/* © 2008 David Given.
 * WordProcess is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#ifndef GLOBALS_H
#define GLOBALS_H

#if !defined _WIN32
#if !defined _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif

#if !defined _XOPEN_SOURCE_EXTENDED
#define _XOPEN_SOURCE_EXTENDED
#endif

#if !defined _GNU_SOURCE
#define _GNU_SOURCE
#endif
#endif

#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <errno.h>
#include <wctype.h>

/* --- Platform detection ------------------------------------------------ */

#if defined(__APPLE__) && defined(__MACH__)
#define OSX
#define EMULATED_WCWIDTH
#endif

#if defined _WIN32
#undef WIN32
#define WIN32
#define EMULATED_WCWIDTH
#endif

/* --- Emulation issues -------------------------------------------------- */

typedef int uni_t;

#if defined EMULATED_WCWIDTH
extern int emu_wcwidth(uni_t c);
#else
#include <wchar.h>
#define emu_wcwidth(c) wcwidth(c)
#endif

extern int main(int argc, char* argv[]);

/* --- Lua --------------------------------------------------------------- */

/* Stock PUC-Rio Lua's headers (unlike Luau's) aren't self-wrapped in
 * `extern "C"`, so a straight #include here would get its declarations
 * C++-mangled, causing link failures against liblua.so (which exports
 * plain C symbols). WORDPROCESS_STOCK_LUA is defined by the Meson build
 * only, since Luau's own headers/library are consistently compiled (and
 * so linked) as C++ throughout and must NOT be wrapped here. */
#if defined(__cplusplus) && defined(WORDPROCESS_STOCK_LUA)
extern "C" {
#endif
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
#if defined(__cplusplus) && defined(WORDPROCESS_STOCK_LUA)
}
#endif

#if defined WINSHIM
#include "winshim.h"
#endif

extern lua_State* L;

typedef struct
{
    const char* name;
    int value;
} luaL_Constant;

extern void luaL_setconstants(
    lua_State* L, const luaL_Constant* array, int len);

typedef struct
{
    const char* data;
    size_t size;
    const char* name;
} FileDescriptor;

extern void script_init(void);
extern void script_load(const char* filename);
extern void script_load_from_table(const FileDescriptor* table);
extern void script_run(const char* argv[]);
extern void textbuffer_init(void);

#if !defined LUA_VERSION_NUM || LUA_VERSION_NUM == 501
extern void luaL_setfuncs(lua_State* L, const luaL_Reg* l, int nup);
#define lua_pushglobaltable(L) lua_pushvalue(L, LUA_GLOBALSINDEX)
#endif

/* Lua 5.2+ dropped luaL_register from the core API; some distros'
 * lauxlib.h restores it as a macro when LUA_COMPAT_MODULE is defined, but
 * that's not something this build controls or can rely on portably (it
 * isn't set by these system packages' pkg-config flags) -- so reimplement
 * it ourselves whenever it isn't already available (as a real function on
 * 5.1/Luau, or as that compat macro), so every existing luaL_register()
 * call site keeps working unmodified regardless of engine/version. */
#if (LUA_VERSION_NUM >= 502) && (LUA_VERSION_NUM != 510) && !defined(luaL_register)
extern void luaL_register(lua_State* L, const char* libname, const luaL_Reg* l);
#endif

extern void bit32_init(lua_State* L);

#define forceinteger(L, offset) (int)lua_tonumber(L, offset)
#define forcedouble(L, offset) (double)lua_tonumber(L, offset)

/* --- Screen management ------------------------------------------------- */

extern void screen_init(const char* argv[]);
extern void screen_deinit(void);
extern void dpy_writeunichar(int x, int y, uni_t c);
extern void decode_mouse_event(uni_t key, int* x, int* y, bool* p);
extern uni_t encode_mouse_event(int x, int y, bool p);

/* --- Word management --------------------------------------------------- */

extern void word_init(void);

/* --- Zipfile management ------------------------------------------------ */

extern void zip_init(void);

/* --- CommonMark -------------------------------------------------------- */

extern void cmark_init(void);

/* --- General utilities ------------------------------------------------- */

extern int getu8bytes(char c);
extern uni_t readu8(const char** ptr);
extern void writeu8(char** ptr, uni_t value);

extern void utils_init(void);
extern void filesystem_init(void);
extern void clipboard_init(void);

#define STRINGIFY1(x) #x
#define STRINGIFY(x) STRINGIFY1(x)

/* --- Display layer ----------------------------------------------------- */

enum
{
    /* These four are also style control codes. */
    DPY_ITALIC = (1 << 0),
    DPY_UNDERLINE = (1 << 1),
    DPY_REVERSE = (1 << 2),
    DPY_BOLD = (1 << 3),

    /* These cannot appear in text. */
    DPY_BRIGHT = (1 << 4),
    DPY_DIM = (1 << 5),
};

enum
{
    /* uni_t special values for representing mouse events. */

    KEYM_MOUSE = 0x7f << 24,
    KEY_MOUSEDOWN = 1 << 24,
    KEY_MOUSEUP = 2 << 24,
    KEY_SCROLLUP = 3 << 24,
    KEY_SCROLLDOWN = 4 << 24,
    KEY_MENU = 5 << 24,
    KEY_RESIZE = 6 << 24,
    KEY_TIMEOUT = 7 << 24,
    KEY_QUIT = 8 << 24,
    /* Alt-; opens the compact-keyboard command layer. */
    KEY_COMMAND = 9 << 24,
    KEYM_ALTCHAR = 10 << 24,
};

typedef struct
{
    float r, g, b;
} colour_t;

extern void dpy_init(const char* argv[]);
extern void dpy_start(void);
extern void dpy_shutdown(void);

extern void dpy_setattr(int andmask, int ormask);
extern void dpy_setcolour(const colour_t* fg, const colour_t* bg);
extern void dpy_writechar(int x, int y, uni_t c);
extern void dpy_setcursor(int x, int y, bool shown);
extern void dpy_clearscreen(void);
extern void dpy_sync(void);
extern void dpy_cleararea(int x1, int y1, int x2, int y2);
extern void dpy_getscreensize(int* x, int* y);
extern uni_t dpy_getchar(double timeout);
extern const char* dpy_getkeyname(uni_t key);

extern bool enable_unicode;

/* --- Clipboard backend (implemented once per frontend arch dir) -------- */

extern void clipboard_backend_init(void);
extern void clipboard_backend_clear(void);
extern void clipboard_backend_set(
    const char* text, size_t textlen, const char* wptext, size_t wptextlen);
extern bool clipboard_backend_get_text(const char** data, size_t* len);
extern bool clipboard_backend_get_wptext(const char** data, size_t* len);

#endif
