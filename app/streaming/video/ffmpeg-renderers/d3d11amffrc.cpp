#include "d3d11amffrc.h"

#include <core/Factory.h>
#include <components/FRC.h>

#include <SDL.h>

#include <array>
#include <cmath>

using Microsoft::WRL::ComPtr;

// Set by AMF on the D3D11 textures it allocates as slices of a texture array
static const GUID k_AMFTextureArrayIndexGUID = { 0x28115527, 0xe7c3, 0x4b66, { 0x99, 0xd3, 0x4f, 0x2a, 0xe6, 0xb4, 0x7f, 0xaf } };

// DX11 support in FRC arrived with AMF 1.4.34
#define AMF_FRC_DX11_MIN_VERSION AMF_MAKE_FULL_VERSION(1, 4, 34, 0)

// Consecutive failures after which AMF is abandoned for this session
#define MAX_FAILURES 30

struct D3D11AmfFrc::Impl
{
    HMODULE module = nullptr;
    amf::AMFFactory* factory = nullptr;
    amf::AMFContextPtr context;
    amf::AMFComponentPtr frc;

    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> deviceContext;
    DXGI_FORMAT format = DXGI_FORMAT_UNKNOWN;
    int width = 0;
    int height = 0;

    // AMF may keep the previous input around, so each frame gets its own copy
    std::array<ComPtr<ID3D11Texture2D>, 3> inputs;
    int nextInput = 0;
    bool primed = false;

    ComPtr<ID3D11Texture2D> output;
    ComPtr<ID3D11ShaderResourceView> outputView;

    int consecutiveFailures = 0;
    LARGE_INTEGER submitTime = {};
    uint64_t interpolatedFrames = 0;
    uint64_t missedFrames = 0;
    uint64_t totalWaitUs = 0;

    ~Impl()
    {
        if (interpolatedFrames + missedFrames > 0) {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "AMF FRC: %llu frames interpolated, %llu missed, %.2f ms average wait",
                        (unsigned long long)interpolatedFrames, (unsigned long long)missedFrames,
                        interpolatedFrames ? totalWaitUs / 1000.0 / interpolatedFrames : 0.0);
        }

        if (frc) {
            frc->Terminate();
            frc = nullptr;
        }
        if (context) {
            context->Terminate();
            context = nullptr;
        }

