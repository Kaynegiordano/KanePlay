#include "overlaymanager.h"
#include "path.h"

#include <QFile>

#include <cmath>

using namespace Overlay;

// Colors of the KanePlay design, for the in-game menu
static const SDL_Color k_MenuBackground = { 0x18, 0x1A, 0x21, 0xF5 };
static const SDL_Color k_MenuRaised = { 0x22, 0x25, 0x2E, 0xFF };
static const SDL_Color k_MenuAccent = { 0xFF, 0x6A, 0x3D, 0xFF };
static const SDL_Color k_MenuAccentText = { 0x14, 0x10, 0x0C, 0xFF };
static const SDL_Color k_MenuText = { 0xF4, 0xF1, 0xEC, 0xFF };
static const SDL_Color k_MenuTextSecondary = { 0xA9, 0xAB, 0xB4, 0xFF };
static const SDL_Color k_MenuDanger = { 0xFF, 0x7A, 0x70, 0xFF };
static const SDL_Color k_MenuSwitchOff = { 0x2E, 0x32, 0x3D, 0xFF };

// Draws color over the ARGB8888 pixel, with the given coverage (0 to 1)
static void blendPixel(Uint32* pixel, SDL_Color color, float coverage)
{
    float srcA = color.a / 255.0f * coverage;
    if (srcA <= 0) {
        return;
    }

    Uint32 dst = *pixel;
    float dstA = ((dst >> 24) & 0xFF) / 255.0f;
    float outA = srcA + dstA * (1 - srcA);
    auto channel = [&](int shift, Uint8 src) {
        float d = ((dst >> shift) & 0xFF) / 255.0f;
        float out = (src / 255.0f * srcA + d * dstA * (1 - srcA)) / outA;
        return (Uint32)SDL_clamp((int)(out * 255 + 0.5f), 0, 255);
    };
    *pixel = ((Uint32)(outA * 255 + 0.5f) << 24) | (channel(16, color.r) << 16) | (channel(8, color.g) << 8) | channel(0, color.b);
}

// Fills a rounded rectangle, with antialiased corners
static void fillRoundedRect(SDL_Surface* surface, float x, float y, float w, float h, float radius, SDL_Color color)
{
    SDL_LockSurface(surface);
    Uint32* pixels = (Uint32*)surface->pixels;
    int pitch = surface->pitch / 4;

    int x0 = SDL_max(0, (int)floorf(x));
    int y0 = SDL_max(0, (int)floorf(y));
    int x1 = SDL_min(surface->w, (int)ceilf(x + w));
    int y1 = SDL_min(surface->h, (int)ceilf(y + h));

    for (int py = y0; py < y1; py++) {
        for (int px = x0; px < x1; px++) {
            // Distance from the pixel center to the rounded shape
            float cx = px + 0.5f, cy = py + 0.5f;
            float nx = SDL_clamp(cx, x + radius, x + w - radius);
            float ny = SDL_clamp(cy, y + radius, y + h - radius);
            float dist = sqrtf((cx - nx) * (cx - nx) + (cy - ny) * (cy - ny)) - radius;

            // And from the pixel to the edges of the rectangle itself
            float edge = SDL_min(SDL_min(cx - x, x + w - cx), SDL_min(cy - y, y + h - cy));
            float coverage = SDL_clamp(0.5f - dist, 0.0f, 1.0f) * SDL_clamp(edge + 0.5f, 0.0f, 1.0f);

            blendPixel(&pixels[py * pitch + px], color, coverage);
        }
    }

    SDL_UnlockSurface(surface);
}

// Draws UTF-8 text with its top left corner at (x, y), returns its width
static int drawText(SDL_Surface* surface, TTF_Font* font, const QString& text, SDL_Color color, int x, int y)
{
    if (font == nullptr || text.isEmpty()) {
        return 0;
    }

    SDL_Surface* textSurface = TTF_RenderUTF8_Blended(font, text.toUtf8().constData(), color);
    if (textSurface == nullptr) {
        return 0;
    }

    SDL_Rect dst = { x, y, textSurface->w, textSurface->h };
    SDL_SetSurfaceBlendMode(textSurface, SDL_BLENDMODE_BLEND);
    SDL_BlitSurface(textSurface, nullptr, surface, &dst);
    int width = textSurface->w;
    SDL_FreeSurface(textSurface);
    return width;
}

