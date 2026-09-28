#pragma once

#include <QObject>
#include <QString>

class QLocalServer;

// KanePlay embedded in KaneMode (KANEPLAY_EMBEDDED). KaneMode starts KanePlay.exe
// with a command in KANEMODE_COMMAND:
//   "show"                            bring the streaming screen up
//   "stream<TAB>uuid<TAB>appId<TAB>name"  open that PC's library and play or resume the app
// A single embedded KanePlay runs: a second one hands its command to the first
// through a local socket and exits, so a paused session is always the one resumed.
class KaneModeBridge : public QObject
{
    Q_OBJECT

public:
    explicit KaneModeBridge(QObject* parent = nullptr);

    // True if an embedded KanePlay already runs and took the command
    static bool forwardToRunningInstance();

    // Starts answering the next KanePlay launches, and runs our own command
    void listen();

    // Back to KaneMode: KaneMode's window comes forward, ours is minimized by QML
    Q_INVOKABLE void returnToKaneMode();

    // Brings our window forward (Windows only lets it with the launcher's consent)
    Q_INVOKABLE void activate();

    // Opens KaneMode's "menu" or "qam" (quick access) on top of us; KaneMode gives us
    // the foreground back when it is closed
    Q_INVOKABLE void openInKaneMode(const QString& panel);

signals:
    void showRequested();
    void launchRequested(QString uuid, int appId, QString appName);

private:
    void handle(const QString& command);

    QLocalServer* m_Server;
};
