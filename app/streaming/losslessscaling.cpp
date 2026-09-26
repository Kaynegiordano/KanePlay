#include "losslessscaling.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QXmlStreamReader>

#include <SDL.h>

#ifdef Q_OS_WIN32
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <TlHelp32.h>
#endif

QString LosslessScaling::installedExe()
{
#ifdef Q_OS_WIN32
    // Steam registers each installed app for Windows' uninstall list
    QSettings steamApp(QString("HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App ") + k_SteamAppId,
                       QSettings::Registry64Format);
    QString installDir = steamApp.value("InstallLocation").toString();
    if (!installDir.isEmpty()) {
        QString exe = QDir(installDir).filePath("LosslessScaling.exe");
        if (QFileInfo::exists(exe)) {
            return QDir::toNativeSeparators(exe);
        }
    }
#endif
    return QString();
}

bool LosslessScaling::isRunning()
{
#ifdef Q_OS_WIN32
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) {
        return false;
    }

    bool running = false;
    PROCESSENTRY32W entry = {};
    entry.dwSize = sizeof(entry);
    for (BOOL more = Process32FirstW(snapshot, &entry); more; more = Process32NextW(snapshot, &entry)) {
        if (_wcsicmp(entry.szExeFile, L"LosslessScaling.exe") == 0) {
            running = true;
            break;
        }
    }
    CloseHandle(snapshot);
    return running;
#else
    return false;
#endif
}

bool LosslessScaling::launch()
{
    QString exe = installedExe();
    return !exe.isEmpty() && QProcess::startDetached(exe, QStringList(), QFileInfo(exe).absolutePath());
}

#ifdef Q_OS_WIN32
// A WPF key name (its settings store them this way) as a virtual key
static UINT virtualKeyFromName(const QString& name)
{
    if (name.length() == 1 && name[0].isLetter()) {
        return name[0].toUpper().unicode();
    }
    if (name.length() == 2 && name[0] == 'D' && name[1].isDigit()) {
        return name[1].unicode();
    }
    if (name.startsWith('F') && name.length() <= 3) {
        bool ok;
        int number = name.mid(1).toInt(&ok);
        if (ok && number >= 1 && number <= 24) {
            return VK_F1 + number - 1;
        }
    }

    static const struct { const char* name; UINT vk; } k_Keys[] = {
        { "Space", VK_SPACE }, { "Tab", VK_TAB }, { "Home", VK_HOME }, { "End", VK_END },
        { "Insert", VK_INSERT }, { "Delete", VK_DELETE }, { "PageUp", VK_PRIOR }, { "PageDown", VK_NEXT },
        { "Left", VK_LEFT }, { "Right", VK_RIGHT }, { "Up", VK_UP }, { "Down", VK_DOWN },
        { "Scroll", VK_SCROLL }, { "Pause", VK_PAUSE },
    };
    for (const auto& key : k_Keys) {
        if (name == key.name) {
            return key.vk;
        }
    }
    return 0;
}
#endif

bool LosslessScaling::pressHotkey()
{
#ifdef Q_OS_WIN32
    // Ctrl+Alt+S unless its settings say otherwise
    UINT key = 'S';
    QString modifiers = "Alt Control";

    QFile settings(QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation))
                   .filePath("Lossless Scaling/Settings.xml"));
    if (settings.open(QIODevice::ReadOnly)) {
        QXmlStreamReader xml(&settings);
        while (!xml.atEnd()) {
            if (xml.readNext() != QXmlStreamReader::StartElement) {
                continue;
            }
            if (xml.name() == QLatin1String("Hotkey")) {
                UINT vk = virtualKeyFromName(xml.readElementText().trimmed());
                if (vk != 0) {
                    key = vk;
                }
            }
            else if (xml.name() == QLatin1String("HotkeyModifierKeys")) {
                modifiers = xml.readElementText();
            }
            else if (xml.name() == QLatin1String("GameProfiles")) {
                break;
            }
        }
    }

    QList<UINT> keys;
    if (modifiers.contains("Control")) {
        keys << VK_CONTROL;
    }
    if (modifiers.contains("Alt")) {
        keys << VK_MENU;
    }
    if (modifiers.contains("Shift")) {
        keys << VK_SHIFT;
    }
    if (modifiers.contains("Windows")) {
        keys << VK_LWIN;
    }
    keys << key;

    // Pressed in order, released the other way around
    INPUT inputs[10] = {};
    int count = 0;
    for (UINT vk : keys) {
        inputs[count].type = INPUT_KEYBOARD;
        inputs[count].ki.wVk = (WORD)vk;
        count++;
    }
    for (int i = (int)keys.size() - 1; i >= 0; i--) {
        inputs[count].type = INPUT_KEYBOARD;
        inputs[count].ki.wVk = (WORD)keys[i];
        inputs[count].ki.dwFlags = KEYEVENTF_KEYUP;
        count++;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Lossless Scaling: pressing its hotkey (%s + %u)",
                qPrintable(modifiers), key);
    return SendInput(count, inputs, sizeof(INPUT)) == (UINT)count;
#else
    return false;
#endif
}
