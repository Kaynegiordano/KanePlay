#include "d3d11fipresenter.h"

#include <Limelight.h>
#include <SDL.h>

#include <cmath>

using Microsoft::WRL::ComPtr;

// A frame counts as shown too briefly below this share of half a stream frame,
// and too long above the other one (see recordInterval())
#define SHORT_INTERVAL 0.6
#define LONG_INTERVAL 1.6

// Timers wake up a little early, the rest is spent spinning
#define SPIN_US 1000

// Timed presentation needs Present() to return at once, which it only does when
// frames go straight to the display (tearing or VRR). When the desktop compositor
// is in the way, it blocks until a refresh, and timing frames only adds latency
// and uneven frames. Past this share of blocking calls, frames are queued instead.
#define BLOCKING_PRESENT_US 2000
#define BLOCKING_CHECK_PRESENTS 240
#define BLOCKING_MAX_SHARE 0.1

D3D11FiPresenter::D3D11FiPresenter()
{
    m_SlotStates.fill(SlotState::Free);
}

D3D11FiPresenter::~D3D11FiPresenter()
{
    stop();

    if (m_FenceEvent != nullptr) {
        CloseHandle(m_FenceEvent);
    }
    if (m_Timer != nullptr) {
        CloseHandle(m_Timer);
    }
}

bool D3D11FiPresenter::initialize(ID3D11Device5* device, ID3D11DeviceContext4* context, DXGI_FORMAT format,
                                  int streamFps, int refreshRate, bool timed, bool allowTearing, const Callbacks& callbacks)
{
    m_Device = device;
    m_Context = context;
    m_Format = format;
    m_Callbacks = callbacks;
    m_Timed = timed;
    const char* duplicateDecoded = SDL_getenv("KANEPLAY_FI_TEST_DUPLICATE");
    m_DuplicateDecodedForTest = duplicateDecoded != nullptr && SDL_strcmp(duplicateDecoded, "1") == 0;
    m_SyncInterval = timed ? 0 : 1;
    m_PresentFlags = timed && allowTearing ? DXGI_PRESENT_ALLOW_TEARING : 0;
    m_NominalPeriodUs = m_PeriodUs = 1000000.0 / SDL_max(streamFps, 1);
    m_RefreshUs = 1000000.0 / SDL_max(refreshRate, 1);
    m_MeasuredRefreshUs = m_RefreshUs;

    // Timing is more accurate if the present thread waits for the GPU to finish
    // a frame before presenting it. Without a fence, frames are just presented.
    if (SUCCEEDED(m_Device->CreateFence(0, D3D11_FENCE_FLAG_NONE, IID_PPV_ARGS(&m_Fence)))) {
        m_FenceEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
        if (m_FenceEvent == nullptr) {
            m_Fence.Reset();
        }
    }

    // A high resolution timer avoids Sleep()'s coarse granularity
    m_Timer = CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
    if (m_Timer == nullptr) {
        m_Timer = CreateWaitableTimerExW(nullptr, nullptr, 0, TIMER_ALL_ACCESS);
    }

    m_Thread = std::thread(&D3D11FiPresenter::presentThread, this);

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Frame interpolation: %s presentation on its own thread",
                timed ? "timed (tearing)" : "queued (V-sync)");
    if (m_DuplicateDecodedForTest) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Frame interpolation diagnostic: presenting each decoded frame twice");
    }
    return true;
}

void D3D11FiPresenter::stop()
{
    {
        std::lock_guard<std::mutex> guard(m_Lock);
        if (!m_Thread.joinable()) {
            return;
        }
        m_Stopping = true;
    }
    m_JobReady.notify_all();
    m_Thread.join();

    logStats();
}

