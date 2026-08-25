#include "globals.h"
#include "gui.h"
#include <GLFW/glfw3.h>
#include <string.h>
#include <ctype.h>
#include "stb_ds.h"

#define VKM_SHIFT 0x10000
#define VKM_CTRL 0x20000
#define VKM_CTRLASCII 0x40000

static GLFWwindow* window;
static int currentAttr;
static colour_t currentFg;
static colour_t currentBg;
static int screenWidth;
static int screenHeight;
static cell_t* screen;
static int cursorx;
static int cursory;
static bool cursorShown;

/* A FIFO queue built on a stb_ds dynamic array plus a read cursor: push
 * appends via arrput, pop reads from keyboardQueueHead and only actually
 * shrinks the backing array once fully drained (amortised O(1) either way,
 * same practical behaviour as the std::deque this replaces). */
static uni_t* keyboardQueue;
static int keyboardQueueHead;

static bool keyboardQueue_empty()
{
    return keyboardQueueHead >= arrlen(keyboardQueue);
}

static void keyboardQueue_push(uni_t v)
{
    arrput(keyboardQueue, v);
}

static uni_t keyboardQueue_pop()
{
    uni_t v = keyboardQueue[keyboardQueueHead++];
    if (keyboardQueueHead == arrlen(keyboardQueue))
    {
        arrsetlen(keyboardQueue, 0);
        keyboardQueueHead = 0;
    }
    return v;
}

static bool pendingRedraw;
static bool fullScreen;
static int oldWindowX;
static int oldWindowY;
static int oldWindowW;
static int oldWindowH;

static void queueRedraw()
{
    if (!pendingRedraw)
    {
        keyboardQueue_push(-KEY_RESIZE);
        pendingRedraw = true;
    }
}

static int convert_numpad_key(int key)
{
    switch (key)
    {
        case GLFW_KEY_KP_0:
            return GLFW_KEY_INSERT;
        case GLFW_KEY_KP_1:
            return GLFW_KEY_END;
        case GLFW_KEY_KP_2:
            return GLFW_KEY_DOWN;
        case GLFW_KEY_KP_3:
            return GLFW_KEY_PAGE_DOWN;
        case GLFW_KEY_KP_4:
            return GLFW_KEY_LEFT;
        case GLFW_KEY_KP_5:
            return 0;
        case GLFW_KEY_KP_6:
            return GLFW_KEY_RIGHT;
        case GLFW_KEY_KP_7:
            return GLFW_KEY_HOME;
        case GLFW_KEY_KP_8:
            return GLFW_KEY_UP;
        case GLFW_KEY_KP_9:
            return GLFW_KEY_PAGE_UP;
        case GLFW_KEY_KP_DECIMAL:
            return GLFW_KEY_DELETE;
    }
    return key;
}

static void key_cb(
    GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (action == GLFW_RELEASE)
        return;

    int ascii = 0;
    if ((key >= GLFW_KEY_A) && (key <= GLFW_KEY_Z))
    {
        const char* name = glfwGetKeyName(key, scancode);
        if (name)
            ascii = toupper(name[0]);
    }

    if ((mods & GLFW_MOD_CONTROL) && (mods & GLFW_MOD_ALT) && ascii &&
        strchr("HJKLBWIOAEUDTGX", ascii))
    {
        int shifted = (mods & GLFW_MOD_SHIFT) ? VKM_SHIFT : 0;
        keyboardQueue_push(-(KEYM_ALTCHAR | VKM_CTRL | shifted | ascii));
        return;
    }
    if (mods & GLFW_MOD_CONTROL)
    {
        if (ascii)
        {
            keyboardQueue_push(-((ascii - 'A' + 1) | VKM_CTRLASCII));
            return;
        }
        if (key == GLFW_KEY_SPACE)
        {
            keyboardQueue_push(-VKM_CTRLASCII);
            return;
        }
    }
    if (mods & GLFW_MOD_ALT)
    {
        if (key == GLFW_KEY_ENTER)
        {
            /* Toggle full screen. */

            if (fullScreen)
            {
                glfwSetWindowMonitor(window,
                    NULL,
                    oldWindowX,
                    oldWindowY,
                    oldWindowW,
                    oldWindowH,
                    0);
                fullScreen = false;
            }
            else
            {
                glfwGetWindowPos(window, &oldWindowX, &oldWindowY);
                glfwGetWindowSize(window, &oldWindowW, &oldWindowH);
                GLFWmonitor* monitor = glfwGetPrimaryMonitor();
                const GLFWvidmode* mode = glfwGetVideoMode(monitor);
                glfwSetWindowMonitor(window,
                    monitor,
                    0,
                    0,
                    mode->width,
                    mode->height,
                    mode->refreshRate);
                fullScreen = true;
            }

            return;
        }
        if (ascii)
        {
            if ((ascii == 'H') || (ascii == 'N'))
            {
                keyboardQueue_push(-(KEYM_ALTCHAR | ascii));
                return;
            }
            keyboardQueue_push(-GLFW_KEY_ESCAPE);
            keyboardQueue_push(ascii);
            return;
        }
    }

    if (!(mods & GLFW_MOD_NUM_LOCK))
    {
        key = convert_numpad_key(key);
        if (!key)
            return;
    }

    switch (key)
    {
        default:
            if ((key < GLFW_KEY_F1) || (key > GLFW_KEY_F25))
                return;

            /* fall through */
        case GLFW_KEY_ESCAPE:
        case GLFW_KEY_ENTER:
        case GLFW_KEY_TAB:
        case GLFW_KEY_BACKSPACE:
        case GLFW_KEY_INSERT:
        case GLFW_KEY_DELETE:
        case GLFW_KEY_RIGHT:
        case GLFW_KEY_LEFT:
        case GLFW_KEY_DOWN:
        case GLFW_KEY_UP:
        case GLFW_KEY_PAGE_UP:
        case GLFW_KEY_PAGE_DOWN:
        case GLFW_KEY_HOME:
        case GLFW_KEY_END:
        {
            int imods = 0;
            if (mods & GLFW_MOD_SHIFT)
                imods |= VKM_SHIFT;
            if (mods & GLFW_MOD_CONTROL)
                imods |= VKM_CTRL;
            keyboardQueue_push(-(key | imods));
            break;
        }
    }
}