OverlayManager::OverlayManager() :
    m_Renderer(nullptr),
    m_FontData(Path::readDataFile("ModeSeven.ttf"))
{
    memset(m_Overlays, 0, sizeof(m_Overlays));

#ifdef Q_OS_WIN32
    // Prefer a clean system UI font for the stats panel when available
    QFile segoeFont("C:/Windows/Fonts/segoeui.ttf");
    if (segoeFont.open(QIODevice::ReadOnly)) {
        m_DebugFontData = segoeFont.readAll();
    }
#endif

    m_Overlays[OverlayType::OverlayDebug].color = {0xF0, 0xF3, 0xF8, 0xFF};
    m_Overlays[OverlayType::OverlayDebug].fontSize = 17;

    m_Overlays[OverlayType::OverlayStatusUpdate].color = {0xF0, 0xF3, 0xF8, 0xFF};
    m_Overlays[OverlayType::OverlayStatusUpdate].fontSize = 18;

    m_Menu.selected = 0;
    m_Menu.scale = 1.0f;

#ifdef Q_OS_WIN32
    const char* menuFonts[] = { "C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/seguisb.ttf", "C:/Windows/Fonts/segoeuib.ttf" };
    for (int i = 0; i < 3; i++) {
        QFile menuFont(menuFonts[i]);
        if (menuFont.open(QIODevice::ReadOnly)) {
            m_MenuFontData[i] = menuFont.readAll();
        }
    }
#endif
    for (int i = 0; i < 3; i++) {
        if (m_MenuFontData[i].isEmpty()) {
            m_MenuFontData[i] = !m_DebugFontData.isEmpty() ? m_DebugFontData : m_FontData;
        }
    }

    // While TTF will usually not be initialized here, it is valid for that not to
    // be the case, since Session destruction is deferred and could overlap with
    // the lifetime of a new Session object.
    //SDL_assert(TTF_WasInit() == 0);

    if (TTF_Init() != 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "TTF_Init() failed: %s",
                    TTF_GetError());
        return;
    }
}

OverlayManager::~OverlayManager()
{
    for (int i = 0; i < OverlayType::OverlayMax; i++) {
        if (m_Overlays[i].surface != nullptr) {
            SDL_FreeSurface(m_Overlays[i].surface);
        }
        if (m_Overlays[i].font != nullptr) {
            TTF_CloseFont(m_Overlays[i].font);
        }
    }

    TTF_Quit();

    // For similar reasons to the comment in the constructor, this will usually,
    // but not always, deinitialize TTF. In the cases where Session objects overlap
    // in lifetime, there may be an additional reference on TTF for the new Session
    // that means it will not be cleaned up here.
    //SDL_assert(TTF_WasInit() == 0);
}

bool OverlayManager::isOverlayEnabled(OverlayType type)
{
    return m_Overlays[type].enabled;
}

char* OverlayManager::getOverlayText(OverlayType type)
{
    return m_Overlays[type].text;
}

void OverlayManager::updateOverlayText(OverlayType type, const char* text)
{
    SDL_utf8strlcpy(m_Overlays[type].text, text, sizeof(m_Overlays[0].text));
    setOverlayTextUpdated(type);
}

int OverlayManager::getOverlayMaxTextLength()
{
    return sizeof(m_Overlays[0].text);
}

int OverlayManager::getOverlayFontSize(OverlayType type)
{
    return m_Overlays[type].fontSize;
}

SDL_Surface* OverlayManager::getUpdatedOverlaySurface(OverlayType type)
{
    // If a new surface is available, return it. If not, return nullptr.
    // Caller must free the surface on success.
    return (SDL_Surface*)SDL_AtomicSetPtr((void**)&m_Overlays[type].surface, nullptr);
}

void OverlayManager::setOverlayTextUpdated(OverlayType type)
{
    // Only update the overlay state if it's enabled. If it's not enabled,
    // the renderer has already been notified by setOverlayState().
    if (m_Overlays[type].enabled) {
        notifyOverlayUpdated(type);
    }
}

