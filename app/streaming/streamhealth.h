#pragma once

#include "video/decoder.h"

#include <QFile>
#include <QString>

#include <atomic>

// Watches the per-second video statistics of a streaming session in order to:
// - log them to a CSV file (one row per second) for offline analysis
// - learn, session after session, which share of the configured bitrate
//   the network to a given host can carry without losing frames
class StreamHealthMonitor
{
public:
    // An empty learnedBitrateKey disables bitrate learning for this session
    StreamHealthMonitor(const QString& hostUuid, int bitrateKbps, double learnedFactor, const QString& learnedBitrateKey,
                        bool logStats, int width, int height, int fps);
    ~StreamHealthMonitor();

    // Called by the video decoder thread about once per second with the stats of the
    // window that just ended, before the window is reset. framePacingState is -1 when
    // frame pacing is unavailable, otherwise 0 (idle) or 1 (pacing frames).
    void onStatsWindow(const VIDEO_STATS& window, int videoFormat, double videoMbps, int framePacingState);

    // Called by moonlight-common-c on its own thread
    void onConnectionStatus(int connectionStatus);

    // Called once the stream is over to save its summary and update the bitrate learned for this host
    void finishSession();

    // Share of the configured bitrate used for this session
    double getLearnedFactor() const { return m_LearnedFactor; }

private:
    void openCsv(int width, int height, int fps);

    // Returns the new share of the configured bitrate to use next time
    double updateLearnedBitrate();

    const QString m_HostUuid;
    const int m_BitrateKbps;
    const double m_LearnedFactor;
    const QString m_LearnedBitrateKey;

    std::atomic<bool> m_PoorStatusSeen;
    std::atomic<int> m_PoorStatusCount;

    // Only touched by the decoder thread
    uint64_t m_Windows;
    uint64_t m_LossyWindows;
    uint64_t m_TotalFrames;
    uint64_t m_DroppedFrames;
    uint64_t m_SessionStartUs;
    QFile m_CsvFile;
};