bool D3D11FiPresenter::createTexture(Texture& texture, int width, int height, bool renderTarget)
{
    texture = Texture();

    D3D11_TEXTURE2D_DESC texDesc = {};
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.MipLevels = 1;
    texDesc.ArraySize = 1;
    texDesc.Format = m_Format;
    texDesc.SampleDesc.Count = 1;
    texDesc.Usage = D3D11_USAGE_DEFAULT;
    texDesc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;

    HRESULT hr = m_Device->CreateTexture2D(&texDesc, nullptr, &texture.texture);
    if (SUCCEEDED(hr) && renderTarget) {
        hr = m_Device->CreateRenderTargetView(texture.texture.Get(), nullptr, &texture.target);
    }
    if (SUCCEEDED(hr)) {
        hr = m_Device->CreateShaderResourceView(texture.texture.Get(), nullptr, &texture.view);
    }
    if (FAILED(hr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Frame interpolation: unable to create presentation textures: %x",
                     hr);
        texture = Texture();
        return false;
    }
    return true;
}

int D3D11FiPresenter::planFrames(int64_t pts, bool consecutive, float* phases, int maxPhases, bool& showDecoded)
{
    // Time since the previous decoded frame, on the stream's clock (90 kHz
    // timestamps, which wrap around)
    double deltaUs = 0;
    if (m_PlanHasLastPts) {
        deltaUs = (int32_t)((uint32_t)pts - (uint32_t)m_PlanLastPts) * 1000000.0 / 90000;
    }
    m_PlanLastPts = pts;
    m_PlanHasLastPts = true;

    showDecoded = true;

    if (m_Timed) {
        // Halfway, then the decoded frame, both timed by the present thread
        if (!consecutive) {
            return 0;
        }
        phases[0] = 0.5f;
        return 1;
    }

    // The display's refresh rate may not be what it claims: with VRR (G-SYNC,
    // FreeSync) and V-sync, it runs as fast as frames come, up to a cap below
    // its maximum. Planning more frames than it shows would only pile them up.
    double refreshUs = m_MeasuredRefreshUs;

    // Nothing to interpolate from: the decoded frame gets the next refresh
    if (!consecutive || deltaUs <= 0) {
        m_NextRefreshUs = refreshUs;
        return 0;
    }

    // More frames waiting than until this one, and a refresh more: the display
    // fell behind (network jitter, a slow frame). One refresh is skipped, a
    // small jump in time, rather than the latency staying up for good.
    if (m_PendingFrames > deltaUs / refreshUs + 1) {
        m_NextRefreshUs += refreshUs;
        m_CatchUpRefreshes++;
    }

    // Each refresh shows the stream as it was one refresh after the frame the
    // previous refresh showed. The refreshes that fall before this frame get
    // frames interpolated at their moment. One that falls within a tenth of a
    // refresh of this frame shows the decoded frame itself, and the count starts
    // again from it, so a steady 60 FPS on 120 Hz alternates exact halves and
    // decoded frames.
    double snapUs = refreshUs * 0.1;
    int count = 0;
    while (m_NextRefreshUs < deltaUs - snapUs) {
        if (count < maxPhases) {
            phases[count++] = (float)(m_NextRefreshUs / deltaUs);
        }
        else {
            // Too many for a slot: the previous frame stays on screen longer
            m_UnplannedRefreshes++;
        }
        m_NextRefreshUs += refreshUs;
    }

    if (m_NextRefreshUs <= deltaUs + snapUs) {
        showDecoded = true;
        m_NextRefreshUs = refreshUs;
    }
    else {
        // The next refresh falls well after this frame: it shows a frame
        // interpolated towards the next decoded one
        showDecoded = false;
        m_NextRefreshUs -= deltaUs;
    }

    return count;
}

