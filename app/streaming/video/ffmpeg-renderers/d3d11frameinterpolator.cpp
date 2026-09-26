#include "d3d11frameinterpolator.h"
#include "path.h"

#include <SDL.h>

using Microsoft::WRL::ComPtr;

namespace {

struct PyramidConstants
{
    float invInputSize[2];
    uint32_t outputSize[2];
    uint32_t fromRgb;
    uint32_t padding[3];
};
static_assert(sizeof(PyramidConstants) % 16 == 0, "Constant buffer sizes must be a multiple of 16");

struct MotionConstants
{
    float invLevelSize[2];
    float levelScale;
    float blockSize;

    float sampleSpacing;
    int32_t searchRadius;
    int32_t refineHalf;
    int32_t hasTemporal;

    uint32_t gridSize[2];
    float lambda;
    float padding;
};
static_assert(sizeof(MotionConstants) % 16 == 0, "Constant buffer sizes must be a multiple of 16");

struct FilterConstants
{
    uint32_t gridSize[2];
    float agreement;
    float padding;
};
static_assert(sizeof(FilterConstants) % 16 == 0, "Constant buffer sizes must be a multiple of 16");

struct InterpolateConstants
{
    float videoSize[2];
    float invVideoSize[2];
    float gridSize[2];
    float blockSize;
    float phase;
};
static_assert(sizeof(InterpolateConstants) % 16 == 0, "Constant buffer sizes must be a multiple of 16");

// Exhaustive search radius of the coarsest level, in pixels of that level.
// At 1/16 of the video resolution, this finds motion of up to 224 pixels
// per frame, and the previous frame's motion extends it for steady pans.
#define COARSEST_SEARCH_RADIUS 7

}

D3D11FrameInterpolator::D3D11FrameInterpolator() :
    m_FrameFormat(DXGI_FORMAT_UNKNOWN),
    m_Width(0),
    m_Height(0),
    m_GridWidth(0),
    m_GridHeight(0),
    m_CurrentFrame(0),
    m_ValidFrames(0),
    m_CurrentField(0),
    m_HasMotionHistory(false),
    m_MotionConstantsTemporal(-1),
    m_InterpolatePhase(0.5f)
{

}

bool D3D11FrameInterpolator::initialize(ID3D11Device* device, ID3D11DeviceContext* context, DXGI_FORMAT frameFormat)
{
    HRESULT hr;

    m_Device = device;
    m_Context = context;
    m_FrameFormat = frameFormat;

    {
        QByteArray bytecode = Path::readDataFile("d3d11_fi_pyramid_cs.fxc");
        hr = m_Device->CreateComputeShader(bytecode.constData(), bytecode.length(), nullptr, &m_PyramidShader);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreateComputeShader() failed: %x",
                         hr);
            return false;
        }
    }

    {
        QByteArray bytecode = Path::readDataFile("d3d11_fi_motion_cs.fxc");
        hr = m_Device->CreateComputeShader(bytecode.constData(), bytecode.length(), nullptr, &m_MotionShader);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreateComputeShader() failed: %x",
                         hr);
            return false;
        }
    }

    {
        QByteArray bytecode = Path::readDataFile("d3d11_fi_filter_cs.fxc");
        hr = m_Device->CreateComputeShader(bytecode.constData(), bytecode.length(), nullptr, &m_FilterShader);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreateComputeShader() failed: %x",
                         hr);
            return false;
        }
    }

    {
        QByteArray bytecode = Path::readDataFile("d3d11_fi_interp_pixel.fxc");
        hr = m_Device->CreatePixelShader(bytecode.constData(), bytecode.length(), nullptr, &m_InterpolateShader);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreatePixelShader() failed: %x",
                         hr);
            return false;
        }
    }

    {
        QByteArray bytecode = Path::readDataFile("d3d11_fi_blit_pixel.fxc");
        hr = m_Device->CreatePixelShader(bytecode.constData(), bytecode.length(), nullptr, &m_BlitShader);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreatePixelShader() failed: %x",
                         hr);
            return false;
        }
    }

    {
        D3D11_SAMPLER_DESC samplerDesc = {};
        samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
        samplerDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
        samplerDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
        samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
        samplerDesc.MipLODBias = 0.0f;
        samplerDesc.MaxAnisotropy = 1;
        samplerDesc.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
        samplerDesc.MinLOD = 0.0f;
        samplerDesc.MaxLOD = D3D11_FLOAT32_MAX;

        hr = m_Device->CreateSamplerState(&samplerDesc, &m_Sampler);
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "ID3D11Device::CreateSamplerState() failed: %x",
                         hr);
            return false;
        }
    }

    return true;
}