        // The factory belongs to the runtime
        factory = nullptr;
        if (module != nullptr) {
            FreeLibrary(module);
        }
    }

    ID3D11Texture2D* copyToNextInput(ID3D11Texture2D* frame)
    {
        ID3D11Texture2D* input = inputs[nextInput].Get();
        nextInput = (nextInput + 1) % (int)inputs.size();
        deviceContext->CopyResource(input, frame);
        return input;
    }

    AMF_RESULT submit(ID3D11Texture2D* input)
    {
        amf::AMFSurfacePtr surface;
        AMF_RESULT res = context->CreateSurfaceFromDX11Native(input, &surface, nullptr);
        if (res != AMF_OK) {
            return res;
        }

        res = frc->SubmitInput(surface);
        if (res == AMF_INPUT_FULL) {
            // Outputs nobody collected (after an error) are in the way
            drainOutputs();
            res = frc->SubmitInput(surface);
        }
        return res;
    }

    void drainOutputs()
    {
        for (int i = 0; i < 8; i++) {
            amf::AMFDataPtr data;
            if (frc->QueryOutput(&data) != AMF_OK || data == nullptr) {
                break;
            }
        }
    }

    // Waits for the interpolated frame of the last submission
    amf::AMFSurfacePtr queryOutput(uint64_t timeoutUs)
    {
        LARGE_INTEGER frequency, start, now;
        QueryPerformanceFrequency(&frequency);
        QueryPerformanceCounter(&start);

        for (;;) {
            amf::AMFDataPtr data;
            AMF_RESULT res = frc->QueryOutput(&data);
            if ((res == AMF_OK || res == AMF_REPEAT) && data != nullptr) {
                return amf::AMFSurfacePtr(data);
            }
            if (res != AMF_OK && res != AMF_REPEAT && res != AMF_NEED_MORE_INPUT) {
                return nullptr;
            }

            QueryPerformanceCounter(&now);
            if ((uint64_t)((now.QuadPart - start.QuadPart) * 1000000 / frequency.QuadPart) >= timeoutUs) {
                return nullptr;
            }
            SwitchToThread();
        }
    }

    bool copyOutput(amf::AMFSurfacePtr& surface)
    {
        amf::AMFPlane* plane = surface->GetPlaneAt(0);
        if (plane == nullptr || plane->GetNative() == nullptr) {
            return false;
        }

        auto texture = (ID3D11Texture2D*)plane->GetNative();
        UINT slice = 0;
        UINT size = sizeof(slice);
        if (FAILED(texture->GetPrivateData(k_AMFTextureArrayIndexGUID, &size, &slice))) {
            slice = 0;
        }

        D3D11_TEXTURE2D_DESC desc;
        texture->GetDesc(&desc);
        if (desc.Format != format || (int)desc.Width < width || (int)desc.Height < height) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "AMF FRC: unexpected output texture %ux%u format %d",
                         desc.Width, desc.Height, desc.Format);
            return false;
        }

        D3D11_BOX box = { 0, 0, 0, (UINT)width, (UINT)height, 1 };
        deviceContext->CopySubresourceRegion(output.Get(), 0, 0, 0, 0, texture,
                                             D3D11CalcSubresource(0, slice, desc.MipLevels), &box);
        return true;
    }

    // Reads the center pixel of the output texture, as a grey level
    float readOutputGrey()
    {
        D3D11_TEXTURE2D_DESC desc = {};
        desc.Width = 1;
        desc.Height = 1;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = format;
        desc.SampleDesc.Count = 1;
        desc.Usage = D3D11_USAGE_STAGING;
        desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;

        ComPtr<ID3D11Texture2D> staging;
        if (FAILED(device->CreateTexture2D(&desc, nullptr, &staging))) {
            return -1;
        }

        D3D11_BOX box = { (UINT)width / 2, (UINT)height / 2, 0, (UINT)width / 2 + 1, (UINT)height / 2 + 1, 1 };
        deviceContext->CopySubresourceRegion(staging.Get(), 0, 0, 0, 0, output.Get(), 0, &box);

        D3D11_MAPPED_SUBRESOURCE mapped;
        if (FAILED(deviceContext->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped))) {
            return -1;
        }

        uint32_t pixel = *(const uint32_t*)mapped.pData;
        deviceContext->Unmap(staging.Get(), 0);

        // Green channel
        if (format == DXGI_FORMAT_R10G10B10A2_UNORM) {
            return ((pixel >> 10) & 0x3FF) / 1023.0f;
        }
        return ((pixel >> 8) & 0xFF) / 255.0f;
    }

    // The documentation doesn't say which frames the output sits between. Showing
    // it in the wrong place would make motion go back and forth, so check that
    // submitting frame B right after frame A gives a frame between A and B.
    bool selfTest()
    {
        const float greyA = 0.40f, greyB = 0.48f;
        ComPtr<ID3D11RenderTargetView> targets[2];
        for (int i = 0; i < 2; i++) {
            if (FAILED(device->CreateRenderTargetView(inputs[i].Get(), nullptr, &targets[i]))) {
                return false;
            }
        }

        const float colorA[4] = { greyA, greyA, greyA, 1.0f };
        const float colorB[4] = { greyB, greyB, greyB, 1.0f };
        deviceContext->ClearRenderTargetView(targets[0].Get(), colorA);
        deviceContext->ClearRenderTargetView(targets[1].Get(), colorB);

        bool ok = false;
        if (submit(inputs[0].Get()) == AMF_OK) {
            // Nothing to interpolate from a single frame
            amf::AMFSurfacePtr early = queryOutput(20000);
            if (early != nullptr) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "AMF FRC: unexpected output after the first frame");
            }
            else if (submit(inputs[1].Get()) == AMF_OK) {
                amf::AMFSurfacePtr result = queryOutput(50000);
                if (result == nullptr) {
                    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                                "AMF FRC: no output after the second frame (it needs a future frame)");
                }
                else if (copyOutput(result)) {
                    float grey = readOutputGrey();
                    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                                "AMF FRC: self-test output %.3f between %.2f and %.2f",
                                grey, greyA, greyB);
                    ok = grey >= greyA - 0.02f && grey <= greyB + 0.02f;
                }
            }
        }

        frc->Flush();
        drainOutputs();
        nextInput = 0;
        primed = false;
        return ok;
    }
};

