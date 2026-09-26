#include "richpresencemanager.h"

#include <QDebug>

// Discord application of KanePlay, empty while there is none
#define KANEPLAY_DISCORD_APP_ID ""

RichPresenceManager::RichPresenceManager(StreamingPreferences& prefs, QString gameName)
    : m_DiscordActive(false)
{
#ifdef HAVE_DISCORD
    // KanePlay has no Discord application of its own yet, and Moonlight's
    // must not be used, so the rich presence stays off until then
    if (prefs.richPresence && sizeof(KANEPLAY_DISCORD_APP_ID) > 1) {
        DiscordEventHandlers handlers = {};
        handlers.ready = discordReady;
        handlers.disconnected = discordDisconnected;
        handlers.errored = discordErrored;
        Discord_Initialize(KANEPLAY_DISCORD_APP_ID, &handlers, 0, nullptr);
        m_DiscordActive = true;
    }

    if (m_DiscordActive) {
        QByteArray stateStr = (QString("Streaming ") + gameName).toUtf8();

        DiscordRichPresence discordPresence = {};
        discordPresence.state = stateStr.data();
        discordPresence.startTimestamp = time(nullptr);
        discordPresence.largeImageKey = "icon";
        Discord_UpdatePresence(&discordPresence);
    }
#else
    Q_UNUSED(prefs)
    Q_UNUSED(gameName)
#endif
}

RichPresenceManager::~RichPresenceManager()
{
#ifdef HAVE_DISCORD
    if (m_DiscordActive) {
        Discord_ClearPresence();
        Discord_Shutdown();
    }
#endif
}

void RichPresenceManager::runCallbacks()
{
#ifdef HAVE_DISCORD
    if (m_DiscordActive) {
        Discord_RunCallbacks();
    }
#endif
}

#ifdef HAVE_DISCORD
void RichPresenceManager::discordReady(const DiscordUser* request)
{
    qInfo() << "Discord integration ready for user:" << request->username;
}

void RichPresenceManager::discordDisconnected(int errorCode, const char *message)
{
    qInfo() << "Discord integration disconnected:" << errorCode << message;
}

void RichPresenceManager::discordErrored(int errorCode, const char *message)
{
    qWarning() << "Discord integration error:" << errorCode << message;
}
#endif
