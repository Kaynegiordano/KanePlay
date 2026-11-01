#include "datausage.h"

#include <QCoreApplication>
#include <QDate>
#include <QLocale>
#include <QSettings>

#include <Limelight.h>

// RTP header (12) + UDP (8) + IPv4 (20) around each packet; the packet size
// negotiated for video already includes its NV_VIDEO_PACKET header
#define PACKET_OVERHEAD 40

#define SER_DATAUSAGE_MONTH "kanemodedatamonth"
#define SER_DATAUSAGE_BYTES "kanemodedatabytes"

std::atomic<int> DataUsage::s_PacketSize(0);
std::atomic<uint64_t> DataUsage::s_AudioPayloadBytes(0);
std::atomic<uint64_t> DataUsage::s_AudioPackets(0);
std::atomic<uint64_t> DataUsage::s_Bytes(0);

void DataUsage::reset(int packetSize)
{
    s_PacketSize = packetSize;
    s_AudioPayloadBytes = 0;
    s_AudioPackets = 0;
    s_Bytes = 0;
}

uint64_t DataUsage::sample()
{
    uint64_t total = 0;

    const RTP_VIDEO_STATS* video = LiGetRTPVideoStats();
    if (video != nullptr) {
        total += ((uint64_t)video->packetCountVideo + video->packetCountFec) * (s_PacketSize + PACKET_OVERHEAD);
    }

    // FEC packets of the audio are as large as its data packets
    uint64_t audioPackets = s_AudioPackets;
    if (audioPackets != 0) {
        uint64_t audioPayload = s_AudioPayloadBytes;
        const RTP_AUDIO_STATS* audio = LiGetRTPAudioStats();
        uint64_t fecPackets = audio != nullptr ? audio->packetCountFec : 0;
        total += audioPayload + audioPayload * fecPackets / audioPackets + (audioPackets + fecPackets) * PACKET_OVERHEAD;
    }

    // Never goes back, even if the stats are cleared at the end of the connection
    if (total > s_Bytes) {
        s_Bytes = total;
    }
    return s_Bytes;
}

QString DataUsage::format(uint64_t bytes)
{
    QLocale locale;
    double mb = bytes / 1000000.0;
    if (mb < 1000) {
        return QCoreApplication::translate("DataUsage", "%1 MB").arg(locale.toString(mb, 'f', 0));
    }
    double gb = mb / 1000;
    return QCoreApplication::translate("DataUsage", "%1 GB").arg(locale.toString(gb, 'f', gb < 100 ? 2 : 0));
}

uint64_t DataUsage::addToMonth(uint64_t bytes)
{
    QSettings settings;
    QString month = QDate::currentDate().toString("yyyy-MM");
    uint64_t total = bytes;
    if (settings.value(SER_DATAUSAGE_MONTH).toString() == month) {
        total += settings.value(SER_DATAUSAGE_BYTES, 0).toULongLong();
    }
    settings.setValue(SER_DATAUSAGE_MONTH, month);
    settings.setValue(SER_DATAUSAGE_BYTES, (qulonglong)total);
    return total;
}