int D3D11FrameInterpolator::levelWidth(int level) const
{
    int width = m_Width;
    for (int i = 0; i <= level; i++) {
        width = (width + 1) / 2;
    }
    return width;
}

int D3D11FrameInterpolator::levelHeight(int level) const
{
    int height = m_Height;
    for (int i = 0; i <= level; i++) {
        height = (height + 1) / 2;
    }
    return height;
}

bool D3D11FrameInterpolator::createTexture(int width, int height, DXGI_FORMAT format, UINT bindFlags,
                                           ComPtr<ID3D11Texture2D>& texture)
{
    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = format;
    texDesc.SampleDesc.Count = 1;
    texDesc.SampleDesc.Quality = 0;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = bindFlags;
    texDesc.CPUAccessFlags = 0;
    texDesc.MiscFlags = 0;

    HRESULT hr = m_Device->CreateTexture2D(&texDesc, nullptr, &texture);
    if (FAILED(hr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "ID3D11Device::CreateTexture2D() failed: %x",
                     hr);
        return false;
    }

    return true;
}

bool D3D11FrameInterpolator::createField(Field& field)
{
    ComPtr<ID3D11Texture2D> texture;
    if (!createTexture(m_GridWidth, m_GridHeight, DXGI_FORMAT_R16G16B16A16_FLOAT,
                       D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, texture)) {
        return false;
    }

    HRESULT hr = m_Device->CreateShaderResourceView(texture.Get(), nullptr, &field.view);
    if (SUCCEEDED(hr)) {
        hr = m_Device->CreateUnorderedAccessView(texture.Get(), nullptr, &field.target);
    }
    if (FAILED(hr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Unable to create motion field views: %x",
                     hr);
        return false;
    }

    return true;
}

bool D3D11FrameInterpolator::createConstantBuffer(const void* data, UINT size, ComPtr<ID3D11Buffer>& buffer)
{
    D3D11_BUFFER_DESC constDesc = {};
    constDesc.ByteWidth = size;
    constDesc.Usage = D3D11_USAGE_DEFAULT;
    constDesc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    constDesc.CPUAccessFlags = 0;
    constDesc.MiscFlags = 0;

    D3D11_SUBRESOURCE_DATA constData = {};
    constData.pSysMem = data;

    HRESULT hr = m_Device->CreateBuffer(&constDesc, &constData, &buffer);
    if (FAILED(hr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "ID3D11Device::CreateBuffer() failed: %x",
                     hr);
        return false;
    }

    return true;
}

