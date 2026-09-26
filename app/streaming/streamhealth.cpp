#include "streamhealth.h"
#include "path.h"
#include "settings/streamingpreferences.h"

#include <QDateTime>
#include <QDir>

#include <Limelight.h>
#include <SDL.h>

// Points kept for the round-trip time graph of the session summary
#define MAX_RTT_SERIES_POINTS 120

// A window (~1 second) is lossy when this share of its frames was lost despite FEC
#define LOSSY_WINDOW_PERCENT 2.0

// Sessions shorter than this don't tell us enough about the network
#define MIN_LEARNING_WINDOWS 60

// Back off when the network couldn't keep up...
#define BACKOFF_LOSSY_WINDOW_RATIO 0.05
#define BACKOFF_LOSS_PERCENT 1.0
#define BACKOFF_POOR_STATUS_COUNT 2
#define BACKOFF_FACTOR 0.85

// ...and slowly give back bitrate after clean sessions
#define RECOVER_LOSSY_WINDOW_RATIO 0.01
#define RECOVER_LOSS_PERCENT 0.1
#define RECOVER_FACTOR 1.05

// Never go below this share of the configured bitrate
#define MIN_LEARNED_FACTOR 0.30

StreamHealthMonitor::StreamHealthMonitor(const QString& hostUuid, int bitrateKbps, double learnedFactor, const QString& learnedBitrateKey,
                                         bool logStats, int width, int height, int fps)
    : m_HostUuid(hostUuid),
      m_BitrateKbps(bitrateKbps),
      m_LearnedFactor(learnedFactor),
      m_LearnedBitrateKey(learnedBitrateKey),
      m_PoorStatusSeen(false),
      m_PoorStatusCount(0),
      m_Windows(0),
      m_LossyWindows(0),
      m_TotalFrames(0),
      m_DroppedFrames(0),
      m_SessionStartUs(LiGetMicroseconds()),
      m_SumRenderedFps(0),
      m_SumVideoMbps(0),
      m_SumRttMs(0),
      m_RttWindows(0),
      m_RttSeriesStep(1),
      m_RttSeriesSum(0),
      m_RttSeriesCount(0),
      m_AppId(0)
{
    if (logStats) {
        openCsv(width, height, fps);
    }
}

StreamHealthMonitor::~StreamHealthMonitor()
{
    if (m_CsvFile.isOpen()) {
        m_CsvFile.close();
    }
}