D3D11FiPresenter::Slot* D3D11FiPresenter::acquire(int width, int height)
{
    int index = -1;
    {
        std::lock_guard<std::mutex> guard(m_Lock);

        // Too far behind: the oldest waiting frame goes, so the display catches up
        while (m_Jobs.size() >= k_MaxQueued) {
            m_SlotStates[m_Jobs.front().slot] = SlotState::Free;
            m_PendingFrames -= m_Jobs.front().interpolatedCount + (m_Jobs.front().showDecoded ? 1 : 0);
            m_Jobs.pop_front();
            m_DroppedFrames++;
        }

        for (int i = 0; i < k_Slots; i++) {
            if (m_SlotStates[i] == SlotState::Free) {
                index = i;
                m_SlotStates[i] = SlotState::Filling;
                break;
            }
        }
    }

    // Can't happen: at most k_MaxQueued slots wait, one is shown and this one is filled
    if (index < 0) {
        return nullptr;
    }

    // Interpolated frames are created when first needed (see interpolatedTarget())
    Slot& slot = m_Slots[index];
    if (slot.width != width || slot.height != height || !slot.decoded.texture) {
        slot = Slot();
        if (!createTexture(slot.decoded, width, height, false)) {
            cancel(&slot);
            return nullptr;
        }
        slot.width = width;
        slot.height = height;
    }
    return &slot;
}

ID3D11RenderTargetView* D3D11FiPresenter::interpolatedTarget(Slot* slot, int index)
{
    Texture& texture = slot->interpolated[index];
    if (!texture.texture && !createTexture(texture, slot->width, slot->height, true)) {
        return nullptr;
    }
    return texture.target.Get();
}

void D3D11FiPresenter::cancel(Slot* slot)
{
    std::lock_guard<std::mutex> guard(m_Lock);
    m_SlotStates[slot - m_Slots.data()] = SlotState::Free;
}

void D3D11FiPresenter::submit(Slot* slot, int interpolatedCount, bool showDecoded, int64_t pts)
{
    Job job;
    job.slot = (int)(slot - m_Slots.data());
    job.interpolatedCount = interpolatedCount;
    // Something has to be shown
    job.showDecoded = showDecoded || interpolatedCount == 0;
    m_PendingFrames += interpolatedCount + (job.showDecoded ? 1 : 0);
    job.fenceValue = 0;
    job.submitUs = LiGetMicroseconds();

    // Tells the present thread when the GPU is done with this slot
    if (m_Fence && SUCCEEDED(m_Context->Signal(m_Fence.Get(), m_FenceValue + 1))) {
        job.fenceValue = ++m_FenceValue;
    }
    m_Context->Flush();

    {
        std::lock_guard<std::mutex> guard(m_Lock);
        updatePeriod(pts);
        m_SlotStates[job.slot] = SlotState::Queued;
        m_Jobs.push_back(job);
    }
    m_JobReady.notify_one();
}

void D3D11FiPresenter::updatePeriod(int64_t pts)
{
    // The stream's own clock (90 kHz timestamps) tells the frame rate of the
    // host without the jitter of the network
    if (m_HasLastPts) {
        int32_t delta = (int32_t)((uint32_t)pts - (uint32_t)m_LastPts);
        double deltaUs = delta * 1000000.0 / 90000;
        if (deltaUs > m_NominalPeriodUs * 0.5 && deltaUs < m_NominalPeriodUs * 1.5) {
            m_PeriodUs += (deltaUs - m_PeriodUs) * 0.05;
        }
    }
    m_LastPts = pts;
    m_HasLastPts = true;
}

void D3D11FiPresenter::flush()
{
    std::unique_lock<std::mutex> guard(m_Lock);
    m_Idle.wait(guard, [this] { return (m_Jobs.empty() && !m_Showing) || !m_Thread.joinable() || m_Stopping; });
}

void D3D11FiPresenter::presentThread()
{
    SDL_SetThreadPriority(SDL_THREAD_PRIORITY_TIME_CRITICAL);

    for (;;) {
        Job job;
        bool backlog;
        {
            std::unique_lock<std::mutex> guard(m_Lock);
            m_Showing = false;
            m_Idle.notify_all();

            m_JobReady.wait(guard, [this] { return m_Stopping || !m_Jobs.empty(); });
            if (m_Stopping) {
                break;
            }

            job = m_Jobs.front();
            m_Jobs.pop_front();
            m_SlotStates[job.slot] = SlotState::Showing;
            m_Showing = true;

            // With frames arriving unevenly, the next one is often waiting
            // already. Two of them mean the display is really falling behind.
            backlog = m_Jobs.size() >= 2;
        }

        showJob(job, backlog);

        std::lock_guard<std::mutex> guard(m_Lock);
        m_SlotStates[job.slot] = SlotState::Free;
    }

    std::lock_guard<std::mutex> guard(m_Lock);
    m_Showing = false;
    m_Idle.notify_all();
}