static void character_cb(GLFWwindow* window, unsigned int c)
{
    keyboardQueue_push(c);
}

static void resize_cb(GLFWwindow* window, int width, int height)
{
    queueRedraw();
}

static void refresh_cb(GLFWwindow* window)
{
    queueRedraw();
}

static void close_cb(GLFWwindow* window)
{
    keyboardQueue_push(-KEY_QUIT);
}

static void handle_mouse(double x, double y, bool b)
{
    static bool motion = false;
    if (!b && !motion)
        return;
    motion = b;

    /* glfwGetCursorPos()/the cursor-pos callback report positions in screen
     * coordinates, but fontWidth/fontHeight (and the screen[] grid) are
     * sized against the framebuffer, in pixels -- these differ on displays
     * with a content scale other than 100% (common on HiDPI/fractional-
     * scaling setups). Rescale into framebuffer pixels before dividing, or
     * clicks land on the wrong row/column. */
    int ww, wh, fw, fh;
    glfwGetWindowSize(window, &ww, &wh);
    glfwGetFramebufferSize(window, &fw, &fh);
    if (ww > 0)
        x = x * fw / ww;
    if (wh > 0)
        y = y * fh / wh;

    /* The grid is anchored to the bottom of the framebuffer (see dpy_sync),
     * so row 0 doesn't necessarily start at y=0 -- there can be a leftover
     * margin above it when fh isn't an exact multiple of fontHeight. Undo
     * that same offset here, or clicks on the status bar (and everything
     * else) would land one row off whenever such a margin exists. */
    int yOffset = fh % fontHeight;
    int ix = x / fontWidth;
    int iy = ((int)y - yOffset) / fontHeight;
    if ((int)y < yOffset)
        iy = -1;
    static int oldix = -1;
    static int oldiy = -1;
    static bool oldb = false;

    if ((ix != oldix) || (iy != oldiy) || (b != oldb))
    {
        keyboardQueue_push(-encode_mouse_event(ix, iy, b));
        oldix = ix;
        oldiy = iy;
        oldb = b;
    }
}

static void mousepos_cb(GLFWwindow* window, double x, double y)
{
    handle_mouse(x, y, glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_LEFT));
}

static void mousebutton_cb(GLFWwindow* window, int button, int action, int mods)
{
    switch (button)
    {
        case GLFW_MOUSE_BUTTON_LEFT:
        {
            double x, y;
            glfwGetCursorPos(window, &x, &y);
            handle_mouse(x, y, (action == GLFW_PRESS) ? true : false);
            break;
        }

        case GLFW_MOUSE_BUTTON_RIGHT:
            if (action == GLFW_PRESS)
                keyboardQueue_push(-KEY_MENU);
            break;
    }
}

void scroll_cb(GLFWwindow* window, double xoffset, double yoffset)
{
    if (yoffset < 0)
        keyboardQueue_push(-KEY_SCROLLDOWN);
    else
        keyboardQueue_push(-KEY_SCROLLUP);
}