void OverlayManager::setOverlayState(OverlayType type, bool enabled)
{
    bool stateChanged = m_Overlays[type].enabled != enabled;

    m_Overlays[type].enabled = enabled;

    if (stateChanged) {
        if (!enabled) {
            // Set the text to empty string on disable
            m_Overlays[type].text[0] = 0;
        }

        notifyOverlayUpdated(type);
    }
}

SDL_Color OverlayManager::getOverlayColor(OverlayType type)
{
    return m_Overlays[type].color;
}

void OverlayManager::setOverlayRenderer(IOverlayRenderer* renderer)
{
    m_Renderer = renderer;
}

void OverlayManager::showMenu(const MenuModel& model)
{
    m_Menu = model;
    m_Overlays[OverlayType::OverlayMenu].enabled = true;
    notifyOverlayUpdated(OverlayType::OverlayMenu);
}

void OverlayManager::notifyOverlayUpdated(OverlayType type)
{
    if (m_Renderer == nullptr) {
        return;
    }

    // The menu draws itself with its own fonts
    if (type == OverlayType::OverlayMenu) {
        SDL_Surface* menuSurface = m_Overlays[type].enabled ? RenderMenuPanel() : nullptr;
        SDL_Surface* oldMenuSurface = (SDL_Surface*)SDL_AtomicSetPtr((void**)&m_Overlays[type].surface, menuSurface);
        m_Renderer->notifyOverlayUpdated(type);
        if (oldMenuSurface != nullptr) {
            SDL_FreeSurface(oldMenuSurface);
        }
        return;
    }

    // Construct the required font to render the overlay
    if (m_Overlays[type].font == nullptr) {
        // Panels prefer the system UI font when one was loaded
        QByteArray& fontData = !m_DebugFontData.isEmpty() ? m_DebugFontData : m_FontData;

        if (fontData.isEmpty()) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "SDL overlay font failed to load");
            return;
        }

        // fontData must stay around until the font is closed
        m_Overlays[type].font = TTF_OpenFontRW(SDL_RWFromConstMem(fontData.constData(), fontData.size()),
                                               1,
                                               m_Overlays[type].fontSize);
        if (m_Overlays[type].font == nullptr) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "TTF_OpenFont() failed: %s",
                        TTF_GetError());

            // Can't proceed without a font
            return;
        }
    }

    // Exchange the old surface with the new one
    SDL_Surface* newSurface = nullptr;
    if (m_Overlays[type].enabled) {
        // Both overlays render as compact panels instead of large outlined text:
        // blue for the stats, amber for status messages like connection warnings.
        newSurface = RenderStatsPanel(m_Overlays[type].font,
                                      m_Overlays[type].text,
                                      m_Overlays[type].color,
                                      type == OverlayType::OverlayDebug ? SDL_Color{0x8F, 0xB4, 0xFF, 0xFF}
                                                                        : SDL_Color{0xF2, 0xC6, 0x6D, 0xFF},
                                      1024);
    }
    SDL_Surface* oldSurface = (SDL_Surface*)SDL_AtomicSetPtr(
        (void**)&m_Overlays[type].surface, newSurface);

    // Notify the renderer
    m_Renderer->notifyOverlayUpdated(type);

    // Free the old surface
    if (oldSurface != nullptr) {
        SDL_FreeSurface(oldSurface);
    }
}