void D3D11FiPresenter::showJob(Job& job, bool backlog)
{
    Slot& slot = m_Slots[job.slot];

    // Nothing can be shown before the GPU is done drawing it
    if (job.fenceValue != 0 && m_Fence->GetCompletedValue() < job.fenceValue &&
            SUCCEEDED(m_Fence->SetEventOnCompletion(job.fenceValue, m_FenceEvent))) {
        WaitForSingleObject(m_FenceEvent, 100);
    }

    double halfPeriodUs;
    {
        std::lock_guard<std::mutex> guard(m_Lock);
        halfPeriodUs = m_PeriodUs / 2;
    }

    // When another frame is already waiting, showing these interpolated frames
    // would delay everything further: only the last frame of the job is shown
    int first = 0;
    if (backlog) {
        first = job.showDecoded ? job.interpolatedCount : job.interpolatedCount - 1;
        m_SkippedInterpolated += first;
        m_PendingFrames -= first;
    }

    if (!m_Timed) {
        // One frame per refresh, through the swapchain queue: Present() returns
        // once the display took the previous frame. Between two frames of the
        // same job, nothing else is waited for, so the time between them is
        // how long the display takes per frame.
        bool shown = false;
        uint64_t previousUs = 0;
        auto measure = [this, &previousUs] {
            uint64_t now = LiGetMicroseconds();
            if (previousUs != 0) {
                double intervalUs = (double)(now - previousUs);
                if (intervalUs > m_RefreshUs * 0.5 && intervalUs < m_RefreshUs * 2) {
                    double measured = m_MeasuredRefreshUs;
                    m_MeasuredRefreshUs = measured + (intervalUs - measured) * 0.02;
                }
            }
            previousUs = now;
        };
        for (int i = first; i < job.interpolatedCount; i++) {
            bool presented = presentSlot(slot, i);
            m_PendingFrames--;
            if (!presented) {
                m_PendingFrames -= job.interpolatedCount - 1 - i + (job.showDecoded ? 1 : 0);
                return;
            }
            measure();
            shown = true;
        }
        if (job.showDecoded) {
            shown = presentSlot(slot, -1);
            m_PendingFrames--;
            if (shown) {
                measure();
            }
        }
        if (shown) {
            uint64_t latencyUs = LiGetMicroseconds() - job.submitUs;
            m_TotalLatencyUs += latencyUs;
        m_LatencySamples++;
            m_MaxLatencyUs = SDL_max(m_MaxLatencyUs, latencyUs);
        }
        return;
    }

    bool interpolated = job.interpolatedCount > 0 && first == 0;

    {
        // Frames are shown on a steady grid of stream periods, like a jitter
        // buffer: a frame that arrives early waits for its place, a late one is
        // shown as soon as it's ready and the grid moves with it. Network jitter
        // then becomes a steady bit of latency rather than frames staying on
        // screen for uneven times.
        double periodUs = halfPeriodUs * 2;
        uint64_t ready = LiGetMicroseconds();
        double slack = (double)m_GridUs - (double)ready;
        if (m_GridUs == 0 || slack < -periodUs || slack > periodUs) {
            // First frame, or after a pause: start a new grid
            m_GridUs = ready;
            slack = 0;
        }

        uint64_t target = SDL_max(ready, m_GridUs);

        // Never less than half a frame after the previous frame
        target = SDL_max(target, m_LastPresentUs + (uint64_t)(halfPeriodUs * 0.9));
        waitUntil(target);

        // The next place is a period later, drawn back a little while frames keep
        // arriving early, so the delay of a late frame doesn't stay forever
        double drift = slack > 0 ? SDL_min(slack, 3000.0) * 0.08 : 0;
        m_GridUs = target + (uint64_t)(periodUs - drift);
    }

    // Timed jobs are shown in one go: they no longer count as waiting
    m_PendingFrames -= job.interpolatedCount - first + 1;

    if (interpolated) {
        if (!presentSlot(slot, 0)) {
            return;
        }
        waitUntil(m_LastPresentUs + (uint64_t)halfPeriodUs);
    }

    if (presentSlot(slot, -1)) {
        uint64_t latencyUs = LiGetMicroseconds() - job.submitUs;
        m_TotalLatencyUs += latencyUs;
        m_LatencySamples++;
        m_MaxLatencyUs = SDL_max(m_MaxLatencyUs, latencyUs);
    }
}

