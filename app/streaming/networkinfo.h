#pragma once

#include <QString>

// KaneMode: the network this device is on right now, read when a stream starts.
// It gives each network its own learned bitrate (home, a friend's Wi-Fi, a phone
// hotspot) and tells the session summary what the stream went through.
struct NetworkInfo
{
    // Wi-Fi adapter (false: cable, or unknown)
    bool wifi = false;

    // Negotiated speed of the link, 0 when unknown
    int linkMbps = 0;

    // Wi-Fi signal quality from 0 to 100, -1 when unknown (Windows hides it
    // from apps that aren't allowed to read the location)
    int signalPercent = -1;

    // Wi-Fi network name when Windows gives it, otherwise the adapter name
    QString name;

    // Stable identifier of the network (hardware address of its gateway),
    // empty when unknown
    QString id;

    static NetworkInfo current();
};
