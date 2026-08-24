/* © 2008 David Given.
 * WordProcess is licensed under the MIT open source license. See the COPYING
 * file in this distribution for the full text.
 */

#include "globals.h"
#include <sys/time.h>
#include <iconv.h>
#include <string.h>

int getu8bytes(char c)
{
    uint8_t cc = c;
    if (cc < 0x80)
        return 1;
    else if (cc < 0xc0)
        return 0;
    else if (cc < 0xe0)
        return 2;
    else if (cc < 0xf0)
        return 3;
    else if (cc < 0xf8)
        return 4;
    else if (cc < 0xfc)
        return 5;
    return 6;
}

uni_t readu8(const char** srcp)
{
    const uint8_t* src = (const uint8_t*)*srcp;

    uni_t c = *src++;
    if (c < 0x80)
    {
        /* Do nothing! */
        goto zero;
    }
    else if (c < 0xc0)
    {
        /* Invalid character */
        c = -1;
        goto zero;
    }
    else if (c < 0xe0)
    {
        /* One trailing byte */
        c &= 0x1f;
        goto one;
    }
    else if (c < 0xf0)
    {
        /* Two trailing bytes */
        c &= 0x0f;
        goto two;
    }
    else if (c < 0xf8)
    {
        /* Three trailing bytes */
        c &= 0x07;
        goto three;
    }
    else if (c < 0xfc)
    {
        /* Four trailing bytes */
        c &= 0x03;
        goto four;
    }
    else
    {
        /* Five trailing bytes */
        c &= 0x01;
        goto five;
    }

    uint8_t d;
five:
    d = *src;
    src += (d != 0);
    c <<= 6;
    c += d & 0x3f;
four:
    d = *src;
    src += (d != 0);
    c <<= 6;
    c += d & 0x3f;
three:
    d = *src;
    src += (d != 0);
    c <<= 6;
    c += d & 0x3f;
two:
    d = *src;
    src += (d != 0);
    c <<= 6;
    c += d & 0x3f;
one:
    d = *src;
    src += (d != 0);
    c <<= 6;
    c += d & 0x3f;
zero:
    *srcp = (const char*)src;
    return c;
}

void writeu8(char** destp, uni_t ch)
{
    char* dest = *destp;

    if (ch < 0)
        assert(false);
    else if (ch < 0x80)
    {
        *dest++ = (char)ch;
    }
    else if (ch < 0x800)
    {
        *dest++ = (ch >> 6) | 0xC0;
        *dest++ = (ch & 0x3F) | 0x80;
    }
    else if (ch < 0x10000)
    {
        *dest++ = (ch >> 12) | 0xE0;
        *dest++ = ((ch >> 6) & 0x3F) | 0x80;
        *dest++ = (ch & 0x3F) | 0x80;
    }
    else if (ch < 0x200000)
    {
        *dest++ = (ch >> 18) | 0xF0;
        *dest++ = ((ch >> 12) & 0x3F) | 0x80;
        *dest++ = ((ch >> 6) & 0x3F) | 0x80;
        *dest++ = (ch & 0x3F) | 0x80;
    }
    else if (ch < 0x4000000)
    {
        *dest++ = (ch >> 24) | 0xF8;
        *dest++ = ((ch >> 18) & 0x3F) | 0x80;
        *dest++ = ((ch >> 12) & 0x3F) | 0x80;
        *dest++ = ((ch >> 6) & 0x3F) | 0x80;
        *dest++ = (ch & 0x3F) | 0x80;
    }
    else if (ch <= 0x7fffffff)
    {
        *dest++ = (ch >> 30) | 0xFC;
        *dest++ = ((ch >> 24) & 0x3F) | 0x80;
        *dest++ = ((ch >> 18) & 0x3F) | 0x80;
        *dest++ = ((ch >> 12) & 0x3F) | 0x80;
        *dest++ = ((ch >> 6) & 0x3F) | 0x80;
        *dest++ = (ch & 0x3F) | 0x80;
    }

    *destp = dest;
}

static int readu8_cb(lua_State* L)
{
    const char* s = luaL_checkstring(L, 1);
    int offset = forceinteger(L, 2);
    uni_t c;

    if (offset > 0)
        offset--;
    const char* p = s + offset;
    c = readu8(&p);

    lua_pushnumber(L, c);
    lua_pushinteger(L, (p - s) + 1);
    return 2;
}

