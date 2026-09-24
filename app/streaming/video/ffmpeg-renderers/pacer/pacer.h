#pragma once

#include "../../decoder.h"
#include "../renderer.h"
#include "vrr/vrrtypes.h"

#include <QQueue>
#include <QMutex>
#include <QWaitCondition>

#include <atomic>
#include <memory>

class VrrPacingWorker;

// The maximum number of frames pacer will ever hold is:
// - 3 frames in the pacing queue
// - 1 frame removed from the render queue in the process of rendering
// - 1 frame for deferred free
#define PACER_MAX_OUTSTANDING_FRAMES (3 + 1 + 1)

class IVsyncSource {
public:
    virtual ~IVsyncSource() {}
    virtual bool initialize(SDL_Window* window, int displayFps) = 0;

    // Asynchronous sources produce callbacks on their own, while synchronous
    // sources require calls to waitForVsync().
    virtual bool isAsync() = 0;

    virtual void waitForVsync() {
        // Synchronous sources must implement waitForVsync()!
        SDL_assert(false);
    }
};

class Pacer
{
public:
    Pacer(IFFmpegRenderer* renderer, PVIDEO_STATS videoStats);

    ~Pacer();

    // Only the active VRR worker consumes the decoder-facing pacing metadata.
    void submitFrame(PacedFrame&& frame);

    void submitFrame(AVFrame* frame);

    bool isVrrActive() const;

    bool initialize(SDL_Window* window, int maxVideoFps,
                    bool enablePacing, bool enableVsync,
                    bool enableVrr, int vrrDisplayRefreshHz,
                    bool autoPacing = false);

    void notifyWindowChanged(PWINDOW_STATE_CHANGE_INFO info);

    bool isAutoPacing() const { return m_AutoPacing; }

    // -1 if frame pacing isn't available, otherwise 1 while frames are paced and 0 when they aren't
    int getPacingState() const { return m_VsyncSource == nullptr ? -1 : (m_PacingActive ? 1 : 0); }

    void signalVsync();

    void renderOnMainThread();

private:
    static int vsyncThread(void* context);

    static int renderThread(void* context);

    void handleVsync(int timeUntilNextVsyncMillis);

    void enqueueFrameForRenderingAndUnlock(AVFrame* frame);

    void renderFrame(AVFrame* frame);

    void dropFrameForEnqueue(QQueue<AVFrame*>& queue);

    void updateAutoPacing();

    QQueue<AVFrame*> m_RenderQueue;
    QQueue<AVFrame*> m_PacingQueue;
    QQueue<int> m_PacingQueueHistory;
    QQueue<int> m_RenderQueueHistory;
    QMutex m_FrameQueueLock;
    QWaitCondition m_RenderQueueNotEmpty;
    QWaitCondition m_PacingQueueNotEmpty;
    QWaitCondition m_VsyncSignalled;
    SDL_Thread* m_RenderThread;
    SDL_Thread* m_VsyncThread;
    AVFrame* m_DeferredFreeFrame;
    bool m_Stopping;

    IVsyncSource* m_VsyncSource;
    IFFmpegRenderer* m_VsyncRenderer;
    int m_MaxVideoFps;
    int m_DisplayFps;
    PVIDEO_STATS m_VideoStats;
    int m_RendererAttributes;

    // Auto pacing state (protected by m_FrameQueueLock, except m_PacingActive)
    bool m_AutoPacing;
    std::atomic<bool> m_PacingActive;
    uint64_t m_LastFrameArrivalUs;
    uint64_t m_JitterWindowStartUs;
    uint64_t m_JitterSumUs;
    int m_JitterSamples;
    int m_IrregularWindows;
    int m_RegularWindows;
    std::unique_ptr<VrrPacingWorker> m_VrrWorker;
};
