#include "ingamemenu.h"
#include "session.h"

#include <QCoreApplication>

InGameMenu::InGameMenu(Session* session)
    : m_Session(session),
      m_Open(false),
      m_Selected(0)
{
}

void InGameMenu::rebuild()
{
    m_Actions.clear();
    m_Actions << ActionResume << ActionStats;
    if (m_Session->hasFrameInterpolation()) {
        m_Actions << ActionFrameGen << ActionFrameGenDuplicateTest;
    }
    if (m_Session->canToggleGamepadMouse()) {
        m_Actions << ActionMouseMode;
    }
    if (m_Session->hasFrameInterpolation()) {
        m_Actions << ActionCapture;
    }
    m_Actions << ActionQuit;

    m_Selected = SDL_clamp(m_Selected, 0, (int)m_Actions.size() - 1);
}

void InGameMenu::render()
{
    Overlay::MenuModel model;
    model.title = m_Session->getAppName();
    model.subtitle = m_Session->getComputerName();
    model.selected = m_Selected;
    model.hints = QCoreApplication::translate("InGameMenu", "A  Choose        B  Back to the game");
    model.scale = m_Session->getWindowPixelHeight() / 1080.0f;

    for (Action action : std::as_const(m_Actions)) {
        Overlay::MenuItem item = {};
        switch (action) {
        case ActionResume:
            item.label = QCoreApplication::translate("InGameMenu", "Resume");
            break;
        case ActionStats:
            item.label = QCoreApplication::translate("InGameMenu", "Performance stats");
            item.isToggle = true;
            item.toggleOn = m_Session->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug);
            break;
        case ActionFrameGen:
            item.label = QCoreApplication::translate("InGameMenu", "Frame doubler ×2");
            item.isToggle = true;
            item.toggleOn = !m_Session->isFrameInterpolationPaused();
            break;
        case ActionFrameGenDuplicateTest:
            item.label = QCoreApplication::translate("InGameMenu", "Duplicate decoded frames (test)");
            item.isToggle = true;
            item.toggleOn = m_Session->isFrameInterpolationDuplicateTest();
            break;
        case ActionMouseMode:
            item.label = QCoreApplication::translate("InGameMenu", "Mouse with the gamepad");
            item.isToggle = true;
            item.toggleOn = m_Session->isGamepadMouseActive();
            break;
        case ActionCapture:
            item.label = QCoreApplication::translate("InGameMenu", "Diagnostic capture");
            break;
        case ActionQuit:
            item.label = QCoreApplication::translate("InGameMenu", "Disconnect");
            item.danger = true;
            break;
        }
        model.items.append(item);
    }

    m_Session->getOverlayManager().showMenu(model);
}

void InGameMenu::open()
{
    if (m_Open) {
        return;
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "In-game menu opened");
    m_Open = true;
    m_Selected = 0;
    rebuild();
    render();
}

void InGameMenu::close()
{
    if (!m_Open) {
        return;
    }

    m_Open = false;
    m_Session->getOverlayManager().setOverlayState(Overlay::OverlayMenu, false);
}

void InGameMenu::move(int direction)
{
    m_Selected = (m_Selected + direction + m_Actions.size()) % m_Actions.size();
    render();
}

void InGameMenu::activate()
{
    switch (m_Actions[m_Selected]) {
    case ActionResume:
        close();
        break;
    case ActionStats:
        m_Session->getOverlayManager().setOverlayState(Overlay::OverlayDebug,
                                                       !m_Session->getOverlayManager().isOverlayEnabled(Overlay::OverlayDebug));
        render();
        break;
    case ActionFrameGen:
        m_Session->setFrameInterpolationPaused(!m_Session->isFrameInterpolationPaused());
        render();
        break;
    case ActionFrameGenDuplicateTest:
        m_Session->setFrameInterpolationDuplicateTest(!m_Session->isFrameInterpolationDuplicateTest());
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Frame interpolation diagnostic: duplicate decoded frames %s",
                    m_Session->isFrameInterpolationDuplicateTest() ? "on" : "off");
        render();
        break;
    case ActionMouseMode:
        m_Session->toggleGamepadMouse();
        render();
        break;
    case ActionCapture:
        // Close first so the capture shows the game
        close();
        m_Session->requestFrameCapture();
        break;
    case ActionQuit: {
        close();

        // Same as the disconnect combo: the host is left as it is
        SDL_Event event;
        event.type = SDL_QUIT;
        event.quit.timestamp = SDL_GetTicks();
        SDL_PushEvent(&event);
        break;
    }
    }
}

void InGameMenu::handleControllerButton(SDL_GameControllerButton button)
{
    switch (button) {
    case SDL_CONTROLLER_BUTTON_DPAD_UP:
        move(-1);
        break;
    case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
        move(1);
        break;
    case SDL_CONTROLLER_BUTTON_A:
        activate();
        break;
    case SDL_CONTROLLER_BUTTON_B:
    case SDL_CONTROLLER_BUTTON_START:
    case SDL_CONTROLLER_BUTTON_BACK:
        close();
        break;
    default:
        break;
    }
}

void InGameMenu::handleKey(SDL_Keycode key)
{
    switch (key) {
    case SDLK_UP:
        move(-1);
        break;
    case SDLK_DOWN:
        move(1);
        break;
    case SDLK_RETURN:
    case SDLK_KP_ENTER:
    case SDLK_SPACE:
        activate();
        break;
    case SDLK_ESCAPE:
        close();
        break;
    default:
        break;
    }
}