// Render overlay text as a compact panel: translucent dark card with rounded
// corners and an accent bar, in the style of typical performance HUDs.
SDL_Surface* OverlayManager::RenderStatsPanel(TTF_Font* font, const char* text, SDL_Color textColor, SDL_Color accentColor, int wrapWidth)
{
    if (text == nullptr || text[0] == '\0') {
        return nullptr;
    }

    SDL_Surface* textSurface = TTF_RenderUTF8_Blended_Wrapped(font, text, textColor, wrapWidth);
    if (textSurface == nullptr) {
        return nullptr;
    }

    // The wrapped render surface can be as wide as wrapWidth; measure the widest
    // actual line so the card hugs the text instead of painting the whole surface.
    int textW = 0;
    for (const QString& line : QString(text).split('\n')) {
        int lineW = 0, lineH = 0;
        if (!line.isEmpty() && TTF_SizeUTF8(font, line.toUtf8(), &lineW, &lineH) == 0) {
            textW = qMax(textW, lineW);
        }
    }
    if (textW == 0 || textW > textSurface->w) {
        textW = textSurface->w;
    }
    int textH = textSurface->h;

    constexpr int kPadX = 14;
    constexpr int kPadY = 10;
    constexpr int kAccent = 3;   // width of the accent bar on the left edge
    constexpr int kRadius = 9;   // corner radius

    int w = textW + kAccent + 2 * kPadX;
    int h = textH + 2 * kPadY;

    SDL_Surface* panel = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_ARGB8888);
    if (panel == nullptr) {
        SDL_FreeSurface(textSurface);
        return nullptr;
    }

    // Card background
    SDL_FillRect(panel, nullptr, SDL_MapRGBA(panel->format, 0x0C, 0x0E, 0x14, 0xD0));

    // Accent bar (left edge)
    SDL_Rect accentRect = { 0, 0, kAccent, h };
    SDL_FillRect(panel, &accentRect, SDL_MapRGBA(panel->format, accentColor.r, accentColor.g, accentColor.b, accentColor.a));

    // Round the corners by clearing pixels outside each corner's arc
    SDL_LockSurface(panel);
    Uint32* pixels = (Uint32*)panel->pixels;
    int pitch = panel->pitch / 4;
    for (int cy = 0; cy < kRadius; cy++) {
        for (int cx = 0; cx < kRadius; cx++) {
            int dx = kRadius - 1 - cx;
            int dy = kRadius - 1 - cy;
            if (dx * dx + dy * dy > kRadius * kRadius) {
                pixels[cy * pitch + cx] = 0;                          // top-left
                pixels[cy * pitch + (w - 1 - cx)] = 0;                // top-right
                pixels[(h - 1 - cy) * pitch + cx] = 0;                // bottom-left
                pixels[(h - 1 - cy) * pitch + (w - 1 - cx)] = 0;      // bottom-right
            }
        }
    }
    SDL_UnlockSurface(panel);

    SDL_Rect src = { 0, 0, textW, textH };
    SDL_Rect dst = { kAccent + kPadX, kPadY, textW, textH };
    SDL_BlitSurface(textSurface, &src, panel, &dst);
    SDL_FreeSurface(textSurface);

    return panel;
}