void dpy_init(const char* argv[]) {}

void dpy_start(void)
{
    if (!glfwInit())
    {
        fprintf(stderr, "OpenGL initialisation failed\n");
        exit(1);
    }

    /* Let desktop environments associate this window with
     * wordprocess.desktop.  Wayland intentionally ignores
     * glfwSetWindowIcon() and resolves the icon from this application ID. */
#ifdef GLFW_WAYLAND_APP_ID
    glfwWindowHintString(GLFW_WAYLAND_APP_ID, "wordprocess");
#endif
#ifdef GLFW_X11_CLASS_NAME
    glfwWindowHintString(GLFW_X11_CLASS_NAME, "WordProcess");
    glfwWindowHintString(GLFW_X11_INSTANCE_NAME, "wordprocess");
#endif

    window = glfwCreateWindow(get_ivar("window_width"),
        get_ivar("window_height"),
        "WordProcess",
        NULL,
        NULL);
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    glfwSetInputMode(window, GLFW_LOCK_KEY_MODS, GLFW_TRUE);
    glfwSetCursor(window, glfwCreateStandardCursor(GLFW_IBEAM_CURSOR));
    glfwSetKeyCallback(window, key_cb);
    glfwSetCharCallback(window, character_cb);
    glfwSetCursorPosCallback(window, mousepos_cb);
    glfwSetMouseButtonCallback(window, mousebutton_cb);
    glfwSetWindowSizeCallback(window, resize_cb);
    glfwSetWindowRefreshCallback(window, refresh_cb);
    glfwSetWindowCloseCallback(window, close_cb);
    glfwSetScrollCallback(window, scroll_cb);

    extern uint8_t icon_data[];
    GLFWimage image;
    image.width = 128;
    image.height = 128;
    image.pixels = icon_data;
    glfwSetWindowIcon(window, 1, &image);

    loadFonts();
}

void dpy_shutdown(void)
{
    unloadFonts();
    flushFontCache();
    glfwDestroyWindow(window);
    glfwTerminate();
}

void dpy_clearscreen(void)
{
    dpy_cleararea(0, 0, screenWidth - 1, screenHeight - 1);
}

void dpy_getscreensize(int* x, int* y)
{
    *x = screenWidth;
    *y = screenHeight;
}

void dpy_getmouse(uni_t key, int* x, int* y, bool* p)
{
    x = y = 0;
    *p = false;
}

void dpy_sync(void)
{
    pendingRedraw = false;

    /* Configure viewport for 2D graphics. */

    glClearColor(0.0, 0.0, 0.0, 1.0);
    glEnable(GL_TEXTURE_2D);
    glEnable(GL_COLOR_MATERIAL);
    glEnable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glDisable(GL_CULL_FACE);
    glDisable(GL_LINE_SMOOTH);
    glEnable(GL_POLYGON_SMOOTH);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glLineWidth(1);

    int w, h;
    glfwGetFramebufferSize(window, &w, &h);
    glViewport(0, 0, w, h);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, w, h, 0, 0, 1);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glClear(GL_COLOR_BUFFER_BIT);

    int sw = w / fontWidth;
    int sh = h / fontHeight;
    if (!screen || (screenWidth != sw) || (screenHeight != sh))
    {
        free(screen);
        screenWidth = sw;
        screenHeight = sh;
        screen = (cell_t*)malloc(sizeof(cell_t) * screenWidth * screenHeight);
        keyboardQueue_push(-KEY_RESIZE);
    }
    else
    {
        /* screenHeight is floor(h/fontHeight): h generally isn't an exact
         * multiple of fontHeight, so there are 0..fontHeight-1 leftover
         * pixels that don't fit a whole row. Anchoring row 0 at y=0 would
         * push that leftover below the last row (the status bar), whose
         * apparent thickness would then change with every resize as the
         * leftover grows and shrinks. Anchoring to the bottom instead
         * keeps every row, including the status bar, at exactly
         * fontHeight regardless of window size -- the leftover always
         * lands above row 0, in the ordinary document background, where
         * a few pixels of slack isn't a visible "bar" changing size. */
        int yOffset = h - screenHeight * fontHeight;

        const cell_t* p = &screen[0];
        for (int y = 0; y < screenHeight; y++)
        {
            float sy = yOffset + y * fontHeight;
            for (int x = 0; x < screenWidth; x++)
            {
                float sx = x * fontWidth;
                printChar(p, sx, sy);
                p++;
            }
        }

        /* yOffset pixels above row 0 aren't part of any cell, so they'd
         * otherwise stay whatever glClearColor() left them -- a fixed
         * black, regardless of theme. That's invisible against the Dark
         * theme's near-black desktop but shows up as a stray black line
         * across the top of the window against the Light theme's paler
         * one. Paint it using row 0's own per-column background instead,
         * so it reads as more of the same desktop rather than a seam. */
        if (yOffset > 0)
        {
            const cell_t* firstRow = &screen[0];
            glDisable(GL_BLEND);
            for (int x = 0; x < screenWidth; x++)
            {
                float sx = x * fontWidth;
                const GLfloat* bg = (const GLfloat*)&firstRow[x].bg;
                const GLfloat* fg = (const GLfloat*)&firstRow[x].fg;
                glColor3fv((firstRow[x].attr & DPY_REVERSE) ? fg : bg);
                glRectf(sx, 0, sx + fontWidth, yOffset);
            }
        }

        if (cursorShown)
        {
            int x = cursorx * fontWidth - 1;
            if (x < 0)
                x = 0;
            int y = yOffset + cursory * fontHeight;

            glColor3f(1.0f, 1.0f, 1.0f);
            glLogicOp(GL_XOR);
            glDisable(GL_BLEND);
            glDisable(GL_POLYGON_SMOOTH);
            glEnable(GL_COLOR_LOGIC_OP);
            glRecti(x, y, x + fontWidth, y + fontHeight);
            glLogicOp(GL_CLEAR);
            glDisable(GL_COLOR_LOGIC_OP);
        }
    }

    glfwSwapBuffers(window);
}

