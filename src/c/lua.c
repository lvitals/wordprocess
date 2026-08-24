/* © 2008 David Given.
 * WordProcess is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#include "globals.h"
#include <string.h>

lua_State* L;

/* Load a chunk of Lua source text (not bytecode), of known length, under a
 * given chunk name. Standard Lua compiles source text directly given an
 * explicit length; Luau requires going through its own compiler first,
 * which src/c/luau-em bridges via a NUL-terminated-string-only 3-arg
 * luaL_loadstring (marked by its LUA_VERSION_NUM==510) -- so for that path
 * only, make a temporary NUL-terminated copy first, since `s` (e.g. an
 * embedded script's raw bytes, see script_load_from_table) is not
 * guaranteed to be NUL-terminated at `s[len]`. */
static int wg_loadstring(lua_State* L, const char* s, size_t len, const char* name)
{
#if LUA_VERSION_NUM == 510
    char* tmp = (char*)malloc(len + 1);
    memcpy(tmp, s, len);
    tmp[len] = '\0';
    int status = luaL_loadstring(L, tmp, name);
    free(tmp);
    return status;
#else
    return luaL_loadbuffer(L, s, len, name ? name : s);
#endif
}

static int wg_dostring(lua_State* L, const char* s, size_t len, const char* name)
{
    int status = wg_loadstring(L, s, len, name);
    if (status == 0)
        status = lua_pcall(L, 0, LUA_MULTRET, 0);
    return status;
}

#if (LUA_VERSION_NUM >= 502) && (LUA_VERSION_NUM != 510) && !defined(luaL_register)
void luaL_register(lua_State* L, const char* libname, const luaL_Reg* l)
{
    if (libname)
    {
        lua_getglobal(L, libname);
        if (!lua_istable(L, -1))
        {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_setglobal(L, libname);
        }
    }

    for (; l->name; l++)
    {
        lua_pushcfunction(L, l->func);
        lua_setfield(L, -2, l->name);
    }
}
#endif

static unsigned bit32_getarg(lua_State* L, int i)
{
    return (unsigned)(long)lua_tointeger(L, i);
}

static int bit32_band_cb(lua_State* L)
{
    unsigned r = ~0u;
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
        r &= bit32_getarg(L, i);
    lua_pushinteger(L, (int)r);
    return 1;
}

static int bit32_bor_cb(lua_State* L)
{
    unsigned r = 0;
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
        r |= bit32_getarg(L, i);
    lua_pushinteger(L, (int)r);
    return 1;
}

static int bit32_bxor_cb(lua_State* L)
{
    unsigned r = 0;
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
        r ^= bit32_getarg(L, i);
    lua_pushinteger(L, (int)r);
    return 1;
}

static int bit32_btest_cb(lua_State* L)
{
    unsigned r = ~0u;
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
        r &= bit32_getarg(L, i);
    lua_pushboolean(L, r != 0);
    return 1;
}

static int bit32_bnot_cb(lua_State* L)
{
    lua_pushnumber(L, (lua_Number)(~bit32_getarg(L, 1)));
    return 1;
}

static int bit32_rshift_cb(lua_State* L)
{
    unsigned shift = bit32_getarg(L, 2);
    unsigned result = shift >= 32 ? 0 : bit32_getarg(L, 1) >> shift;
    lua_pushnumber(L, (lua_Number)result);
    return 1;
}

/* Lua 5.1 (and Luau) only have a global `unpack`; 5.2+ moved it to
 * `table.unpack` and dropped the global. This codebase uses both
 * spellings interchangeably, so make sure both exist regardless of
 * engine/version. */
static void unpack_compat_init(lua_State* L)
{
    lua_getglobal(L, "table");
    lua_getfield(L, -1, "unpack");
    if (lua_isnil(L, -1))
    {
        lua_pop(L, 1);
        lua_getglobal(L, "unpack");
        lua_setfield(L, -2, "unpack");
    }
    else
        lua_setglobal(L, "unpack");
    lua_pop(L, 1);
}

void bit32_init(lua_State* L)
{
    lua_getglobal(L, "bit32");
    bool exists = lua_istable(L, -1);
    lua_pop(L, 1);
    if (exists)
        return;

    static const luaL_Reg funcs[] = {
        {"band",  bit32_band_cb },
        {"bor",   bit32_bor_cb  },
        {"bxor",  bit32_bxor_cb },
        {"btest", bit32_btest_cb},
        {"bnot",  bit32_bnot_cb },
        {"rshift", bit32_rshift_cb},
        {NULL,    NULL          }
    };

    luaL_register(L, "bit32", funcs);
}

