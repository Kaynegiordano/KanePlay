#include "networkinfo.h"

#include <QByteArray>

#ifdef Q_OS_WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <wlanapi.h>
#endif

#ifdef Q_OS_WIN32
// Name and signal of the Wi-Fi network. Fails without the location permission
// (Windows 11 24H2 and later): the caller then keeps the adapter name.
static void readWifiConnection(NetworkInfo& info)
{
    HANDLE client = nullptr;
    DWORD version = 0;
    if (WlanOpenHandle(2, nullptr, &version, &client) != ERROR_SUCCESS) {
        return;
    }

    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(client, nullptr, &interfaces) == ERROR_SUCCESS && interfaces != nullptr) {
        for (DWORD i = 0; i < interfaces->dwNumberOfItems; i++) {
            if (interfaces->InterfaceInfo[i].isState != wlan_interface_state_connected) {
                continue;
            }

            DWORD size = 0;
            PWLAN_CONNECTION_ATTRIBUTES attributes = nullptr;
            if (WlanQueryInterface(client, &interfaces->InterfaceInfo[i].InterfaceGuid,
                                   wlan_intf_opcode_current_connection, nullptr,
                                   &size, (PVOID*)&attributes, nullptr) == ERROR_SUCCESS && attributes != nullptr) {
                const DOT11_SSID& ssid = attributes->wlanAssociationAttributes.dot11Ssid;
                QString name = QString::fromUtf8((const char*)ssid.ucSSID, (int)qMin<ULONG>(ssid.uSSIDLength, DOT11_SSID_MAX_LENGTH));
                if (!name.isEmpty()) {
                    info.name = name;
                }
                info.signalPercent = (int)qMin<ULONG>(attributes->wlanAssociationAttributes.wlanSignalQuality, 100);
                if (info.linkMbps == 0 && attributes->wlanAssociationAttributes.ulRxRate != 0) {
                    info.linkMbps = (int)(attributes->wlanAssociationAttributes.ulRxRate / 1000);
                }
                WlanFreeMemory(attributes);
                break;
            }
        }
        WlanFreeMemory(interfaces);
    }

    WlanCloseHandle(client, nullptr);
}
#endif

NetworkInfo NetworkInfo::current()
{
    NetworkInfo info;

#ifdef Q_OS_WIN32
    QByteArray buffer;
    ULONG size = 32 * 1024;
    ULONG err = ERROR_BUFFER_OVERFLOW;
    for (int attempt = 0; attempt < 3 && err == ERROR_BUFFER_OVERFLOW; attempt++) {
        buffer.resize((int)size);
        err = GetAdaptersAddresses(AF_UNSPEC,
                                   GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                   nullptr, (PIP_ADAPTER_ADDRESSES)buffer.data(), &size);
    }
    if (err != NO_ERROR) {
        return info;
    }

    // The adapter this device reaches the outside world with: up, with a gateway,
    // Wi-Fi or cable, lowest metric first
    const IP_ADAPTER_ADDRESSES* best = nullptr;
    for (const IP_ADAPTER_ADDRESSES* adapter = (const IP_ADAPTER_ADDRESSES*)buffer.constData(); adapter != nullptr; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp || adapter->FirstGatewayAddress == nullptr) {
            continue;
        }
        if (adapter->IfType != IF_TYPE_IEEE80211 && adapter->IfType != IF_TYPE_ETHERNET_CSMACD) {
            continue;
        }
        if (best == nullptr || adapter->Ipv4Metric < best->Ipv4Metric) {
            best = adapter;
        }
    }
    if (best == nullptr) {
        return info;
    }

    info.wifi = best->IfType == IF_TYPE_IEEE80211;
    info.name = QString::fromWCharArray(best->FriendlyName);

    // An unknown speed is reported as all bits set
    if (best->ReceiveLinkSpeed != 0 && best->ReceiveLinkSpeed < 100000000000ULL) {
        info.linkMbps = (int)(best->ReceiveLinkSpeed / 1000000ULL);
    }

    // The gateway is in the neighbor cache of a connected adapter, so this
    // doesn't wait for the network
    for (const IP_ADAPTER_GATEWAY_ADDRESS_LH* gateway = best->FirstGatewayAddress; gateway != nullptr; gateway = gateway->Next) {
        if (gateway->Address.lpSockaddr == nullptr || gateway->Address.lpSockaddr->sa_family != AF_INET) {
            continue;
        }

        const sockaddr_in* address = (const sockaddr_in*)gateway->Address.lpSockaddr;
        ULONG mac[2] = {0, 0};
        ULONG macLength = 6;
        if (SendARP(address->sin_addr.s_addr, 0, mac, &macLength) == NO_ERROR && macLength == 6) {
            info.id = QString::fromLatin1(QByteArray((const char*)mac, 6).toHex());
        }
        break;
    }

    if (info.wifi) {
        readWifiConnection(info);
    }
#endif

    return info;
}