// The in-game menu: a dark card with the app, then one row per action, the
// selected one raised with an ember border, and the gamepad hints at the bottom
SDL_Surface* OverlayManager::RenderMenuPanel()
{
    const float s = SDL_clamp(m_Menu.scale, 0.6f, 3.0f);
    auto px = [s](float value) { return (int)lroundf(value * s); };

    TTF_Font* regular = TTF_OpenFontRW(SDL_RWFromConstMem(m_MenuFontData[0].constData(), m_MenuFontData[0].size()), 1, px(15));
    TTF_Font* hintFont = TTF_OpenFontRW(SDL_RWFromConstMem(m_MenuFontData[0].constData(), m_MenuFontData[0].size()), 1, px(13));
    TTF_Font* semibold = TTF_OpenFontRW(SDL_RWFromConstMem(m_MenuFontData[1].constData(), m_MenuFontData[1].size()), 1, px(17));
    TTF_Font* bold = TTF_OpenFontRW(SDL_RWFromConstMem(m_MenuFontData[2].constData(), m_MenuFontData[2].size()), 1, px(21));

    SDL_Surface* panel = nullptr;
    if (regular != nullptr && hintFont != nullptr && semibold != nullptr && bold != nullptr) {
        const int width = px(400);
        const int pad = px(24);
        const int rowHeight = px(54);
        const int rowGap = px(6);
        const int titleHeight = TTF_FontHeight(bold);
        const int subtitleHeight = TTF_FontHeight(regular);
        const int hintHeight = TTF_FontHeight(hintFont);
        const int itemsTop = pad + titleHeight + px(2) + subtitleHeight + px(20);
        const int itemsHeight = m_Menu.items.size() * (rowHeight + rowGap) - rowGap;
        const int height = itemsTop + itemsHeight + px(22) + hintHeight + pad;

        panel = SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, SDL_PIXELFORMAT_ARGB8888);
        if (panel != nullptr) {
            SDL_FillRect(panel, nullptr, 0);
            fillRoundedRect(panel, 0, 0, width, height, px(24), k_MenuBackground);

            drawText(panel, bold, m_Menu.title, k_MenuText, pad, pad);
            drawText(panel, regular, m_Menu.subtitle, k_MenuTextSecondary, pad, pad + titleHeight + px(2));

            for (int i = 0; i < m_Menu.items.size(); i++) {
                const MenuItem& item = m_Menu.items[i];
                int rowX = px(12);
                int rowY = itemsTop + i * (rowHeight + rowGap);
                int rowW = width - 2 * rowX;

                if (i == m_Menu.selected) {
                    fillRoundedRect(panel, rowX, rowY, rowW, rowHeight, px(14), k_MenuAccent);
                    fillRoundedRect(panel, rowX + px(2), rowY + px(2), rowW - px(4), rowHeight - px(4), px(12), k_MenuRaised);
                }

                SDL_Color labelColor = item.danger ? k_MenuDanger : k_MenuText;
                drawText(panel, semibold, item.label, labelColor, rowX + px(16), rowY + (rowHeight - TTF_FontHeight(semibold)) / 2);

                if (item.isToggle) {
                    // A switch on the right, like the ones of the settings
                    float trackW = 44 * s, trackH = 24 * s;
                    float trackX = rowX + rowW - px(16) - trackW;
                    float trackY = rowY + (rowHeight - trackH) / 2;
                    fillRoundedRect(panel, trackX, trackY, trackW, trackH, trackH / 2, item.toggleOn ? k_MenuAccent : k_MenuSwitchOff);

                    float thumb = 18 * s;
                    float thumbX = item.toggleOn ? trackX + trackW - thumb - 3 * s : trackX + 3 * s;
                    fillRoundedRect(panel, thumbX, trackY + (trackH - thumb) / 2, thumb, thumb, thumb / 2,
                                    item.toggleOn ? k_MenuAccentText : k_MenuTextSecondary);
                }
            }

            drawText(panel, hintFont, m_Menu.hints, k_MenuTextSecondary, pad, height - pad - hintHeight);
        }
    }

    for (TTF_Font* font : { regular, hintFont, semibold, bold }) {
        if (font != nullptr) {
            TTF_CloseFont(font);
        }
    }

    return panel;
}

SDL_Surface* OverlayManager::RenderTextOutlinedWrapped(TTF_Font* font, const char* text, SDL_Color textColor, SDL_Color outlineColor, int outlineWidth, int wrapWidth) {
    if (text == nullptr || text[0] == '\0') {
        return nullptr;
    }

    int oldOutline = TTF_GetFontOutline(font);
    TTF_SetFontOutline(font, outlineWidth);

    // Verify that the string won't require wrapping (which could cause the outline and the text
    // to diverge due to different wrapping positions).
    //
    // FIXME: We do this rather than just disabling wrapping entirely (wrapWidth = 0) because we
    // need further testing to ensure that all renderers can handle non-NPOT overlay textures.
    for (const QString& line : QString(text).split('\n')) {
        int extent, count;
        if (TTF_MeasureUTF8(font, line.toUtf8(), wrapWidth, &extent, &count) == 0 && count < line.size()) {
            // If it requires wrapping, render it without the outline
            TTF_SetFontOutline(font, oldOutline);
            return TTF_RenderUTF8_Blended_Wrapped(font, text, textColor, wrapWidth);
        }
    }

    // Draw text twice, but outline is a bit bigger
    auto outlineSurface = TTF_RenderUTF8_Blended_Wrapped(font, text, outlineColor, wrapWidth);
    TTF_SetFontOutline(font, 0);
    auto textSurface = TTF_RenderUTF8_Blended_Wrapped(font, text, textColor, wrapWidth);
    TTF_SetFontOutline(font, oldOutline);

    if (outlineSurface == nullptr || textSurface == nullptr) {
        SDL_FreeSurface(outlineSurface);
        SDL_FreeSurface(textSurface);
        return nullptr;
    }

    // Merge the texts
    SDL_Rect dst = { outlineWidth, outlineWidth, textSurface->w, textSurface->h };
    SDL_BlitSurface(textSurface, nullptr, outlineSurface, &dst);

    SDL_FreeSurface(textSurface);
    return outlineSurface;
}


