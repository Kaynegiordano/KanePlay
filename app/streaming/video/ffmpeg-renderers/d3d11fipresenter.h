#pragma once

#include <d3d11_4.h>
#include <wrl/client.h>

#include <array>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>

// Shows the frames of the frame doubler at an even pace, from a thread of its own.
//
// For each decoded frame, the render thread fills a slot with the interpolated
// frame and the decoded frame, then submits it. The present thread shows the
// interpolated frame, then the decoded one, each for half a stream frame, the way
// AMD's FSR 3 frame generation paces its frames. Keeping this apart from the
// render thread means the time spent interpolating (AMF can take several
// milliseconds) no longer shortens how long a frame stays on screen, which made
// frames flicker.
//
// Two ways to pace:
//  - Queued (V-sync on, or no tearing support): both frames go through the
//    swapchain queue with a sync interval of 1, so each one is shown for one
//    refresh. Ideal when the display runs at twice the stream rate.
//  - Timed (V-sync off, with tearing support): each frame is presented half a
//    stream frame after the previous one, measured on the stream's own clock.
//    Ideal on VRR displays, which then show every frame for the same time.
class D3D11FiPresenter
{
public:
    struct Callbacks {
        // Serialize access to the D3D11 immediate context with the renderer
        std::function<void()> lock;
        std::function<void()> unlock;

        // Draws a video sized frame to the back buffer, with the overlays, and
        // presents it. Called with the context locked.
        std::function<HRESULT(ID3D11ShaderResourceView* frame, int width, int height, UINT syncInterval, UINT flags)> present;

        // Presenting failed: the device needs to be reset
        std::function<void()> presentFailed;

        // The last present that reached the screen, and on which refresh
        // (IDXGISwapChain::GetFrameStatistics()), for the statistics
        std::function<bool(UINT& presentCount, UINT& refreshCount)> frameStatistics;
        // Live diagnostic toggle: keep the presentation cadence but show decoded frames twice.
        std::function<bool()> duplicateDecodedForTest;
    };

    // A frame to show: the interpolated frame (drawn to interpolatedTarget)
    // and the decoded frame (copied to decoded)
    struct Slot {
        Microsoft::WRL::ComPtr<ID3D11Texture2D> interpolated;
        Microsoft::WRL::ComPtr<ID3D11RenderTargetView> interpolatedTarget;
        Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> interpolatedView;
        Microsoft::WRL::ComPtr<ID3D11Texture2D> decoded;
        Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> decodedView;
        int width = 0;
        int height = 0;
    };

    D3D11FiPresenter();
    ~D3D11FiPresenter();

    bool initialize(ID3D11Device5* device, ID3D11DeviceContext4* context, DXGI_FORMAT format,
                    int streamFps, bool timed, bool allowTearing, const Callbacks& callbacks);

    // Render thread, with the context locked: a free slot for a frame of this size,
    // or nullptr on failure. It stays reserved until submit() or cancel().
    Slot* acquire(int width, int height);
    void cancel(Slot* slot);

    // Render thread, with the context locked: queues the slot to be shown.
    // pts is the 90 kHz timestamp of the decoded frame, to pace on the stream clock.
    void submit(Slot* slot, bool hasInterpolated, int64_t pts);

    // Waits until every submitted frame is on screen, before presenting
    // from somewhere else. The context must not be locked.
    void flush();

    // Stops the present thread. The context must not be locked.
    void stop();

    bool isTimed() const { return m_Timed; }

private:
    enum class SlotState { Free, Filling, Queued, Showing };

    struct Job {
        int slot;
        bool hasInterpolated;
        UINT64 fenceValue;
        uint64_t submitUs;
    };

    // Frames waiting beyond this are dropped, oldest first, to catch up
    static constexpr size_t k_MaxQueued = 3;

    // Waiting, plus the one shown and the one being filled
    static constexpr int k_Slots = (int)k_MaxQueued + 2;

    bool createSlot(Slot& slot, int width, int height);
    void presentThread();
    void showJob(Job& job, bool backlog);
    bool presentSlot(Slot& slot, bool interpolated);
    void waitUntil(uint64_t targetUs);
    void checkBlockingPresent(uint64_t durationUs);
    void recordInterval(uint64_t presentUs, bool interpolated);
    void recordDisplayStatistics();
    void updatePeriod(int64_t pts);
    void logStats();

    Microsoft::WRL::ComPtr<ID3D11Device5> m_Device;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext4> m_Context;
    DXGI_FORMAT m_Format = DXGI_FORMAT_UNKNOWN;
    Callbacks m_Callbacks;
    // Switched off by the present thread if presents block (see checkBlockingPresent())
    std::atomic<bool> m_Timed { false };
    // Diagnostic: present the decoded frame twice without changing the pacing.
    bool m_DuplicateDecodedForTest = false;
    UINT m_SyncInterval = 1;
    UINT m_PresentFlags = 0;

    std::array<Slot, k_Slots> m_Slots;
    std::array<SlotState, k_Slots> m_SlotStates {};

    // Ready when the GPU finished drawing a slot
    Microsoft::WRL::ComPtr<ID3D11Fence> m_Fence;
    UINT64 m_FenceValue = 0;
    HANDLE m_FenceEvent = nullptr;
    HANDLE m_Timer = nullptr;

    std::thread m_Thread;
    std::mutex m_Lock;
    std::condition_variable m_JobReady;
    std::condition_variable m_Idle;
    std::deque<Job> m_Jobs;
    bool m_Showing = false;
    bool m_Stopping = false;

    // Stream frame period in microseconds, averaged from the timestamps
    double m_NominalPeriodUs = 0;
    double m_PeriodUs = 0;
    int64_t m_LastPts = 0;
    bool m_HasLastPts = false;

    // Present thread only
    uint64_t m_GridUs = 0;
    uint64_t m_LastPresentUs = 0;
    bool m_LastWasInterpolated = false;

    // Statistics, logged when stopping
    // Refreshes each frame stayed on screen: 1, 2, 3 and more, from the display's statistics
    UINT m_LastStatsPresent = 0;
    UINT m_LastStatsRefresh = 0;
    std::array<uint64_t, 4> m_RefreshHistogram {};
    uint64_t m_TimedPresents = 0;
    uint64_t m_BlockingPresents = 0;
    uint64_t m_Shown = 0;
    uint64_t m_ShownInterpolated = 0;
    uint64_t m_DroppedFrames = 0;
    uint64_t m_SkippedInterpolated = 0;
    uint64_t m_ShortIntervals = 0;
    uint64_t m_LongIntervals = 0;
    uint64_t m_Intervals = 0;
    uint64_t m_TotalLatencyUs = 0;
    uint64_t m_MaxLatencyUs = 0;
};
