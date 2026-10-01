#include "kanemodebridge.h"

#include <QDebug>
#include <QGuiApplication>
#include <QLocalServer>
#include <QLocalSocket>
#include <QTimer>
#include <QWindow>

#ifdef Q_OS_WIN32
#include <windows.h>

// KaneMode's own window: titled exactly "KaneMode", WPF class "HwndWrapper[KaneMode;;...]".
// KaneMode's Game Bar widget also has a (hidden) window titled "KaneMode": FindWindow could
// return it, KanePlay then gave the foreground to the widget and KaneMode's gamepad stopped
// answering (and Start / Select went to the widget).
static BOOL CALLBACK findKaneModeProc(HWND hwnd, LPARAM param)
{
    wchar_t title[16];
    if (GetWindowTextW(hwnd, title, 16) == 0 || wcscmp(title, L"KaneMode") != 0) {
        return TRUE;
    }
    wchar_t cls[64];
    if (GetClassNameW(hwnd, cls, 64) == 0 || wcsncmp(cls, L"HwndWrapper[KaneMode", 20) != 0) {
        return TRUE;
    }
    *reinterpret_cast<HWND*>(param) = hwnd;
    return FALSE;
}

static HWND findKaneMode()
{
    HWND found = nullptr;
    EnumWindows(findKaneModeProc, reinterpret_cast<LPARAM>(&found));
    return found;
}
#endif

static QString serverName()
{
    return QStringLiteral("KaneMode.Streaming.") + qEnvironmentVariable("USERNAME");
}

static QString command()
{
    QString c = qEnvironmentVariable("KANEMODE_COMMAND");
    return c.isEmpty() ? QStringLiteral("show") : c;
}

KaneModeBridge::KaneModeBridge(QObject* parent)
    : QObject(parent),
      m_Server(nullptr)
{
}

bool KaneModeBridge::forwardToRunningInstance()
{
    QLocalSocket socket;
    socket.connectToServer(serverName());
    if (!socket.waitForConnected(1000)) {
        return false;
    }

#ifdef Q_OS_WIN32
    // We were started by KaneMode, in the foreground: let the running KanePlay take it
    AllowSetForegroundWindow(ASFW_ANY);
#endif
    socket.write(command().toUtf8());
    socket.flush();
    socket.waitForBytesWritten(1000);
    socket.disconnectFromServer();
    return true;
}

void KaneModeBridge::listen()
{
    m_Server = new QLocalServer(this);
    m_Server->setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(serverName());
    if (!m_Server->listen(serverName())) {
        qWarning() << "KaneMode bridge: unable to listen:" << m_Server->errorString();
    }

    connect(m_Server, &QLocalServer::newConnection, this, [this]() {
        while (QLocalSocket* socket = m_Server->nextPendingConnection()) {
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QLocalSocket::readyRead, this, [this, socket]() {
                handle(QString::fromUtf8(socket->readAll()));
            });
        }
    });

    // Our own command, once the UI is up
    QString own = command();
    QTimer::singleShot(0, this, [this, own]() { handle(own); });
}

void KaneModeBridge::handle(const QString& command)
{
    QStringList parts = command.trimmed().split('\t');
    if (parts.value(0) == QStringLiteral("stream") && parts.size() >= 3) {
        emit launchRequested(parts.value(1), parts.value(2).toInt(), parts.value(3));
    }
    else {
        emit showRequested();
    }
}

void KaneModeBridge::activate()
{
#ifdef Q_OS_WIN32
    for (QWindow* window : QGuiApplication::topLevelWindows()) {
        if (window->isVisible() && window->transientParent() == nullptr) {
            HWND hwnd = (HWND)window->winId();
            if (IsIconic(hwnd)) {
                ShowWindow(hwnd, SW_RESTORE);
            }
            SetForegroundWindow(hwnd);
        }
    }
#endif
}

void KaneModeBridge::openInKaneMode(const QString& panel)
{
#ifdef Q_OS_WIN32
    HWND kaneMode = findKaneMode();
    if (kaneMode == nullptr) {
        return;
    }
    // KaneMode may take the foreground, and knows where to come back (wParam)
    DWORD pid = 0;
    GetWindowThreadProcessId(kaneMode, &pid);
    AllowSetForegroundWindow(pid);
    HWND ours = nullptr;
    for (QWindow* window : QGuiApplication::topLevelWindows()) {
        if (window->isVisible() && window->transientParent() == nullptr) {
            ours = (HWND)window->winId();
            break;
        }
    }
    QString message = QStringLiteral("open\t") + panel;
    COPYDATASTRUCT data;
    data.dwData = 0x4B4D; // "KM"
    data.cbData = (DWORD)((message.size() + 1) * sizeof(wchar_t));
    data.lpData = (PVOID)message.utf16();
    DWORD_PTR result = 0;
    SendMessageTimeoutW(kaneMode, WM_COPYDATA, (WPARAM)ours, (LPARAM)&data, SMTO_ABORTIFHUNG, 1000, &result);
#else
    Q_UNUSED(panel)
#endif
}

void KaneModeBridge::returnToKaneMode()
{
    // Une relance doit démarrer un nouveau moteur dès que celui-ci commence à se fermer.
    if (m_Server != nullptr) m_Server->close();
#ifdef Q_OS_WIN32
    // KaneMode's window is titled exactly "KaneMode" (ours is "KaneMode · Streaming")
    HWND kaneMode = findKaneMode();
    if (kaneMode != nullptr) {
        if (IsIconic(kaneMode)) {
            ShowWindow(kaneMode, SW_RESTORE);
        }
        SetForegroundWindow(kaneMode);
    }
#endif
}