static int report(lua_State* L, int status)
{
    if (status && !lua_isnil(L, -1))
    {
        const char* msg = lua_tostring(L, -1);
        if (!msg)
            msg = "(error object is not a string)";
        screen_deinit();
        fprintf(stderr, "Lua error: %s\n", msg);
        lua_pop(L, 1);

        exit(1);
    }

    return status;
}

static int traceback(lua_State* L)
{
    lua_pushglobaltable(L);
    lua_getfield(L, -1, "debug");
    if (!lua_istable(L, -1))
    {
        lua_pop(L, 1);
        return 1;
    }

    lua_getfield(L, -1, "traceback");
    if (!lua_isfunction(L, -1))
    {
        lua_pop(L, 2);
        return 1;
    }

    lua_pushvalue(L, 1);   /* pass error message */
    lua_pushinteger(L, 2); /* skip this function and traceback */
    lua_call(L, 2, 1);     /* call debug.traceback */
    return 1;
}

static int docall(lua_State* L, int narg, int clear)
{
    int base = lua_gettop(L) - narg;
    lua_pushcfunction(L, traceback);
    lua_insert(L, base);

    int status = lua_pcall(L, narg, (clear ? 0 : LUA_MULTRET), base);

    lua_remove(L, base);

    if (status != 0)
        lua_gc(L, LUA_GCCOLLECT, 0);
    return status;
}

void script_deinit(void)
{
    lua_close(L);
}

static int loadstring_cb(lua_State* L)
{
    size_t len;
    const char* s = luaL_checklstring(L, 1, &len);
    const char* name = luaL_optlstring(L, 2, NULL, NULL);

    if (wg_loadstring(L, s, len, name) == 0)
        return 1;

    lua_pushnil(L);
    lua_insert(L, -2); /* put before error message */
    return 2;
}

static int exit_cb(lua_State* L)
{
    int e = forceinteger(L, 1);
    exit(e);
}

void script_init(void)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    bit32_init(L);
    unpack_compat_init(L);

    atexit(script_deinit);

    /* Set some global variables. */

    lua_pushstring(L, STRINGIFY(VERSION));
    lua_setglobal(L, "VERSION");

    lua_pushnumber(L, FILEFORMAT);
    lua_setglobal(L, "FILEFORMAT");

    lua_pushstring(L, STRINGIFY(ARCH));
    lua_setglobal(L, "ARCH");

    lua_pushstring(L, STRINGIFY(FRONTEND));
    lua_setglobal(L, "FRONTEND");

    lua_pushstring(L, STRINGIFY(DEFAULT_DICTIONARY_PATH));
    lua_setglobal(L, "DEFAULT_DICTIONARY_PATH");
    lua_pushstring(L, STRINGIFY(DICTIONARY_DIR));
    lua_setglobal(L, "DICTIONARY_DIR");

    lua_pushcfunction(L, loadstring_cb);
    lua_setglobal(L, "loadstring");

    lua_newtable(L);
    lua_setglobal(L, "wg");

    {
        static const luaL_Reg wg_funcs[] = {
            {"exit", exit_cb},
            {NULL,   NULL   }
        };
        luaL_register(L, "wg", wg_funcs);
    }

    lua_pushboolean(L,
#ifndef NDEBUG
        1
#else
        0
#endif
    );
    lua_setglobal(L, "DEBUG");
}

void script_load_from_table(const FileDescriptor* table)
{
    while (table->name)
    {
        int status = wg_dostring(L, table->data, table->size, table->name);
        if (status)
        {
            (void)report(L, status);
            break;
        }

        table++;
    }
}

void script_run(const char* argv[])
{
    lua_getglobal(L, "Main");

    /* Push the arguments onto the stack. */

    int argc = 0;
    for (;;)
    {
        const char* s = *argv++;
        if (!s)
            break;
        lua_pushstring(L, s);
        argc++;
    }

    /* Call the main program. */

    int status = docall(L, argc, 1);
    (void)report(L, status);
}

#if 0
/* Lua fallback functions, used for compatibility with 5.1 */

void luaL_setfuncs(lua_State* L, const luaL_Reg* l, int nup)
{
    luaL_checkstack(L, nup + 1, "too many upvalues");
    for (; l->name != NULL; l++)
    { /* fill the table with given functions */
        int i;
        lua_pushstring(L, l->name);

        for (i = 0; i < nup; i++) /* copy upvalues to the top */
            lua_pushvalue(L, -(nup + 1));

        lua_pushcfunction(L, l->func, nup); /* closure with those upvalues */
        lua_settable(L, -(nup + 3));
    }
    lua_pop(L, nup); /* remove upvalues */
}
#endif

extern void luaL_setconstants(lua_State* L, const luaL_Constant* array, int len)
{
    while (len--)
    {
        lua_pushnumber(L, array->value);
        lua_setfield(L, -2, array->name);
        array++;
    }
}