static int writeu8_cb(lua_State* L)
{
    uni_t c = forceinteger(L, 1);
    static char buffer[8];
    char* s = buffer;

    writeu8(&s, c);
    lua_pushlstring(L, buffer, s - buffer);
    return 1;
}

static int transcode_cb(lua_State* L)
{
    size_t inputbuffersize;
    const char* inputbuffer = luaL_checklstring(L, 1, &inputbuffersize);

    size_t outputbuffersize = inputbuffersize * 2 + 32;
    char* outputbuffer = (char*)malloc(outputbuffersize); /* should fit everything */

    const char* in = (char*)inputbuffer;
    const char* inend = inputbuffer + inputbuffersize;

    char* out = outputbuffer;

    while (in < inend)
    {
        int c = readu8(&in);
        writeu8(&out, c);
    }

    lua_pushlstring(L, outputbuffer, out - outputbuffer);
    free(outputbuffer);
    return 1;
}

static int transcodefrom_cb(lua_State* L)
{
    size_t input_size;
    const char* input = luaL_checklstring(L, 1, &input_size);
    const char* encoding = luaL_checkstring(L, 2);
    iconv_t converter = iconv_open("UTF-8", encoding);
    if (converter == (iconv_t)-1)
        return luaL_error(L, "unsupported source encoding '%s'", encoding);

    size_t output_capacity = input_size * 4 + 1;
    char* output = (char*)malloc(output_capacity);
    char* output_position = output;
    size_t output_remaining = output_capacity;
    char* input_position = (char*)input;
    size_t input_remaining = input_size;
    if (iconv(converter, &input_position, &input_remaining,
            &output_position, &output_remaining) == (size_t)-1)
    {
        int saved_errno = errno;
        iconv_close(converter);
        free(output);
        return luaL_error(L, "cannot transcode from %s: %s",
            encoding, strerror(saved_errno));
    }
    iconv_close(converter);
    lua_pushlstring(L, output, output_position - output);
    free(output);
    return 1;
}

static int time_cb(lua_State* L)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);

    double t = (double)tv.tv_sec + (double)tv.tv_usec / 1000000.0;
    lua_pushnumber(L, t);

    return 1;
}

static int escape_cb(lua_State* L)
{
    size_t inputbuffersize;
    const char* inputbuffer = luaL_checklstring(L, 1, &inputbuffersize);

    const size_t outputbuffersize = inputbuffersize * 2; /* big enough to fit */
    char* outputbuffer = (char*)malloc(outputbuffersize);

    const char* in = (char*)inputbuffer;
    const char* inend = inputbuffer + inputbuffersize;

    char* out = outputbuffer;

    while (in < inend)
    {
        int c = readu8(&in);
        switch (c)
        {
            case '\n':
                writeu8(&out, '\\');
                writeu8(&out, 'n');
                break;

            case '\r':
                writeu8(&out, '\\');
                writeu8(&out, 'r');
                break;

            case '"':
            case '\\':
                writeu8(&out, '\\');
                /* fall through */
            default:
                writeu8(&out, c);
        }
    }

    lua_pushlstring(L, outputbuffer, out - outputbuffer);
    free(outputbuffer);
    return 1;
}

static int unescape_cb(lua_State* L)
{
    size_t inputbuffersize;
    const char* inputbuffer = luaL_checklstring(L, 1, &inputbuffersize);

    const size_t outputbuffersize = inputbuffersize; /* big enough to fit */
    char* outputbuffer = (char*)malloc(outputbuffersize);

    const char* in = (char*)inputbuffer;
    const char* inend = inputbuffer + inputbuffersize;

    char* out = outputbuffer;

    while (in < inend)
    {
        int c = readu8(&in);
        switch (c)
        {
            case '\\':
                c = readu8(&in);
                switch (c)
                {
                    case 'n':
                        writeu8(&out, '\n');
                        break;

                    case 'r':
                        writeu8(&out, '\r');
                        break;

                    default:
                        writeu8(&out, c);
                }
                break;

            default:
                writeu8(&out, c);
        }
    }

    lua_pushlstring(L, outputbuffer, out - outputbuffer);
    free(outputbuffer);
    return 1;
}

void utils_init(void)
{
    const static luaL_Reg funcs[] = {
        {"readu8",    readu8_cb   },
        {"writeu8",   writeu8_cb  },
        {"transcode", transcode_cb},
        {"transcodefrom", transcodefrom_cb},
        {"time",      time_cb     },
        {"escape",    escape_cb   },
        {"unescape",  unescape_cb },
        {NULL,        NULL        }
    };

    luaL_register(L, "wg", funcs);
}
