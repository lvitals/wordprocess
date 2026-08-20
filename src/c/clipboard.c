/* © 2022 David Given.
 * WordProcess is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#include "globals.h"

/* Generic Lua glue: platform-specific storage/system-clipboard access lives
 * in clipboard_backend_* (implemented once per frontend, in
 * src/c/arch/ncurses/dpy.cc for the terminal build and
 * src/c/arch/glfw/main.cc for the GUI build via GLFW's own clipboard API). */

static int clipboard_clear_cb(lua_State* L)
{
    clipboard_backend_clear();
    return 0;
}

static int clipboard_get_cb(lua_State* L)
{
    const char* data;
    size_t len;

    if (clipboard_backend_get_text(&data, &len))
        lua_pushlstring(L, data, len);
    else
        lua_pushnil(L);

    if (clipboard_backend_get_wptext(&data, &len))
        lua_pushlstring(L, data, len);
    else
        lua_pushnil(L);

    return 2;
}

static int clipboard_set_cb(lua_State* L)
{
    size_t textlen = 0;
    size_t wptextlen = 0;
    const char* text = lua_tolstring(L, 1, &textlen);
    const char* wptext = lua_tolstring(L, 2, &wptextlen);

    clipboard_backend_set(text, textlen, wptext, wptextlen);
    return 0;
}

void clipboard_init()
{
    clipboard_backend_init();

    const static luaL_Reg funcs[] = {
        {"clipboard_clear", clipboard_clear_cb},
        {"clipboard_get",   clipboard_get_cb  },
        {"clipboard_set",   clipboard_set_cb  },
        {NULL,              NULL              }
    };

    luaL_register(L, "wg", funcs);
}