D3D11AmfFrc::D3D11AmfFrc() :
    m(std::make_unique<Impl>())
{

}

D3D11AmfFrc::~D3D11AmfFrc() = default;

bool D3D11AmfFrc::initialize(ID3D11Device* device, ID3D11DeviceContext* context,
                             DXGI_FORMAT format, int width, int height, bool fastSearch)
{
    m->device = device;
    m->deviceContext = context;
    m->format = format;
    m->width = width;
    m->height = height;

    m->module = LoadLibraryExW(AMF_DLL_NAME, nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (m->module == nullptr) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: AMF runtime not found (not an AMD GPU)");
        return false;
    }

    auto queryVersion = (AMFQueryVersion_Fn)GetProcAddress(m->module, AMF_QUERY_VERSION_FUNCTION_NAME);
    auto init = (AMFInit_Fn)GetProcAddress(m->module, AMF_INIT_FUNCTION_NAME);
    amf_uint64 runtimeVersion = 0;
    if (queryVersion == nullptr || init == nullptr || queryVersion(&runtimeVersion) != AMF_OK) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: invalid AMF runtime");
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "AMF FRC: runtime %d.%d.%d.%d",
                (int)AMF_GET_MAJOR_VERSION(runtimeVersion), (int)AMF_GET_MINOR_VERSION(runtimeVersion),
                (int)AMF_GET_SUBMINOR_VERSION(runtimeVersion), (int)AMF_GET_BUILD_VERSION(runtimeVersion));

    if (runtimeVersion < AMF_FRC_DX11_MIN_VERSION) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: the AMD driver is too old for D3D11 frame rate conversion");
        return false;
    }

    // A runtime older than our headers only knows its own version
    AMF_RESULT res = init(runtimeVersion < AMF_FULL_VERSION ? runtimeVersion : AMF_FULL_VERSION, &m->factory);
    if (res != AMF_OK || m->factory == nullptr) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: AMFInit() failed: %d", res);
        return false;
    }

    // AMF submits work on the device's immediate context from its own code, so
    // make D3D11 serialize it with FFmpeg's decoding and our rendering
    ComPtr<ID3D11Multithread> multithread;
    if (SUCCEEDED(context->QueryInterface(IID_PPV_ARGS(&multithread)))) {
        multithread->SetMultithreadProtected(TRUE);
    }

    res = m->factory->CreateContext(&m->context);
    if (res == AMF_OK) {
        res = m->context->InitDX11(device);
    }
    if (res == AMF_OK) {
        res = m->factory->CreateComponent(m->context, AMFFRC, &m->frc);
    }
    if (res != AMF_OK) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: unable to create the FRC component: %d", res);
        return false;
    }

    m->frc->SetProperty(AMF_FRC_ENGINE_TYPE, (amf_int64)FRC_ENGINE_DX11);
    m->frc->SetProperty(AMF_FRC_MODE, (amf_int64)FRC_ONLY_INTERPOLATED);

    // Waiting for the frame after the next one would add a frame of latency
    m->frc->SetProperty(AMF_FRC_USE_FUTURE_FRAME, false);

    // Where interpolation fails, repeat the frame rather than cross-fade (ghosting)
    m->frc->SetProperty(AMF_FRC_ENABLE_FALLBACK, false);
    m->frc->SetProperty(AMF_FRC_INDICATOR, false);
    m->frc->SetProperty(AMF_FRC_PROFILE, (amf_int64)FRC_PROFILE_HIGH);
    m->frc->SetProperty(AMF_FRC_MV_SEARCH_MODE, (amf_int64)(fastSearch ? FRC_MV_SEARCH_PERFORMANCE : FRC_MV_SEARCH_NATIVE));

    amf::AMF_SURFACE_FORMAT surfaceFormat;
    switch (format) {
    case DXGI_FORMAT_R8G8B8A8_UNORM:
        surfaceFormat = amf::AMF_SURFACE_RGBA;
        break;
    case DXGI_FORMAT_R10G10B10A2_UNORM:
        surfaceFormat = amf::AMF_SURFACE_R10G10B10A2;
        break;
    default:
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: unsupported frame format %d", format);
        return false;
    }

    res = m->frc->Init(surfaceFormat, width, height);
    if (res != AMF_OK) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: Init() failed for %dx%d: %d", width, height, res);
        return false;
    }

    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = format;
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
    for (auto& input : m->inputs) {
        if (FAILED(device->CreateTexture2D(&texDesc, nullptr, &input))) {
            return false;
        }
    }
    if (FAILED(device->CreateTexture2D(&texDesc, nullptr, &m->output)) ||
            FAILED(device->CreateShaderResourceView(m->output.Get(), nullptr, &m->outputView))) {
        return false;
    }

    if (!m->selfTest()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: self-test failed, using KanePlay's own frame interpolation");
        return false;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "AMF FRC: ready for %dx%d frames, %s motion search",
                width, height, fastSearch ? "fast" : "full resolution");
    return true;
}