bool D3D11FiPresenter::presentSlot(Slot& slot, int index)
{
    bool interpolated = index >= 0;
    m_Callbacks.lock();
    uint64_t presentUs = LiGetMicroseconds();
    const bool duplicateDecoded = m_DuplicateDecodedForTest ||
        (m_Callbacks.duplicateDecodedForTest && m_Callbacks.duplicateDecodedForTest());
    ID3D11ShaderResourceView* view = interpolated && !duplicateDecoded
        ? slot.interpolated[index].view.Get() : slot.decoded.view.Get();
    HRESULT hr = m_Callbacks.present(view,
                                     slot.width, slot.height, m_SyncInterval, m_PresentFlags);
    uint64_t presentedUs = LiGetMicroseconds();
    if (SUCCEEDED(hr)) {
        recordDisplayStatistics();
    }
    m_Callbacks.unlock();

    if (m_Timed && SUCCEEDED(hr)) {
        checkBlockingPresent(presentedUs - presentUs);
    }

    if (FAILED(hr)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Frame interpolation: Present() failed: %x",
                     hr);
        m_Callbacks.presentFailed();
        return false;
    }

    // In queued mode, Present() returns once the frame has a place in the
    // queue, which is when the previous one reached the screen
    if (!m_Timed) {
        presentUs = LiGetMicroseconds();
    }

    // Half a stream frame apart is only the goal of timed presentation
    if (m_Timed) {
        recordInterval(presentUs, interpolated);
    }
    m_LastPresentUs = presentUs;
    m_LastWasInterpolated = interpolated;
    m_Shown++;
    if (interpolated) {
        m_ShownInterpolated++;
    }
    return true;
}

void D3D11FiPresenter::recordDisplayStatistics()
{
    UINT presentCount, refreshCount;
    if (!m_Callbacks.frameStatistics || !m_Callbacks.frameStatistics(presentCount, refreshCount)) {
        return;
    }

    // Two presents in a row that reached the screen: the first stayed there for
    // the refreshes in between. Frames that never showed up aren't counted.
    if (presentCount == m_LastStatsPresent + 1 && refreshCount > m_LastStatsRefresh) {
        UINT refreshes = refreshCount - m_LastStatsRefresh;
        m_RefreshHistogram[SDL_min(refreshes, 4u) - 1]++;
    }
    if (presentCount != m_LastStatsPresent) {
        m_LastStatsPresent = presentCount;
        m_LastStatsRefresh = refreshCount;
    }
}

void D3D11FiPresenter::checkBlockingPresent(uint64_t durationUs)
{
    m_TimedPresents++;
    if (durationUs > BLOCKING_PRESENT_US) {
        m_BlockingPresents++;
    }

    if (m_TimedPresents == BLOCKING_CHECK_PRESENTS) {
        if (m_BlockingPresents > BLOCKING_CHECK_PRESENTS * BLOCKING_MAX_SHARE) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Frame interpolation: %llu of %d presents blocked, frames don't go straight to the display; queuing them instead",
                        (unsigned long long)m_BlockingPresents, BLOCKING_CHECK_PRESENTS);
            m_Timed = false;
            m_SyncInterval = 1;
            m_PresentFlags = 0;
        }
        else {
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "Frame interpolation: frames go straight to the display (%llu of %d presents blocked)",
                        (unsigned long long)m_BlockingPresents, BLOCKING_CHECK_PRESENTS);
        }
    }
}