void dpy_setattr(int andmask, int ormask)
{
    currentAttr &= andmask;
    currentAttr |= ormask;
}

void dpy_setcolour(const colour_t* fg, const colour_t* bg)
{
    currentFg = *fg;
    currentBg = *bg;
}

void dpy_writechar(int x, int y, uni_t c)
{
    if (!screen)
        return;
    if ((x < 0) || (x >= screenWidth))
        return;
    if ((y < 0) || (y >= screenHeight))
        return;

    cell_t* p = &screen[x + y * screenWidth];
    p->c = c;
    p->attr = currentAttr;
    p->fg = currentFg;
    p->bg = currentBg;
}

static void clipBounds(int* x, int* y)
{
    if (*x < 0)
        *x = 0;
    if (*x >= screenWidth)
        *x = screenWidth - 1;
    if (*y < 0)
        *y = 0;
    if (*y >= screenHeight)
        *y = screenHeight - 1;
}

void dpy_cleararea(int x1, int y1, int x2, int y2)
{
    if (!screen)
        return;

    clipBounds(&x1, &y1);
    clipBounds(&x2, &y2);

    for (int y = y1; y <= y2; y++)
    {
        cell_t* p = &screen[y * screenWidth + x1];
        for (int x = x1; x <= x2; x++)
        {
            p->c = ' ';
            p->attr = currentAttr;
            p->fg = currentFg;
            p->bg = currentBg;
            p++;
        }
    }
}

void dpy_setcursor(int x, int y, bool shown)
{
    cursorx = x;
    cursory = y;
    cursorShown = shown;
}

uni_t dpy_getchar(double timeout)
{
    double endTime = glfwGetTime() + timeout;
    for (;;)
    {
        if (!keyboardQueue_empty())
            return keyboardQueue_pop();

        if (timeout == -1)
            glfwWaitEvents();
        else
        {
            double waitTime = endTime - glfwGetTime();
            if (waitTime < 0)
                return -KEY_TIMEOUT;
            glfwWaitEventsTimeout(waitTime);
        }
    }
}

/* Unlike dpy_getchar(0), this never calls into GLFW's event pump -- it only
 * reports what has already been queued by a *previous* call to
 * dpy_getchar(). That makes it safe for a caller to loop on this to drain
 * an already-queued run of repeated events (e.g. mouse-wheel scroll ticks
 * stacked up past the end of a document) without that loop also picking up
 * brand new events for as long as the input device keeps producing them --
 * which would starve the redraw loop for as long as the user kept
 * scrolling. */
bool dpy_charavailable(void)
{
    return !keyboardQueue_empty();
}

