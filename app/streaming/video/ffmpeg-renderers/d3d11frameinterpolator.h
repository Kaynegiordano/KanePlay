#pragma once

#include <d3d11_4.h>
#include <wrl/client.h>

#include <array>

// Doubles the frame rate of the stream by drawing a motion compensated frame
// halfway between each pair of decoded frames.
//
// It only relies on D3D11 compute and pixel shaders (feature level 11.0), so it
// works on any GPU the D3D11 renderer runs on, whatever the vendor.
//
// The renderer converts each decoded frame to RGB into the target returned by
// beginFrame(), then calls analyzeFrame() to estimate the motion from the
// previous frame, and finally draws the interpolated and the current frame.
class D3D11FrameInterpolator
{
public:
    D3D11FrameInterpolator();

    bool initialize(ID3D11Device* device, ID3D11DeviceContext* context, DXGI_FORMAT frameFormat);

    // Returns the render target the next decoded frame must be converted into,
    // at the video resolution. A new size discards the previous frame.
    ID3D11RenderTargetView* beginFrame(int width, int height);

    // Estimates the motion between the previous frame and the one converted
    // since beginFrame(). Returns false if there is nothing to interpolate yet.
    bool analyzeFrame();

    // Both draw into the currently bound render target using the currently
    // bound vertex buffer, which must map the video with texcoords from 0 to 1.
    void drawInterpolated();
    void drawCurrent();
    void drawTexture(ID3D11ShaderResourceView* texture);

    // Forgets the previous frame, for example after the stream was interrupted
    void reset();

    // The frame converted since beginFrame(), in RGB at the video resolution
    ID3D11Texture2D* currentFrameTexture() const { return m_Frames[m_CurrentFrame].rgb.Get(); }

private:
    // Level 0 is half the video resolution, each following level halves it again
    static constexpr int k_Levels = 4;
    static constexpr int k_BlockSize = 32;

    struct Frame {
        Microsoft::WRL::ComPtr<ID3D11Texture2D> rgb;
        Microsoft::WRL::ComPtr<ID3D11RenderTargetView> rgbTarget;
        Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> rgbView;
        std::array<Microsoft::WRL::ComPtr<ID3D11ShaderResourceView>, k_Levels> lumaViews;
        std::array<Microsoft::WRL::ComPtr<ID3D11UnorderedAccessView>, k_Levels> lumaTargets;
    };

    struct Field {
        Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> view;
        Microsoft::WRL::ComPtr<ID3D11UnorderedAccessView> target;
    };

    bool createSizeDependentResources(int width, int height);
    bool createTexture(int width, int height, DXGI_FORMAT format, UINT bindFlags,
                       Microsoft::WRL::ComPtr<ID3D11Texture2D>& texture);
    bool createField(Field& field);
    bool createConstantBuffer(const void* data, UINT size, Microsoft::WRL::ComPtr<ID3D11Buffer>& buffer);
    void updateMotionConstants(bool hasTemporal);
    int levelWidth(int level) const;
    int levelHeight(int level) const;

    Microsoft::WRL::ComPtr<ID3D11Device> m_Device;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> m_Context;
    DXGI_FORMAT m_FrameFormat;

    Microsoft::WRL::ComPtr<ID3D11ComputeShader> m_PyramidShader;
    Microsoft::WRL::ComPtr<ID3D11ComputeShader> m_MotionShader;
    Microsoft::WRL::ComPtr<ID3D11ComputeShader> m_FilterShader;
    Microsoft::WRL::ComPtr<ID3D11PixelShader> m_InterpolateShader;
    Microsoft::WRL::ComPtr<ID3D11PixelShader> m_BlitShader;
    Microsoft::WRL::ComPtr<ID3D11SamplerState> m_Sampler;

    int m_Width;
    int m_Height;
    int m_GridWidth;
    int m_GridHeight;

    std::array<Frame, 2> m_Frames;
    int m_CurrentFrame;
    int m_ValidFrames;

    // Raw motion of each level, then the filtered motion of this frame and of
    // the previous one (used as a prediction for the next one)
    std::array<Field, k_Levels> m_LevelFields;
    std::array<Field, 2> m_FinalFields;
    int m_CurrentField;
    bool m_HasMotionHistory;

    std::array<Microsoft::WRL::ComPtr<ID3D11Buffer>, k_Levels> m_PyramidConstants;
    std::array<Microsoft::WRL::ComPtr<ID3D11Buffer>, k_Levels> m_MotionConstants;
    int m_MotionConstantsTemporal;
    Microsoft::WRL::ComPtr<ID3D11Buffer> m_FilterConstants;
    Microsoft::WRL::ComPtr<ID3D11Buffer> m_InterpolateConstants;
};
