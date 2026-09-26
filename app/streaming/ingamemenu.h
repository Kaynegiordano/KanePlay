#pragma once

#include <QVector>

#include "SDL_compat.h"

class Session;

// Menu shown over the game (Start + Select on a gamepad, Ctrl+Alt+Shift+O on a
// keyboard) to change a few things without leaving the stream. While it is open,
// the gamepad and keyboard drive the menu and nothing reaches the host.
class InGameMenu
{
public:
    explicit InGameMenu(Session* session);

    bool isOpen() const { return m_Open; }

    void open();
    void close();

    // A gamepad button went down while the menu is open
    void handleControllerButton(SDL_GameControllerButton button);

    // A key went down while the menu is open
    void handleKey(SDL_Keycode key);

private:
    enum Action {
        ActionResume,
        ActionStats,
        ActionFrameGen,
        ActionMouseMode,
        ActionCapture,
        ActionQuit
    };

    void rebuild();
    void render();
    void move(int direction);
    void activate();

    Session* m_Session;
    bool m_Open;
    int m_Selected;
    QVector<Action> m_Actions;
};
