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
    // fastSearch uses AMF's downscaled motion search, which AMD recommends for
    // integrated GPUs.
    bool initialize(ID3D11Device* device, ID3D11DeviceContext* context,
                    DXGI_FORMAT format, int width, int height, bool fastSearch);

    // Submits the newest frame. Returns true if an interpolated frame between it
    // and the previous one is on its way, to collect with collect().
    bool submit(ID3D11Texture2D* frame);

    // Waits for the interpolated frame of the last submission, up to timeoutUs,
    // and returns it, or nullptr if it didn't come. It doesn't need the caller's
    // context lock: AMF protects the D3D11 context itself (see initialize()).
    ID3D11ShaderResourceView* collect(uint64_t timeoutUs);

    // True once AMF failed repeatedly, so the caller can stop using it
    bool hasFailed() const;

    // Average time AMF took per interpolated frame so far, and how many frames that is
    double averageWaitUs() const;
    uint64_t interpolatedFrames() const;

    // Forgets the previous frame
    void reset();

private:
    struct Impl;
    std::unique_ptr<Impl> m;
};