bool D3D11FrameInterpolator::createSizeDependentResources(int width, int height)
{
    HRESULT hr;

    m_Width = width;
    m_Height = height;
    m_GridWidth = (width + k_BlockSize - 1) / k_BlockSize;
    m_GridHeight = (height + k_BlockSize - 1) / k_BlockSize;
    m_ValidFrames = 0;
    m_HasMotionHistory = false;
    m_MotionConstantsTemporal = -1;

    for (Frame& frame : m_Frames) {
        frame = Frame();

        if (!createTexture(width, height, m_FrameFormat,
                           D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE, frame.rgb)) {
            return false;
        }

        hr = m_Device->CreateRenderTargetView(frame.rgb.Get(), nullptr, &frame.rgbTarget);
        if (SUCCEEDED(hr)) {
            hr = m_Device->CreateShaderResourceView(frame.rgb.Get(), nullptr, &frame.rgbView);
        }
        if (FAILED(hr)) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "Unable to create interpolation frame views: %x",
                         hr);
            return false;
        }

        for (int level = 0; level < k_Levels; level++) {
            ComPtr<ID3D11Texture2D> luma;
            if (!createTexture(levelWidth(level), levelHeight(level), DXGI_FORMAT_R16_FLOAT,
                               D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_UNORDERED_ACCESS, luma)) {
                return false;
            }

            hr = m_Device->CreateShaderResourceView(luma.Get(), nullptr, &frame.lumaViews[level]);
            if (SUCCEEDED(hr)) {
                hr = m_Device->CreateUnorderedAccessView(luma.Get(), nullptr, &frame.lumaTargets[level]);
            }
            if (FAILED(hr)) {
                SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                             "Unable to create luma pyramid views: %x",
                             hr);
                return false;
            }
        }
    }

    for (int level = 0; level < k_Levels; level++) {
        if (!createField(m_LevelFields[level])) {
            return false;
        }
    }
    for (Field& field : m_FinalFields) {
        if (!createField(field)) {
            return false;
        }
    }

    for (int level = 0; level < k_Levels; level++) {
        PyramidConstants constants = {};
        int inputWidth = level == 0 ? m_Width : levelWidth(level - 1);
        int inputHeight = level == 0 ? m_Height : levelHeight(level - 1);
        constants.invInputSize[0] = 1.0f / inputWidth;
        constants.invInputSize[1] = 1.0f / inputHeight;
        constants.outputSize[0] = levelWidth(level);
        constants.outputSize[1] = levelHeight(level);
        constants.fromRgb = level == 0;

        // Filled in by updateMotionConstants()
        MotionConstants motionConstants = {};

        if (!createConstantBuffer(&constants, sizeof(constants), m_PyramidConstants[level]) ||
                !createConstantBuffer(&motionConstants, sizeof(motionConstants), m_MotionConstants[level])) {
            return false;
        }
    }

    {
        FilterConstants constants = {};
        constants.gridSize[0] = m_GridWidth;
        constants.gridSize[1] = m_GridHeight;

        // Vectors within 4 pixels of each other describe the same motion
        constants.agreement = 4.0f;

        if (!createConstantBuffer(&constants, sizeof(constants), m_FilterConstants)) {
            return false;
        }
    }

    {
        InterpolateConstants constants = {};
        constants.videoSize[0] = (float)m_Width;
        constants.videoSize[1] = (float)m_Height;
        constants.invVideoSize[0] = 1.0f / m_Width;
        constants.invVideoSize[1] = 1.0f / m_Height;
        constants.gridSize[0] = (float)m_GridWidth;
        constants.gridSize[1] = (float)m_GridHeight;
        constants.blockSize = (float)k_BlockSize;
        constants.phase = 0.5f;
        m_InterpolatePhase = constants.phase;

        if (!createConstantBuffer(&constants, sizeof(constants), m_InterpolateConstants)) {
            return false;
        }
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Frame interpolation: %dx%d frames, %dx%d motion blocks",
                m_Width, m_Height, m_GridWidth, m_GridHeight);
    return true;
}

