#pragma once

#include <QString>

#include <atomic>
#include <cstdint>

// KaneMode: data received from the host during a streaming session, as it goes over
// the network. Video packets all have the negotiated packet size, so the video and
// FEC packet counts of moonlight-common-c give its share exactly; audio is counted
// from the Opus packets. Input and control traffic (a few KB/s) are left out.
class DataUsage
{
public:
    // A new session starts with this packet size
    static void reset(int packetSize);

    // Audio thread: an Opus packet of this many bytes arrived
    static void addAudioPacket(int bytes) { s_AudioPayloadBytes += (uint64_t)bytes; s_AudioPackets++; }

    // Bytes received so far in this session. Must be called while connected
    // (it reads the RTP stats of moonlight-common-c); the last value is kept after.
    static uint64_t sample();

    // Last value of sample(), from any thread
    static uint64_t bytes() { return s_Bytes; }

    // "1,24 GB", "380 MB": in the language of the UI
    static QString format(uint64_t bytes);

    // Adds the session to the total of the current month and returns that total
    static uint64_t addToMonth(uint64_t bytes);

private:
    static std::atomic<int> s_PacketSize;
    static std::atomic<uint64_t> s_AudioPayloadBytes;
    static std::atomic<uint64_t> s_AudioPackets;
    static std::atomic<uint64_t> s_Bytes;
};
