/* © 2020 David Given.
 * WordProcess is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#include "globals.h"
#include <sys/time.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

#ifdef WIN32
#include <windows.h>
#include <rpc.h>
#endif

static int pusherrno(lua_State* L)
{
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    lua_pushinteger(L, errno);
    return 3;
}

#define FILE_WRITER_MT "wordprocess.filewriter"
typedef struct FileWriter { FILE* fp; } FileWriter;

static FileWriter* checkwriter(lua_State* L)
{
    return (FileWriter*)luaL_checkudata(L, 1, FILE_WRITER_MT);
}

static int filewriter_write_cb(lua_State* L)
{
    FileWriter* writer = checkwriter(L);
    luaL_argcheck(L, writer->fp != NULL, 1, "writer is closed");
    for (int argument = 2; argument <= lua_gettop(L); argument++)
    {
        size_t length;
        const char* data = luaL_checklstring(L, argument, &length);
        while (length)
        {
            size_t written = fwrite(data, 1, length, writer->fp);
            if (!written) return pusherrno(L);
            data += written;
            length -= written;
        }
    }
    lua_pushboolean(L, true);
    return 1;
}

static int filewriter_close_cb(lua_State* L)
{
    FileWriter* writer = checkwriter(L);
    if (!writer->fp) { lua_pushboolean(L, true); return 1; }
    int result = fclose(writer->fp);
    writer->fp = NULL;
    if (result != 0) return pusherrno(L);
    lua_pushboolean(L, true);
    return 1;
}

static int openwriter_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);
    FILE* fp = fopen(filename, "wb");
    if (!fp) return pusherrno(L);
    FileWriter* writer = (FileWriter*)lua_newuserdata(L, sizeof(*writer));
    writer->fp = fp;
    luaL_getmetatable(L, FILE_WRITER_MT);
    lua_setmetatable(L, -2);
    return 1;
}

#ifdef WIN32
static void createUuid(char* buf, size_t buflen)
{
    UUID uuid;
    UuidCreate(&uuid);

    unsigned char* s;
    UuidToStringA(&uuid, &s);
    snprintf(buf, buflen, "%s", (char*)s);
    RpcStringFreeA(&s);
}
#endif

static int chdir_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

    if (chdir(filename) != 0)
        return pusherrno(L);

    lua_pushboolean(L, true);
    return 1;
}

static int mkdir_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

#ifdef WIN32
    if (mkdir(filename) != 0)
#else
    if (mkdir(filename, 0777) != 0)
#endif
        return pusherrno(L);

    lua_pushboolean(L, true);
    return 1;
}

/* Creates `filename` and any missing parent directories, tolerating
 * already-existing components (matching std::filesystem::create_directories
 * semantics, which this replaces). */
static int mkdir_component(char* path)
{
#ifdef WIN32
    if ((mkdir(path) != 0) && (errno != EEXIST))
#else
    if ((mkdir(path, 0777) != 0) && (errno != EEXIST))
#endif
        return -1;
    return 0;
}

static int mkdirs_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

    size_t len = strlen(filename);
    char* path = (char*)malloc(len + 1);
    memcpy(path, filename, len + 1);

    for (size_t i = 1; i < len; i++)
    {
        if ((path[i] == '/') || (path[i] == '\\'))
        {
            char saved = path[i];
            path[i] = '\0';
            if ((path[0] != '\0') && (mkdir_component(path) != 0))
            {
                free(path);
                return pusherrno(L);
            }
            path[i] = saved;
        }
    }

    if (mkdir_component(path) != 0)
    {
        free(path);
        return pusherrno(L);
    }

    free(path);
    lua_pushboolean(L, true);
    return 1;
}

static int getcwd_cb(lua_State* L)
{
    char* buf = getcwd(NULL, 0);
    if (!buf)
        return pusherrno(L);

    lua_pushstring(L, buf);
    free(buf);
    return 1;
}

static int remove_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);
    if (remove(filename) != 0)
        return pusherrno(L);

    lua_pushboolean(L, true);
    return 1;
}

static int rename_cb(lua_State* L)
{
    const char* oldfilename = luaL_checklstring(L, 1, NULL);
    const char* newfilename = luaL_checklstring(L, 2, NULL);
    if (rename(oldfilename, newfilename) != 0)
        return pusherrno(L);

    lua_pushboolean(L, true);
    return 1;
}

static int truncatefile_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);
    lua_Number requested = luaL_checknumber(L, 2);
    if (requested < 0)
    {
        errno = EINVAL;
        return pusherrno(L);
    }
#ifdef WIN32
    FILE* file = fopen(filename, "wb");
    if (!file)
        return pusherrno(L);
    int result = _chsize_s(_fileno(file), (__int64)requested);
    int saved = errno;
    fclose(file);
    errno = saved;
    if (result != 0)
        return pusherrno(L);
#else
    if (truncate(filename, (off_t)requested) != 0)
        return pusherrno(L);
#endif
    lua_pushboolean(L, true);
    return 1;
}

static int readdir_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

    DIR* dir = opendir(filename);
    if (!dir)
        return pusherrno(L);

    lua_newtable(L);

    int index = 1;
    lua_pushinteger(L, index++);
    lua_pushstring(L, ".");
    lua_settable(L, -3);
    lua_pushinteger(L, index++);
    lua_pushstring(L, "..");
    lua_settable(L, -3);

    struct dirent* de;
    while ((de = readdir(dir)) != NULL)
    {
        if ((strcmp(de->d_name, ".") == 0) || (strcmp(de->d_name, "..") == 0))
            continue;

        lua_pushinteger(L, index++);
        lua_pushstring(L, de->d_name);
        lua_settable(L, -3);
    }
    closedir(dir);

    return 1;
}