void D3D11FrameInterpolator::updateMotionConstants(bool hasTemporal)
{
    if (m_MotionConstantsTemporal == (int)hasTemporal) {
        return;
    }

    for (int level = 0; level < k_Levels; level++) {
        MotionConstants constants = {};
        float levelScale = 1.0f / (float)(2 << level);

        constants.invLevelSize[0] = 1.0f / levelWidth(level);
        constants.invLevelSize[1] = 1.0f / levelHeight(level);
        constants.levelScale = levelScale;
        constants.blockSize = k_BlockSize * levelScale;

        // Matching always uses 8x8 samples. On the finest level, they are
        // spread out to cover the whole block.
        constants.sampleSpacing = SDL_max(1.0f, constants.blockSize / 8);
        constants.searchRadius = level == k_Levels - 1 ? COARSEST_SEARCH_RADIUS : 0;
        constants.refineHalf = level == 0;
        constants.hasTemporal = hasTemporal;
        constants.gridSize[0] = m_GridWidth;
        constants.gridSize[1] = m_GridHeight;

        // Only the exhaustive search needs a nudge towards small motion. Pulling
        // the finer levels towards the coarse answer made object edges worse.
        constants.lambda = level == k_Levels - 1 ? 0.02f : 0.0f;

        m_Context->UpdateSubresource(m_MotionConstants[level].Get(), 0, nullptr, &constants, 0, 0);
    }

    m_MotionConstantsTemporal = hasTemporal;
}

ID3D11RenderTargetView* D3D11FrameInterpolator::beginFrame(int width, int height)
{
    if (width != m_Width || height != m_Height || !m_Frames[0].rgbTarget) {
        if (!createSizeDependentResources(width, height)) {
            m_Width = m_Height = 0;
            return nullptr;
        }
    }

    m_CurrentFrame ^= 1;
    return m_Frames[m_CurrentFrame].rgbTarget.Get();
}

bool D3D11FrameInterpolator::analyzeFrame()
{
    Frame& curr = m_Frames[m_CurrentFrame];
    Frame& prev = m_Frames[m_CurrentFrame ^ 1];
    ID3D11ShaderResourceView* nullViews[4] = {};
    ID3D11UnorderedAccessView* nullTarget = nullptr;

    m_Context->CSSetSamplers(0, 1, m_Sampler.GetAddressOf());

    // Build the luma pyramid of the new frame
    m_Context->CSSetShader(m_PyramidShader.Get(), nullptr, 0);
    for (int level = 0; level < k_Levels; level++) {
        ID3D11ShaderResourceView* input = level == 0 ? curr.rgbView.Get() : curr.lumaViews[level - 1].Get();

        m_Context->CSSetShaderResources(0, 1, &input);
        m_Context->CSSetUnorderedAccessViews(0, 1, curr.lumaTargets[level].GetAddressOf(), nullptr);
        m_Context->CSSetConstantBuffers(0, 1, m_PyramidConstants[level].GetAddressOf());
        m_Context->Dispatch((levelWidth(level) + 7) / 8, (levelHeight(level) + 7) / 8, 1);

        // Unbind the output so the next level can read it
        m_Context->CSSetUnorderedAccessViews(0, 1, &nullTarget, nullptr);
        m_Context->CSSetShaderResources(0, 1, nullViews);
    }

    bool hasPrevious = m_ValidFrames > 0;
    m_ValidFrames = SDL_min(m_ValidFrames + 1, 2);
    if (!hasPrevious) {
        m_Context->CSSetShader(nullptr, nullptr, 0);
        return false;
    }

    // Estimate the motion from the coarsest level to the finest one
    bool hasTemporal = m_HasMotionHistory;
    updateMotionConstants(hasTemporal);
    m_CurrentField ^= 1;

    m_Context->CSSetShader(m_MotionShader.Get(), nullptr, 0);
    for (int level = k_Levels - 1; level >= 0; level--) {
        ID3D11ShaderResourceView* inputs[4] = {
            prev.lumaViews[level].Get(),
            curr.lumaViews[level].Get(),
            level + 1 < k_Levels ? m_LevelFields[level + 1].view.Get() : nullptr,
            hasTemporal ? m_FinalFields[m_CurrentField ^ 1].view.Get() : nullptr,
        };
        ID3D11UnorderedAccessView* output = m_LevelFields[level].target.Get();

        m_Context->CSSetShaderResources(0, 4, inputs);
        m_Context->CSSetUnorderedAccessViews(0, 1, &output, nullptr);
        m_Context->CSSetConstantBuffers(0, 1, m_MotionConstants[level].GetAddressOf());
        m_Context->Dispatch(m_GridWidth, m_GridHeight, 1);

        m_Context->CSSetUnorderedAccessViews(0, 1, &nullTarget, nullptr);
        m_Context->CSSetShaderResources(0, 4, nullViews);
    }

    // Replace isolated wrong vectors
    m_Context->CSSetShader(m_FilterShader.Get(), nullptr, 0);
    m_Context->CSSetShaderResources(0, 1, m_LevelFields[0].view.GetAddressOf());
    m_Context->CSSetUnorderedAccessViews(0, 1, m_FinalFields[m_CurrentField].target.GetAddressOf(), nullptr);
    m_Context->CSSetConstantBuffers(0, 1, m_FilterConstants.GetAddressOf());
    m_Context->Dispatch((m_GridWidth + 7) / 8, (m_GridHeight + 7) / 8, 1);
    m_Context->CSSetUnorderedAccessViews(0, 1, &nullTarget, nullptr);
    m_Context->CSSetShaderResources(0, 1, nullViews);

    m_Context->CSSetShader(nullptr, nullptr, 0);
    m_HasMotionHistory = true;
    return true;
}