const char* dpy_getkeyname(uni_t k)
{
    static char buffer[32];
    int encoded = -k;
    if ((encoded & 0xff000000) == KEYM_ALTCHAR)
    {
        sprintf(buffer, "KEY_A%s%s%c",
            (encoded & VKM_SHIFT) ? "S" : "",
            (encoded & VKM_CTRL) ? "^" : "", encoded & 0xff);
        return buffer;
    }
    switch (-k)
    {
        case KEY_RESIZE:
            return "KEY_RESIZE";
        case KEY_TIMEOUT:
            return "KEY_TIMEOUT";
        case KEY_QUIT:
            return "KEY_QUIT";
        case KEY_SCROLLUP:
            return "KEY_SCROLLUP";
        case KEY_SCROLLDOWN:
            return "KEY_SCROLLDOWN";
        case KEY_MENU:
            return "KEY_MENU";
        case KEY_COMMAND:
            return "KEY_COMMAND";
    }

    int mods = -k;
    int key = (-k & 0xfff0ffff);

    if (mods & VKM_CTRLASCII)
    {
        sprintf(buffer, "KEY_%s^%c", (mods & VKM_SHIFT) ? "S" : "", key + 64);
        return buffer;
    }

    const char* t = NULL;
    switch (key)
    {
        // clang-format off
        case GLFW_KEY_ESCAPE:    t = "ESCAPE"; break;
        case GLFW_KEY_ENTER:     t = "RETURN"; break;
        case GLFW_KEY_TAB:       t = "TAB"; break;
        case GLFW_KEY_BACKSPACE: t = "BACKSPACE"; break;
        case GLFW_KEY_INSERT:    t = "INSERT"; break;
        case GLFW_KEY_DELETE:    t = "DELETE"; break;
        case GLFW_KEY_RIGHT:     t = "RIGHT"; break;
        case GLFW_KEY_LEFT:      t = "LEFT"; break;
        case GLFW_KEY_DOWN:      t = "DOWN"; break;
        case GLFW_KEY_UP:        t = "UP"; break;
        case GLFW_KEY_PAGE_UP:   t = "PGUP"; break;
        case GLFW_KEY_PAGE_DOWN: t = "PGDN"; break;
        case GLFW_KEY_HOME:      t = "HOME"; break;
        case GLFW_KEY_END:       t = "END"; break;
            // clang-format on
    }

    if (t)
    {
        sprintf(buffer,
            "KEY_%s%s%s",
            (mods & VKM_SHIFT) ? "S" : "",
            (mods & VKM_CTRL) ? "^" : "",
            t);
        return buffer;
    }

    if ((key >= GLFW_KEY_F1) && (key <= (GLFW_KEY_F25)))
    {
        sprintf(buffer,
            "KEY_%s%sF%d",
            (mods & VKM_SHIFT) ? "S" : "",
            (mods & VKM_CTRL) ? "^" : "",
            key - GLFW_KEY_F1 + 1);
        return buffer;
    }

    sprintf(buffer, "KEY_UNKNOWN_%d", -k);
    return buffer;
}

/* --- Clipboard backend --------------------------------------------------
 *
 * Uses GLFW's own clipboard API (glfwSetClipboardString/
 * glfwGetClipboardString), which works identically under both the X11 and
 * Wayland GLFW backends with no windowing-protocol code of our own. It's a
 * plain-string API only, so it carries the "text" channel; the styled
 * "wptext" channel (WordProcess's own internal paragraph-style format) has
 * no system-clipboard equivalent and is kept as a simple in-process static
 * instead -- same-instance copy/paste keeps full styling, cross-app/
 * cross-instance paste falls back to plain text (see GetClipboard() in
 * src/lua/fileio.lua, which already handles a nil wptext gracefully). */

static char* wptextData;
static size_t wptextLen;
static bool haveWptext;

void clipboard_backend_init(void) {}

void clipboard_backend_clear(void)
{
    glfwSetClipboardString(window, "");
    free(wptextData);
    wptextData = NULL;
    wptextLen = 0;
    haveWptext = false;
}

void clipboard_backend_set(
    const char* text, size_t textlen, const char* wptext, size_t wptextlen)
{
    if (text)
    {
        char* buf = (char*)malloc(textlen + 1);
        memcpy(buf, text, textlen);
        buf[textlen] = '\0';
        glfwSetClipboardString(window, buf);
        free(buf);
    }

    free(wptextData);
    wptextData = NULL;
    haveWptext = false;
    if (wptext)
    {
        wptextData = (char*)malloc(wptextlen);
        memcpy(wptextData, wptext, wptextlen);
        wptextLen = wptextlen;
        haveWptext = true;
    }
}

bool clipboard_backend_get_text(const char** data, size_t* len)
{
    const char* s = glfwGetClipboardString(window);
    if (!s)
        return false;
    *data = s;
    *len = strlen(s);
    return true;
}

bool clipboard_backend_get_wptext(const char** data, size_t* len)
{
    if (!haveWptext)
        return false;
    *data = wptextData;
    *len = wptextLen;
    return true;
}

// vim: sw=4 ts=4 et