void StreamHealthMonitor::openCsv(int width, int height, int fps)
{
    QDir logDir(Path::getLogDir());
    m_CsvFile.setFileName(logDir.filePath(QString("KanePlay-stats-%1.csv")
                                              .arg(QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss"))));
    if (!m_CsvFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Unable to create stats file %s",
                    qPrintable(m_CsvFile.fileName()));
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Logging stream stats (%dx%d, %d FPS, %d Kbps) to %s",
                width, height, fps, m_BitrateKbps,
                qPrintable(QDir::toNativeSeparators(m_CsvFile.fileName())));

    m_CsvFile.write("time_s,codec,received_fps,rendered_fps,total_frames,net_dropped,loss_pct,"
                    "pacer_dropped,decode_ms,queue_ms,render_ms,host_latency_ms,rtt_ms,rtt_var_ms,"
                    "video_mbps,bitrate_kbps,frame_pacing,conn_poor\n");
    m_CsvFile.flush();
}

static const char* getCodecName(int videoFormat)
{
    if (videoFormat & VIDEO_FORMAT_MASK_AV1) {
        return (videoFormat & VIDEO_FORMAT_MASK_10BIT) ? "AV1 10-bit" : "AV1";
    }
    else if (videoFormat & VIDEO_FORMAT_MASK_H265) {
        return (videoFormat & VIDEO_FORMAT_MASK_10BIT) ? "HEVC 10-bit" : "HEVC";
    }
    else {
        return "H.264";
    }
}

void StreamHealthMonitor::onConnectionStatus(int connectionStatus)
{
    if (connectionStatus == CONN_STATUS_POOR) {
        m_PoorStatusSeen = true;
        m_PoorStatusCount++;
    }
}

void StreamHealthMonitor::onStatsWindow(const VIDEO_STATS& window, int videoFormat, double videoMbps, int framePacingState)
{
    double windowSecs = (double)(LiGetMicroseconds() - window.measurementStartUs) / 1000000.0;
    if (window.totalFrames == 0 || windowSecs <= 0) {
        return;
    }

    double lossPercent = (double)window.networkDroppedFrames / window.totalFrames * 100.0;
    bool poorStatus = m_PoorStatusSeen.exchange(false);

    m_Windows++;
    m_TotalFrames += window.totalFrames;
    m_DroppedFrames += window.networkDroppedFrames;
    if (lossPercent >= LOSSY_WINDOW_PERCENT) {
        m_LossyWindows++;
    }

    uint32_t rtt, rttVariance;
    if (!LiGetEstimatedRttInfo(&rtt, &rttVariance)) {
        rtt = rttVariance = 0;
    }

    m_SumRenderedFps += window.renderedFrames / windowSecs;
    m_SumVideoMbps += videoMbps;
    if (rtt != 0) {
        m_SumRttMs += rtt;
        m_RttWindows++;

        m_RttSeriesSum += rtt;
        if (++m_RttSeriesCount == m_RttSeriesStep) {
            m_RttSeries.append((int)(m_RttSeriesSum / m_RttSeriesCount));
            m_RttSeriesSum = 0;
            m_RttSeriesCount = 0;

            // Halve the resolution once the graph has enough points
            if (m_RttSeries.size() >= MAX_RTT_SERIES_POINTS) {
                QVector<int> halved;
                for (int i = 0; i + 1 < m_RttSeries.size(); i += 2) {
                    halved.append((m_RttSeries[i] + m_RttSeries[i + 1]) / 2);
                }
                m_RttSeries = halved;
                m_RttSeriesStep *= 2;
            }
        }
    }

    if (!m_CsvFile.isOpen()) {
        return;
    }

    auto average = [](double total, uint32_t count) {
        return count != 0 ? total / count : 0.0;
    };

    QString row = QString::asprintf("%.1f,%s,%.2f,%.2f,%u,%u,%.2f,%u,%.2f,%.2f,%.2f,%.1f,%u,%u,%.2f,%d,%d,%d\n",
                                    (double)(LiGetMicroseconds() - m_SessionStartUs) / 1000000.0,
                                    getCodecName(videoFormat),
                                    window.receivedFrames / windowSecs,
                                    window.renderedFrames / windowSecs,
                                    window.totalFrames,
                                    window.networkDroppedFrames,
                                    lossPercent,
                                    window.pacerDroppedFrames,
                                    average(window.totalDecodeTimeUs / 1000.0, window.decodedFrames),
                                    average(window.totalPacerTimeUs / 1000.0, window.renderedFrames),
                                    average(window.totalRenderTimeUs / 1000.0, window.renderedFrames),
                                    average(window.totalHostProcessingLatency / 10.0, window.framesWithHostProcessingLatency),
                                    rtt,
                                    rttVariance,
                                    videoMbps,
                                    m_BitrateKbps,
                                    framePacingState,
                                    poorStatus ? 1 : 0);
    m_CsvFile.write(row.toUtf8());
    m_CsvFile.flush();
}

// Sessions shorter than this aren't worth showing as the last session
#define MIN_SUMMARY_WINDOWS 10

void StreamHealthMonitor::finishSession()
{
    double newFactor = m_LearnedFactor;

    if (!m_LearnedBitrateKey.isEmpty()) {
        newFactor = updateLearnedBitrate();
    }

    if (m_Windows >= MIN_SUMMARY_WINDOWS && m_TotalFrames != 0 && !m_HostUuid.isEmpty()) {
        QVariantMap summary;
        summary["endTime"] = QDateTime::currentDateTime();
        summary["durationSecs"] = (qulonglong)m_Windows;
        summary["lossPercent"] = (double)m_DroppedFrames / m_TotalFrames * 100.0;
        summary["learnedPercent"] = qRound(newFactor * 100);
        summary["appName"] = m_AppName;
        summary["appId"] = m_AppId;
        summary["avgFps"] = m_SumRenderedFps / m_Windows;
        summary["avgMbps"] = m_SumVideoMbps / m_Windows;
        summary["avgRttMs"] = m_RttWindows != 0 ? (double)m_SumRttMs / m_RttWindows : 0.0;

        QVariantList rttSeries;
        for (int rtt : m_RttSeries) {
            rttSeries.append(rtt);
        }
        summary["rttSeries"] = rttSeries;
        StreamingPreferences::setLastSession(m_HostUuid, summary);
    }
}

double StreamHealthMonitor::updateLearnedBitrate()
{
    if (m_Windows < MIN_LEARNING_WINDOWS || m_TotalFrames == 0) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Learned bitrate: session too short to learn from (%llu s)",
                    (unsigned long long)m_Windows);
        return m_LearnedFactor;
    }

    double lossPercent = (double)m_DroppedFrames / m_TotalFrames * 100.0;
    double lossyWindowRatio = (double)m_LossyWindows / m_Windows;
    int poorStatusCount = m_PoorStatusCount;

    double newFactor = m_LearnedFactor;
    if (lossyWindowRatio >= BACKOFF_LOSSY_WINDOW_RATIO ||
            lossPercent >= BACKOFF_LOSS_PERCENT ||
            poorStatusCount >= BACKOFF_POOR_STATUS_COUNT) {
        newFactor = qMax(MIN_LEARNED_FACTOR, m_LearnedFactor * BACKOFF_FACTOR);
    }
    else if (lossyWindowRatio <= RECOVER_LOSSY_WINDOW_RATIO &&
             lossPercent < RECOVER_LOSS_PERCENT &&
             poorStatusCount == 0) {
        newFactor = qMin(1.0, m_LearnedFactor * RECOVER_FACTOR);
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Learned bitrate for %s: %.0f%% -> %.0f%% (loss %.2f%%, lossy windows %.1f%%, poor status %d, %llu s)",
                qPrintable(m_LearnedBitrateKey),
                m_LearnedFactor * 100, newFactor * 100,
                lossPercent, lossyWindowRatio * 100, poorStatusCount,
                (unsigned long long)m_Windows);

    StreamingPreferences::setLearnedBitrateFactor(m_LearnedBitrateKey, newFactor);
    return newFactor;
}
