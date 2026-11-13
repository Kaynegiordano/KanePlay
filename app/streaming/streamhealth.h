#pragma once

#include "video/decoder.h"
#include "networkinfo.h"

#include <QFile>
#include <QString>
#include <QStringList>
#include <QVector>

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

    // Remembered with the summary, so the UI can offer to resume this app
    void setApp(const QString& name, int id) { m_AppName = name; m_AppId = id; }

    // KaneMode: what the stream started with, told in the session summary. limits says
    // why the bitrate is below the wanted one ("learned", "link", "battery", "picture")
    // and loweredMode the picture chosen for a weak network ("" when left alone).
    void setNetwork(const NetworkInfo& network, bool remote, int wantedBitrateKbps,
                    const QStringList& limits, const QString& loweredMode)
    {
        m_Network = network;
        m_Remote = remote;
        m_WantedBitrateKbps = wantedBitrateKbps;
        m_BitrateLimits = limits;
        m_LoweredMode = loweredMode;
    }

    // Share of the configured bitrate used for this session
    double getLearnedFactor() const { return m_LearnedFactor; }

private:
    void openCsv(int width, int height, int fps);

    // KaneMode: what got in the way of the session, most serious first
    QStringList findIssues(double lossPercent) const;

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
    double m_SumRenderedFps;
    double m_SumVideoMbps;
    uint64_t m_SumRttMs;
    uint64_t m_RttWindows;

    // Round-trip time over the session for the summary graph, averaged over
    // m_RttSeriesStep windows per point so a long session keeps few points
    QVector<int> m_RttSeries;
    int m_RttSeriesStep;
    uint64_t m_RttSeriesSum;
    int m_RttSeriesCount;

    QString m_AppName;
    int m_AppId;

    // KaneMode: for the diagnosis of the session summary
    const int m_Fps;
    NetworkInfo m_Network;
    bool m_Remote;
    int m_WantedBitrateKbps;
    QStringList m_BitrateLimits;
    QString m_LoweredMode;
    double m_SumReceivedFps;
    double m_SumDecodeMs;
    uint64_t m_DecodeWindows;
    double m_SumHostMs;
    uint64_t m_HostWindows;
    uint64_t m_SumRttVarianceMs;
    uint64_t m_PacerDroppedFrames;
    QFile m_CsvFile;
};