bool D3D11AmfFrc::submit(ID3D11Texture2D* frame)
{
    ID3D11Texture2D* input = m->copyToNextInput(frame);

    AMF_RESULT res = m->submit(input);
    if (res != AMF_OK) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "AMF FRC: SubmitInput() failed: %d", res);
        m->consecutiveFailures++;
        m->primed = false;
        return false;
    }

    bool hadPrevious = m->primed;
    m->primed = true;
    if (!hadPrevious) {
        m->drainOutputs();
        return false;
    }

    QueryPerformanceCounter(&m->submitTime);
    return true;
}

ID3D11ShaderResourceView* D3D11AmfFrc::collect(uint64_t timeoutUs)
{
    LARGE_INTEGER frequency, end;
    QueryPerformanceFrequency(&frequency);
    amf::AMFSurfacePtr result = m->queryOutput(timeoutUs);
    QueryPerformanceCounter(&end);

    if (result == nullptr || !m->copyOutput(result)) {
        m->missedFrames++;
        m->consecutiveFailures++;
        return nullptr;
    }

    // From the submission, so it includes the GPU work queued before collect()
    m->totalWaitUs += (end.QuadPart - m->submitTime.QuadPart) * 1000000 / frequency.QuadPart;
    m->interpolatedFrames++;
    m->consecutiveFailures = 0;
    return m->outputView.Get();
}

bool D3D11AmfFrc::hasFailed() const
{
    return m->consecutiveFailures >= MAX_FAILURES;
}

double D3D11AmfFrc::averageWaitUs() const
{
    return m->interpolatedFrames ? (double)m->totalWaitUs / m->interpolatedFrames : 0.0;
}

uint64_t D3D11AmfFrc::interpolatedFrames() const
{
    return m->interpolatedFrames;
}

void D3D11AmfFrc::reset()
{
    if (m->frc) {
        m->frc->Flush();
        m->drainOutputs();
    }
    m->primed = false;
}