static int stat_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

    struct stat st;
    if (stat(filename, &st) != 0)
    {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        lua_pushinteger(L, errno);
        return 3;
    }

    lua_newtable(L);

    lua_pushstring(L, "size");
    lua_pushinteger(L, S_ISDIR(st.st_mode) ? 0 : (lua_Integer)st.st_size);
    lua_settable(L, -3);

    lua_pushstring(L, "mode");
    lua_pushstring(L, S_ISDIR(st.st_mode) ? "directory" : "file");
    lua_settable(L, -3);

    bool symlink = false;
#ifndef WIN32
    struct stat link_st;
    if (lstat(filename, &link_st) == 0)
        symlink = S_ISLNK(link_st.st_mode);
#endif
    lua_pushstring(L, "symlink");
    lua_pushboolean(L, symlink);
    lua_settable(L, -3);
    return 1;
}

static int access_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);
    int mode = forceinteger(L, 2);

#if defined WIN32
    wchar_t widepath[strlen(filename) + 1];
    MultiByteToWideChar(
        CP_UTF8, 0, filename, -1, widepath, strlen(filename) + 1);

    if (_waccess(widepath, mode) != 0)
        return pusherrno(L);
#else
    if (access(filename, mode) != 0)
        return pusherrno(L);
#endif

    lua_pushboolean(L, true);
    return 1;
}

static int getenv_cb(lua_State* L)
{
    const char* varname = luaL_checklstring(L, 1, NULL);
    const char* result = getenv(varname);

    if (result)
        lua_pushstring(L, result);
    else
        lua_pushnil(L);
    return 1;
}

static int printerr_cb(lua_State* L)
{
    int count = lua_gettop(L);
    for (int i = 1; i <= count; i++)
    {
        const char* message = luaL_checklstring(L, i, NULL);
        fprintf(stderr, "%s", message);
    }
    return 0;
}

static int printout_cb(lua_State* L)
{
    int count = lua_gettop(L);
    for (int i = 1; i <= count; i++)
    {
        const char* message = luaL_checklstring(L, i, NULL);
        fprintf(stdout, "%s", message);
    }
    return 0;
}

static int mkdtemp_cb(lua_State* L)
{
#ifdef WIN32
    char uuid[64];
    createUuid(uuid, sizeof(uuid));

    const char* base = getenv("TEMP");
    if (!base)
        base = getenv("TMP");
    if (!base)
        base = "C:\\Windows\\Temp";

    char path[1024];
    snprintf(path, sizeof(path), "%s/%s", base, uuid);
    if (mkdir(path) == 0)
    {
        lua_pushstring(L, path);
        return 1;
    }
    else
        return pusherrno(L);
#else
    const char* base = getenv("TMPDIR");
    if (!base)
        base = "/tmp";

    char path[1024];
    snprintf(path, sizeof(path), "%s/XXXXXX", base);
    if (mkdtemp(path))
    {
        lua_pushstring(L, path);
        return 1;
    }
    else
        return pusherrno(L);
#endif
}

static int readfile_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);

    FILE* fp = fopen(filename, "rb");
    if (!fp)
        goto error;

    luaL_Buffer buffer;
    luaL_buffinit(L, &buffer);

    for (;;)
    {
        char b[4096];
        size_t i = fread(b, 1, sizeof(b), fp);
        if (i == 0)
            break;

        luaL_addlstring(&buffer, b, i);
    }

    fclose(fp);
    luaL_pushresult(&buffer);
    return 1;

error:
    pusherrno(L);
    if (fp)
        fclose(fp);
    return 3;
}

static int writefile_cb(lua_State* L)
{
    const char* filename = luaL_checklstring(L, 1, NULL);
    size_t len;
    const char* data = luaL_checklstring(L, 2, &len);

    FILE* fp = fopen(filename, "wb");
    if (!fp)
        goto error;

    while (len != 0)
    {
        size_t i = fwrite(data, 1, len, fp);
        if (i == 0)
            goto error;

        len -= i;
        data += i;
    }
    fclose(fp);
    return 0;

error:
    pusherrno(L);
    if (fp)
        fclose(fp);
    return 3;
}

void filesystem_init(void)
{
    const static luaL_Reg funcs[] = {
        {"access",    access_cb   },
        {"chdir",     chdir_cb    },
        {"getcwd",    getcwd_cb   },
        {"getenv",    getenv_cb   },
        {"mkdir",     mkdir_cb    },
        {"mkdirs",    mkdirs_cb    },
        {"mkdtemp",   mkdtemp_cb  },
		{"openwriter", openwriter_cb},
        {"printerr",  printerr_cb },
        {"printout",  printout_cb },
        {"readdir",   readdir_cb  },
        {"readfile",  readfile_cb },
        {"remove",    remove_cb   },
        {"rename",    rename_cb   },
        {"stat",      stat_cb     },
        {"truncatefile", truncatefile_cb},
        {"writefile", writefile_cb},
        {NULL,        NULL        }
    };

    const static luaL_Constant consts[] = {
        {"ENOENT", ENOENT},
        {"EEXIST", EEXIST},
        {"EACCES", EACCES},
        {"EISDIR", EISDIR},
    };

    lua_getglobal(L, "wg");
    luaL_register(L, NULL, funcs);
    luaL_setconstants(L, consts, sizeof(consts) / sizeof(*consts));

    luaL_newmetatable(L, FILE_WRITER_MT);
    const static luaL_Reg writer_methods[] = {
        {"write", filewriter_write_cb},
        {"close", filewriter_close_cb},
        {"__gc", filewriter_close_cb},
        {NULL, NULL}
    };
    luaL_register(L, NULL, writer_methods);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

// vim: sw=4 ts=4 et