void D3D11FiPresenter::recordInterval(uint64_t presentUs, bool interpolated)
{
    // Only the pairs that should be half a stream frame apart: a decoded frame
    // after its interpolated frame, and an interpolated frame after a decoded one
    if (m_LastPresentUs == 0 || interpolated == m_LastWasInterpolated) {
        return;
    }

    double halfPeriodUs;
    {
        std::lock_guard<std::mutex> guard(m_Lock);
        halfPeriodUs = m_PeriodUs / 2;
    }

    double ratio = (presentUs - m_LastPresentUs) / halfPeriodUs;
    m_Intervals++;
    if (ratio < SHORT_INTERVAL) {
        m_ShortIntervals++;
    }
    else if (ratio > LONG_INTERVAL && interpolated) {
        // A decoded frame shown longer while waiting for the next one. Only
        // counted before interpolated frames, since the other way around can't
        // happen: the decoded frame always follows its interpolated frame.
        m_LongIntervals++;
    }
}

void D3D11FiPresenter::waitUntil(uint64_t targetUs)
{
    uint64_t now = LiGetMicroseconds();
    if (now >= targetUs) {
        return;
    }

    if (targetUs - now > SPIN_US && m_Timer != nullptr) {
        LARGE_INTEGER dueTime;
        dueTime.QuadPart = -(LONGLONG)(targetUs - now - SPIN_US) * 10; // Relative, in 100 ns units
        if (SetWaitableTimer(m_Timer, &dueTime, 0, nullptr, nullptr, FALSE)) {
            WaitForSingleObject(m_Timer, 100);
        }
    }

    while (LiGetMicroseconds() < targetUs) {
        YieldProcessor();
    }
}

void D3D11FiPresenter::logStats()
{
    if (m_Shown == 0) {
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Frame interpolation pacing: %llu frames shown (%llu interpolated), %.2f ms stream period, "
                "%llu/%llu intervals too short and %llu too long, %llu interpolated frames skipped to catch up, "
                "%llu refreshes beyond the interpolated frames, %llu skipped to catch up, %llu frames dropped, "
                "latency %.1f ms average and %.1f ms max, display %.2f ms per frame (%.2f ms nominal)",
                (unsigned long long)m_Shown, (unsigned long long)m_ShownInterpolated, m_PeriodUs / 1000.0,
                (unsigned long long)m_ShortIntervals, (unsigned long long)m_Intervals,
                (unsigned long long)m_LongIntervals, (unsigned long long)m_SkippedInterpolated,
                (unsigned long long)m_UnplannedRefreshes, (unsigned long long)m_CatchUpRefreshes,
                (unsigned long long)m_DroppedFrames,
                m_LatencySamples ? m_TotalLatencyUs / 1000.0 / m_LatencySamples : 0.0, m_MaxLatencyUs / 1000.0,
                m_MeasuredRefreshUs.load() / 1000.0, m_RefreshUs / 1000.0);

    uint64_t measured = m_RefreshHistogram[0] + m_RefreshHistogram[1] + m_RefreshHistogram[2] + m_RefreshHistogram[3];
    if (measured > 0) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Frame interpolation display: of %llu frames measured, %.1f%% stayed 1 refresh, %.1f%% 2, %.1f%% 3, %.1f%% more",
                    (unsigned long long)measured,
                    100.0 * m_RefreshHistogram[0] / measured, 100.0 * m_RefreshHistogram[1] / measured,
                    100.0 * m_RefreshHistogram[2] / measured, 100.0 * m_RefreshHistogram[3] / measured);
    }
}
