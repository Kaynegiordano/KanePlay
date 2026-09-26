#include "uisound.h"

#include <QFile>
#include <QKeyEvent>
#include <QGuiApplication>
#include <QDateTime>

// The audio device is closed after this long without sounds, so it doesn't
// sit open next to the stream's own audio output
#define IDLE_CLOSE_DELAY_MS 5000

// A focus change this soon after a navigation key press counts as navigation
#define NAVIGATION_WINDOW_MS 250

// Holding a direction repeats moves quickly, don't tick on every one of them
#define MIN_MOVE_INTERVAL_MS 45

static const char* k_SoundNames[] = {
    "move", "select", "back", "tab", "on", "off", "launch", "connected", "notify", "error"
};

// Sounds that shouldn't be cut short by navigation feedback
static bool isLongSound(const QString& name)
{
    return name == "launch" || name == "connected" || name == "notify" || name == "error";
}

UiSound::UiSound(StreamingPreferences* prefs)
    : m_Prefs(prefs),
      m_Device(0),
      m_LastKeyPressMs(0),
      m_LastMoveMs(0)
{
    SDL_zero(m_Spec);

    for (const char* name : k_SoundNames) {
        QFile file(QString(":/res/sounds/%1.wav").arg(name));
        if (!file.open(QIODevice::ReadOnly)) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Missing UI sound: %s", name);
            continue;
        }

        QByteArray wav = file.readAll();
        SDL_AudioSpec spec;
        Uint8* buffer;
        Uint32 length;
        if (SDL_LoadWAV_RW(SDL_RWFromConstMem(wav.constData(), wav.size()), 1, &spec, &buffer, &length) == nullptr) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Unable to load UI sound %s: %s", name, SDL_GetError());
            continue;
        }

        // All the sounds share one format, the device is opened with it
        if (m_Spec.freq == 0) {
            m_Spec = spec;
        }
        if (spec.freq == m_Spec.freq && spec.format == m_Spec.format && spec.channels == m_Spec.channels) {
            m_Sounds.insert(name, QByteArray((const char*)buffer, (int)length));
        }
        else {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "UI sound %s has a different format", name);
        }
        SDL_FreeWAV(buffer);
    }

    m_IdleTimer.setSingleShot(true);
    connect(&m_IdleTimer, &QTimer::timeout, this, &UiSound::closeDevice);

    qApp->installEventFilter(this);
}

UiSound::~UiSound()
{
    qApp->removeEventFilter(this);
    closeDevice();
}

bool UiSound::openDevice()
{
    if (m_Device != 0) {
        return true;
    }

    if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "SDL_InitSubSystem(SDL_INIT_AUDIO) failed: %s", SDL_GetError());
        return false;
    }

    SDL_AudioSpec want = m_Spec;
    want.samples = 512;
    want.callback = nullptr;
    m_Device = SDL_OpenAudioDevice(nullptr, 0, &want, nullptr, 0);
    if (m_Device == 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION, "Unable to open the UI sound device: %s", SDL_GetError());
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        return false;
    }

    SDL_PauseAudioDevice(m_Device, 0);
    return true;
}

void UiSound::closeDevice()
{
    if (m_Device != 0) {
        SDL_CloseAudioDevice(m_Device);
        m_Device = 0;
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
    }
}

void UiSound::play(const QString& name)
{
    if (!m_Prefs->uiSounds || m_Prefs->uiSoundVolume <= 0) {
        return;
    }

    auto sound = m_Sounds.constFind(name);
    if (sound == m_Sounds.constEnd() || !openDevice()) {
        return;
    }

    // Let a longer sound finish rather than cutting it with a short one
    static QString s_LastSound;
    if (!isLongSound(name) && isLongSound(s_LastSound) && SDL_GetQueuedAudioSize(m_Device) > 0) {
        return;
    }
    s_LastSound = name;

    QByteArray mixed(sound->size(), 0);
    SDL_MixAudioFormat((Uint8*)mixed.data(), (const Uint8*)sound->constData(), m_Spec.format,
                       (Uint32)sound->size(), m_Prefs->uiSoundVolume * SDL_MIX_MAXVOLUME / 100);

    SDL_ClearQueuedAudio(m_Device);
    SDL_QueueAudio(m_Device, mixed.constData(), (Uint32)mixed.size());

    m_IdleTimer.start(IDLE_CLOSE_DELAY_MS);
}

void UiSound::focusMoved()
{
    quint64 now = QDateTime::currentMSecsSinceEpoch();
    if (now - m_LastKeyPressMs > NAVIGATION_WINDOW_MS || now - m_LastMoveMs < MIN_MOVE_INTERVAL_MS) {
        return;
    }

    m_LastMoveMs = now;
    play("move");
}

bool UiSound::eventFilter(QObject* object, QEvent* event)
{
    // Every window's key events pass by the application, only look at them once
    if (event->type() == QEvent::KeyPress && object->isWindowType()) {
        QKeyEvent* keyEvent = static_cast<QKeyEvent*>(event);
        switch (keyEvent->key()) {
        case Qt::Key_Up:
        case Qt::Key_Down:
        case Qt::Key_Left:
        case Qt::Key_Right:
        case Qt::Key_Tab:
        case Qt::Key_Backtab:
            m_LastKeyPressMs = QDateTime::currentMSecsSinceEpoch();
            break;
        case Qt::Key_Escape:
        case Qt::Key_Back:
            if (!keyEvent->isAutoRepeat()) {
                play("back");
            }
            break;
        default:
            break;
        }
    }

    return QObject::eventFilter(object, event);
}
