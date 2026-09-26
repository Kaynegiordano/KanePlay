#pragma once

#include <d3d11_4.h>
#include <wrl/client.h>

#include <memory>

// Frame interpolation with the FRC (frame rate conversion) component of AMD's
// Advanced Media Framework. The AMF runtime ships with the AMD driver, so this
// only works on AMD GPUs; D3D11FrameInterpolator uses its own shaders elsewhere.
class D3D11AmfFrc
{
public:
    D3D11AmfFrc();
    ~D3D11AmfFrc();

    // Loads the AMF runtime and checks that FRC interpolates between the two
    // latest frames on this device. Returns false if it can't be used.
    bool initialize(ID3D11Device* device, ID3D11DeviceContext* context,
                    DXGI_FORMAT format, int width, int height);

    // Submits the newest frame and returns the frame halfway between it and
    // the previous one, or nullptr if there is none (first frame, error).
    ID3D11ShaderResourceView* interpolate(ID3D11Texture2D* frame);

    // True once AMF failed repeatedly, so the caller can stop using it
    bool hasFailed() const;

    // Forgets the previous frame
    void reset();

private:
    struct Impl;
    std::unique_ptr<Impl> m;
};