void D3D11FrameInterpolator::drawInterpolated(float phase)
{
    if (phase != m_InterpolatePhase) {
        InterpolateConstants constants = {};
        constants.videoSize[0] = (float)m_Width;
        constants.videoSize[1] = (float)m_Height;
        constants.invVideoSize[0] = 1.0f / m_Width;
        constants.invVideoSize[1] = 1.0f / m_Height;
        constants.gridSize[0] = (float)m_GridWidth;
        constants.gridSize[1] = (float)m_GridHeight;
        constants.blockSize = (float)k_BlockSize;
        constants.phase = phase;
        m_Context->UpdateSubresource(m_InterpolateConstants.Get(), 0, nullptr, &constants, 0, 0);
        m_InterpolatePhase = phase;
    }

    Frame& curr = m_Frames[m_CurrentFrame];
    Frame& prev = m_Frames[m_CurrentFrame ^ 1];
    ID3D11ShaderResourceView* inputs[5] = {
        prev.rgbView.Get(),
        curr.rgbView.Get(),
        m_FinalFields[m_CurrentField].view.Get(),
        prev.lumaViews[0].Get(),
        curr.lumaViews[0].Get(),
    };

    m_Context->PSSetShader(m_InterpolateShader.Get(), nullptr, 0);
    m_Context->PSSetSamplers(0, 1, m_Sampler.GetAddressOf());
    m_Context->PSSetShaderResources(0, ARRAYSIZE(inputs), inputs);
    m_Context->PSSetConstantBuffers(1, 1, m_InterpolateConstants.GetAddressOf());
    m_Context->DrawIndexed(6, 0, 0);

    ID3D11ShaderResourceView* nullViews[ARRAYSIZE(inputs)] = {};
    m_Context->PSSetShaderResources(0, ARRAYSIZE(inputs), nullViews);
}

void D3D11FrameInterpolator::drawCurrent()
{
    drawTexture(m_Frames[m_CurrentFrame].rgbView.Get());
}

void D3D11FrameInterpolator::drawTexture(ID3D11ShaderResourceView* texture)
{
    m_Context->PSSetShader(m_BlitShader.Get(), nullptr, 0);
    m_Context->PSSetSamplers(0, 1, m_Sampler.GetAddressOf());
    m_Context->PSSetShaderResources(0, 1, &texture);
    m_Context->DrawIndexed(6, 0, 0);

    ID3D11ShaderResourceView* nullView = nullptr;
    m_Context->PSSetShaderResources(0, 1, &nullView);
}

void D3D11FrameInterpolator::reset()
{
    m_ValidFrames = 0;
    m_HasMotionHistory = false;
}
