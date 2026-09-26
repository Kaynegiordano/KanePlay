#pragma once

#include <QObject>
#include <QHash>
#include <QByteArray>
#include <QTimer>

#include "SDL_compat.h"

#include "settings/streamingpreferences.h"

// Short feedback sounds of the UI (res/sounds/*.wav), played through SDL
// since the UI has no other audio output. Nothing plays while streaming.
class UiSound : public QObject
{
    Q_OBJECT

public:
    explicit UiSound(StreamingPreferences* prefs);

    ~UiSound();

    // move, select, back, tab, on, off, launch, connected, notify, error
    Q_INVOKABLE void play(const QString& name);

    // Called when the focused item changes: plays "move" only if the change
    // came from keyboard or gamepad navigation, not from a click
    Q_INVOKABLE void focusMoved();

protected:
    bool eventFilter(QObject* object, QEvent* event) override;

private:
    bool openDevice();

    void closeDevice();

    StreamingPreferences* m_Prefs;
    QHash<QString, QByteArray> m_Sounds;
    SDL_AudioDeviceID m_Device;
    SDL_AudioSpec m_Spec;
    QTimer m_IdleTimer;
    quint64 m_LastKeyPressMs;
    quint64 m_LastMoveMs;
};
