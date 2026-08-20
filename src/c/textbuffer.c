/* Copyright 2026 Leandro V. Catarin.
 * WordProcess is licensed under the MIT open source license.
 *
 * An editable piece table. Existing large files are immutable mmap blocks;
 * insertions live in owned blocks and edits only rewrite the piece list.
 */

#include "globals.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#ifndef WIN32
#include <sys/mman.h>
#ifdef __linux__
#include <sys/sendfile.h>
#endif
#endif

#define TEXTBUFFER_MT "wordprocess.textbuffer"
#define MAX_LUA_SLICE (16u * 1024u * 1024u)

typedef struct Piece Piece;
typedef struct Change Change;
struct Piece
{
    const unsigned char* data;
    size_t length;
    bool owned;
    Piece* next;
};

struct Change
{
    size_t position;
    unsigned char* removed;
    size_t removed_length;
    unsigned char* added;
    size_t added_length;
    Change* next;
};

typedef struct
{
    const unsigned char* mapping;
    size_t mapped_size;
    size_t size;
    Piece* pieces;
    Change* undo;
    Change* redo;
    char* source_path;
    bool modified;
#ifndef WIN32
    int source_fd;
    dev_t source_device;
    ino_t source_inode;
    off_t source_size;
    time_t source_mtime;
#endif
#ifdef WIN32
    HANDLE file;
    HANDLE map_handle;
#endif
} TextBuffer;

static void changes_free(Change* change)
{
    while (change)
    {
        Change* next = change->next;
        free(change->removed);
        free(change->added);
        free(change);
        change = next;
    }
}

static TextBuffer* check_buffer(lua_State* L, int index)
{
    return (TextBuffer*)luaL_checkudata(L, index, TEXTBUFFER_MT);
}

static Piece* piece_new(const unsigned char* data, size_t length, bool owned)
{
    Piece* piece = (Piece*)calloc(1, sizeof(*piece));
    if (!piece)
        return NULL;
    piece->data = data;
    piece->length = length;
    piece->owned = owned;
    return piece;
}

static void piece_free(Piece* piece)
{
    if (piece->owned)
        free((void*)piece->data);
    free(piece);
}

static Piece* piece_copy_range(const Piece* source, size_t start, size_t length)
{
    if (!source->owned)
        return piece_new(source->data + start, length, false);
    unsigned char* data = (unsigned char*)malloc(length ? length : 1);
    if (!data)
        return NULL;
    if (length)
        memcpy(data, source->data + start, length);
    Piece* result = piece_new(data, length, true);
    if (!result)
        free(data);
    return result;
}

static void pieces_coalesce(TextBuffer* buffer)
{
    Piece* piece = buffer->pieces;
    while (piece && piece->next)
    {
        Piece* next = piece->next;
        bool merged = false;
        if (!piece->owned && !next->owned &&
            piece->data + piece->length == next->data)
        {
            piece->length += next->length;
            merged = true;
        }
        else if (piece->owned && next->owned &&
            piece->length <= SIZE_MAX - next->length)
        {
            unsigned char* data = (unsigned char*)realloc((void*)piece->data,
                piece->length + next->length);
            if (data)
            {
                memcpy(data + piece->length, next->data, next->length);
                piece->data = data;
                piece->length += next->length;
                merged = true;
            }
        }
        if (merged)
        {
            piece->next = next->next;
            piece_free(next);
        }
        else
            piece = next;
    }
}

static void close_buffer(TextBuffer* buffer)
{
    Piece* piece = buffer->pieces;
    while (piece)
    {
        Piece* next = piece->next;
        piece_free(piece);
        piece = next;
    }
    buffer->pieces = NULL;
    changes_free(buffer->undo);
    changes_free(buffer->redo);
    buffer->undo = buffer->redo = NULL;
    free(buffer->source_path);
    buffer->source_path = NULL;
#ifdef WIN32
    if (buffer->mapping)
        UnmapViewOfFile(buffer->mapping);
    if (buffer->map_handle)
        CloseHandle(buffer->map_handle);
    if (buffer->file && buffer->file != INVALID_HANDLE_VALUE)
        CloseHandle(buffer->file);
    buffer->map_handle = NULL;
    buffer->file = INVALID_HANDLE_VALUE;
#else
    if (buffer->mapping)
        munmap((void*)buffer->mapping, buffer->mapped_size);
    if (buffer->source_fd >= 0)
        close(buffer->source_fd);
    buffer->source_fd = -1;
#endif
    buffer->mapping = NULL;
    buffer->mapped_size = 0;
    buffer->size = 0;
}

static size_t check_offset(lua_State* L, int index, size_t limit)
{
    lua_Number value = luaL_checknumber(L, index);
    luaL_argcheck(L, value >= 0 && value <= (lua_Number)limit, index,
        "offset outside text buffer");
    return (size_t)value;
}

/* Find the piece containing pos; at EOF returns the final piece and its end. */
static Piece* locate(TextBuffer* buffer, size_t pos, Piece** previous,
    size_t* inner)
{
    Piece* prev = NULL;
    Piece* piece = buffer->pieces;
    while (piece && pos > piece->length)
    {
        pos -= piece->length;
        prev = piece;
        piece = piece->next;
    }
    if (previous)
        *previous = prev;
    if (inner)
        *inner = pos;
    return piece;
}

static int buffer_gc_cb(lua_State* L)
{
    close_buffer(check_buffer(L, 1));
    return 0;
}

static int buffer_close_cb(lua_State* L)
{
    close_buffer(check_buffer(L, 1));
    return 0;
}

static int buffer_size_cb(lua_State* L)
{
    lua_pushnumber(L, (lua_Number)check_buffer(L, 1)->size);
    return 1;
}

static int buffer_slice_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t start = check_offset(L, 2, buffer->size);
    lua_Number requested = luaL_checknumber(L, 3);
    luaL_argcheck(L, requested >= 0 && requested <= MAX_LUA_SLICE, 3,
        "slice exceeds the 16 MiB safety limit");
    size_t remaining = (size_t)requested;
    luaL_argcheck(L, remaining <= buffer->size - start, 3,
        "slice outside text buffer");
    luaL_Buffer output;
    luaL_buffinit(L, &output);
    size_t inner;
    Piece* piece = locate(buffer, start, NULL, &inner);
    while (remaining && piece)
    {
        size_t length = piece->length - inner;
        if (length > remaining)
            length = remaining;
        luaL_addlstring(&output, (const char*)piece->data + inner, length);
        remaining -= length;
        piece = piece->next;
        inner = 0;
    }
    luaL_pushresult(&output);
    return 1;
}

static bool buffer_insert_raw(TextBuffer* buffer, size_t pos,
    const unsigned char* input, size_t length)
{
    if (!length)
        return true;
    if (length > SIZE_MAX - buffer->size)
    {
        errno = EOVERFLOW;
        return false;
    }
    unsigned char* copy = (unsigned char*)malloc(length);
    if (!copy)
        return false;
    memcpy(copy, input, length);
    Piece* added = piece_new(copy, length, true);
    if (!added)
    {
        free(copy);
        return false;
    }

    Piece* previous;
    size_t inner;
    Piece* current = locate(buffer, pos, &previous, &inner);
    if (!current)
    {
        if (previous)
            previous->next = added;
        else
            buffer->pieces = added;
    }
    else if (inner == 0)
    {
        added->next = current;
        if (previous)
            previous->next = added;
        else
            buffer->pieces = added;
    }
    else if (inner == current->length)
    {
        added->next = current->next;
        current->next = added;
    }
    else
    {
        Piece* right = piece_copy_range(current, inner, current->length - inner);
        if (!right)
        {
            piece_free(added);
            return false;
        }
        if (current->owned)
        {
            unsigned char* left = (unsigned char*)malloc(inner);
            if (!left)
            {
                piece_free(right);
                piece_free(added);
                return false;
            }
            memcpy(left, current->data, inner);
            free((void*)current->data);
            current->data = left;
        }
        current->length = inner;
        right->next = current->next;
        added->next = right;
        current->next = added;
    }
    buffer->size += length;
    pieces_coalesce(buffer);
    return true;
}

static bool buffer_delete_raw(TextBuffer* buffer, size_t start, size_t length)
{
    if (!length)
        return true;

    /* Preserve the two boundary fragments, unlink everything intersecting the
     * deletion, then splice the fragments back. */
    Piece* previous;
    size_t inner;
    Piece* first = locate(buffer, start, &previous, &inner);
    size_t end_inner;
    Piece* end = locate(buffer, start + length, NULL, &end_inner);
    Piece* left = (first && inner) ? piece_copy_range(first, 0, inner) : NULL;
    Piece* right = (end && end_inner < end->length)
        ? piece_copy_range(end, end_inner, end->length - end_inner) : NULL;
    if ((first && inner && !left) ||
        (end && end_inner < end->length && !right))
    {
        piece_free(left);
        piece_free(right);
        return false;
    }
    Piece* after = end ? end->next : NULL;
    if (end && end_inner == 0)
        after = end;

    Piece* piece = first;
    while (piece && piece != after)
    {
        Piece* next = piece->next;
        piece_free(piece);
        piece = next;
    }
    Piece* head = left ? left : right;
    if (left)
        left->next = right ? right : after;
    if (right)
        right->next = after;
    if (!head)
        head = after;
    if (previous)
        previous->next = head;
    else
        buffer->pieces = head;
    buffer->size -= length;
    pieces_coalesce(buffer);
    return true;
}

static unsigned char* buffer_copy(TextBuffer* buffer, size_t start, size_t length)
{
    unsigned char* output = (unsigned char*)malloc(length ? length : 1);
    if (!output)
        return NULL;
    size_t inner;
    Piece* piece = locate(buffer, start, NULL, &inner);
    size_t copied = 0;
    while (copied < length && piece)
    {
        size_t amount = piece->length - inner;
        if (amount > length - copied)
            amount = length - copied;
        memcpy(output + copied, piece->data + inner, amount);
        copied += amount;
        piece = piece->next;
        inner = 0;
    }
    return output;
}

static Change* change_new(size_t position, const unsigned char* removed,
    size_t removed_length, const unsigned char* added, size_t added_length)
{
    Change* change = (Change*)calloc(1, sizeof(*change));
    if (!change)
        return NULL;
    change->position = position;
    change->removed_length = removed_length;
    change->added_length = added_length;
    if (removed_length)
    {
        change->removed = (unsigned char*)malloc(removed_length);
        if (!change->removed) goto error;
        memcpy(change->removed, removed, removed_length);
    }
    if (added_length)
    {
        change->added = (unsigned char*)malloc(added_length);
        if (!change->added) goto error;
        memcpy(change->added, added, added_length);
    }
    return change;
error:
    changes_free(change);
    return NULL;
}

static void push_change(Change** stack, Change* change)
{
    change->next = *stack;
    *stack = change;
}

static void trim_changes(Change** stack, size_t limit)
{
    Change* change = *stack;
    if (!change) return;
    for (size_t i = 1; i < limit && change->next; i++)
        change = change->next;
    if (change->next)
    {
        changes_free(change->next);
        change->next = NULL;
    }
}

static int buffer_insert_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t pos = check_offset(L, 2, buffer->size);
    size_t length;
    const unsigned char* input =
        (const unsigned char*)luaL_checklstring(L, 3, &length);
    if (!length) return 0;
    Change* change = change_new(pos, NULL, 0, input, length);
    if (!change || !buffer_insert_raw(buffer, pos, input, length))
    {
        changes_free(change);
        return luaL_error(L, "out of memory inserting into text buffer");
    }
    changes_free(buffer->redo);
    buffer->redo = NULL;
    push_change(&buffer->undo, change);
    trim_changes(&buffer->undo, 500);
    buffer->modified = true;
    return 0;
}

static int buffer_delete_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t start = check_offset(L, 2, buffer->size);
    size_t length = (size_t)luaL_checknumber(L, 3);
    luaL_argcheck(L, length <= buffer->size - start, 3,
        "deletion outside text buffer");
    if (!length) return 0;
    unsigned char* removed = buffer_copy(buffer, start, length);
    Change* change = removed ? change_new(start, removed, length, NULL, 0) : NULL;
    free(removed);
    if (!change || !buffer_delete_raw(buffer, start, length))
    {
        changes_free(change);
        return luaL_error(L, "out of memory deleting from text buffer");
    }
    changes_free(buffer->redo);
    buffer->redo = NULL;
    push_change(&buffer->undo, change);
    trim_changes(&buffer->undo, 500);
    buffer->modified = true;
    return 0;
}

static int buffer_find_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t start = check_offset(L, 2, buffer->size);
    int byte = (int)luaL_checkinteger(L, 3);
    size_t limit = lua_isnoneornil(L, 4) ? buffer->size
        : check_offset(L, 4, buffer->size);
    luaL_argcheck(L, byte >= 0 && byte <= 255, 3, "byte must be 0..255");
    luaL_argcheck(L, limit >= start, 4, "limit precedes start");
    size_t inner;
    Piece* piece = locate(buffer, start, NULL, &inner);
    size_t logical = start;
    while (piece && logical < limit)
    {
        size_t length = piece->length - inner;
        if (length > limit - logical)
            length = limit - logical;
        const unsigned char* found = memchr(piece->data + inner, byte, length);
        if (found)
        {
            lua_pushnumber(L, (lua_Number)(logical + found - (piece->data + inner)));
            return 1;
        }
        logical += length;
        piece = piece->next;
        inner = 0;
    }
    lua_pushnil(L);
    return 1;
}

static int buffer_findstring_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t pattern_length;
    const unsigned char* pattern =
        (const unsigned char*)luaL_checklstring(L, 2, &pattern_length);
    size_t start = check_offset(L, 3, buffer->size);
    if (!pattern_length)
    {
        lua_pushnumber(L, (lua_Number)start);
        return 1;
    }
    size_t* failure = (size_t*)calloc(pattern_length, sizeof(*failure));
    if (!failure)
        return luaL_error(L, "out of memory preparing text search");
    for (size_t i = 1, matched = 0; i < pattern_length; i++)
    {
        while (matched && pattern[i] != pattern[matched])
            matched = failure[matched - 1];
        if (pattern[i] == pattern[matched]) matched++;
        failure[i] = matched;
    }
    size_t inner;
    Piece* piece = locate(buffer, start, NULL, &inner);
    size_t logical = start;
    size_t matched = 0;
    while (piece)
    {
        for (size_t i = inner; i < piece->length; i++, logical++)
        {
            unsigned char byte = piece->data[i];
            while (matched && byte != pattern[matched])
                matched = failure[matched - 1];
            if (byte == pattern[matched]) matched++;
            if (matched == pattern_length)
            {
                free(failure);
                lua_pushnumber(L, (lua_Number)(logical + 1 - pattern_length));
                return 1;
            }
        }
        piece = piece->next;
        inner = 0;
    }
    free(failure);
    lua_pushnil(L);
    return 1;
}

static int buffer_rfind_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t start = check_offset(L, 2, buffer->size);
    int byte = (int)luaL_checkinteger(L, 3);
    size_t limit = check_offset(L, 4, buffer->size);
    luaL_argcheck(L, byte >= 0 && byte <= 255, 3, "byte must be 0..255");
    luaL_argcheck(L, limit >= start, 4, "limit precedes start");
    while (limit > start)
    {
        size_t inner;
        Piece* piece = locate(buffer, limit - 1, NULL, &inner);
        if (!piece)
            break;
        size_t piece_start = (limit - 1) - inner;
        size_t lower = start > piece_start ? start - piece_start : 0;
        size_t index = inner + 1;
        while (index > lower)
        {
            index--;
            if (piece->data[index] == (unsigned char)byte)
            {
                lua_pushnumber(L, (lua_Number)(piece_start + index));
                return 1;
            }
        }
        limit = piece_start;
    }
    lua_pushnil(L);
    return 1;
}

static bool apply_change(TextBuffer* buffer, const Change* change, bool forward)
{
    const unsigned char* remove_data = forward ? change->removed : change->added;
    size_t remove_length = forward ? change->removed_length : change->added_length;
    const unsigned char* add_data = forward ? change->added : change->removed;
    size_t add_length = forward ? change->added_length : change->removed_length;
    (void)remove_data;
    if (remove_length && !buffer_delete_raw(buffer, change->position, remove_length))
        return false;
    if (add_length && !buffer_insert_raw(buffer, change->position, add_data, add_length))
    {
        /* Best-effort rollback. The removed bytes are owned by the change. */
        if (remove_length)
            buffer_insert_raw(buffer, change->position, remove_data, remove_length);
        return false;
    }
    return true;
}

static int move_history(lua_State* L, bool forward)
{
    TextBuffer* buffer = check_buffer(L, 1);
    Change** source = forward ? &buffer->redo : &buffer->undo;
    Change** destination = forward ? &buffer->undo : &buffer->redo;
    Change* change = *source;
    if (!change)
    {
        lua_pushboolean(L, false);
        return 1;
    }
    if (!apply_change(buffer, change, forward))
        return luaL_error(L, "out of memory applying text-buffer history");
    *source = change->next;
    push_change(destination, change);
    buffer->modified = true;
    lua_pushboolean(L, true);
    lua_pushnumber(L, (lua_Number)(change->position +
        (forward ? change->added_length : change->removed_length)));
    return 2;
}

static int buffer_undo_cb(lua_State* L) { return move_history(L, false); }
static int buffer_redo_cb(lua_State* L) { return move_history(L, true); }

#ifndef WIN32
static bool write_all(int fd, const unsigned char* data, size_t length)
{
    while (length)
    {
        size_t chunk = length > 0x7ffff000u ? 0x7ffff000u : length;
        ssize_t written = write(fd, data, chunk);
        if (written < 0 && errno == EINTR)
            continue;
        if (written <= 0)
            return false;
        data += written;
        length -= (size_t)written;
    }
    return true;
}

static bool write_piece(int output, TextBuffer* buffer, const Piece* piece,
    size_t length)
{
#ifdef __linux__
    if (!piece->owned && buffer->source_fd >= 0 &&
        piece->data >= buffer->mapping &&
        piece->data + length <= buffer->mapping + buffer->mapped_size)
    {
        off_t offset = (off_t)(piece->data - buffer->mapping);
        size_t remaining = length;
        while (remaining)
        {
            size_t chunk = remaining > 0x7ffff000u ? 0x7ffff000u : remaining;
            ssize_t written = sendfile(output, buffer->source_fd, &offset, chunk);
            if (written < 0 && errno == EINTR)
                continue;
            if (written < 0 && (errno == EINVAL || errno == ENOSYS ||
                errno == EXDEV || errno == EOPNOTSUPP))
                break;
            if (written <= 0)
                return false;
            remaining -= (size_t)written;
        }
        if (!remaining)
            return true;
        return write_all(output, piece->data + length - remaining, remaining);
    }
#endif
    return write_all(output, piece->data, length);
}
#endif

static int buffer_save_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    const char* filename = luaL_checkstring(L, 2);
#ifndef WIN32
    if (!buffer->modified && buffer->source_path &&
        strcmp(buffer->source_path, filename) == 0)
    {
        lua_pushboolean(L, true);
        return 1;
    }
#endif
    size_t namelen = strlen(filename);
    char* temporary = (char*)malloc(namelen + 5);
    if (!temporary)
        return luaL_error(L, "out of memory creating save path");
    memcpy(temporary, filename, namelen);
    memcpy(temporary + namelen, ".new", 5);
#ifndef WIN32
    int output = open(temporary, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (output < 0)
#else
    FILE* output = fopen(temporary, "wb");
    if (!output)
#endif
    {
        free(temporary);
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
    bool ok = true;
    size_t remaining = buffer->size;
    for (Piece* piece = buffer->pieces; piece && ok; piece = piece->next)
    {
        size_t piece_length = piece->length < remaining ? piece->length : remaining;
#ifndef WIN32
        if (!write_piece(output, buffer, piece, piece_length)) ok = false;
#else
        size_t written = fwrite(piece->data, 1, piece_length, output);
        if (written != piece_length) ok = false;
#endif
        remaining -= piece_length;
    }
    if (remaining != 0)
    {
        errno = EIO;
        ok = false;
    }
#ifndef WIN32
    if (ok && fsync(output) != 0)
        ok = false;
    if (close(output) != 0)
        ok = false;
#else
    if (fflush(output) != 0)
        ok = false;
    if (fclose(output) != 0)
        ok = false;
#endif
    if (!ok)
    {
        int saved = errno;
        remove(temporary);
        free(temporary);
        errno = saved;
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
#ifdef WIN32
    remove(filename);
#endif
    if (rename(temporary, filename) != 0)
    {
        free(temporary);
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
    free(temporary);
    if (!buffer->source_path || strcmp(buffer->source_path, filename) != 0)
    {
        char* path = (char*)realloc(buffer->source_path, strlen(filename) + 1);
        if (path)
        {
            buffer->source_path = path;
            memcpy(buffer->source_path, filename, strlen(filename) + 1);
        }
    }
#ifndef WIN32
    struct stat st;
    if (stat(filename, &st) == 0)
    {
        buffer->source_device = st.st_dev;
        buffer->source_inode = st.st_ino;
        buffer->source_size = st.st_size;
        buffer->source_mtime = st.st_mtime;
    }
#endif
    buffer->modified = false;
    lua_pushboolean(L, true);
    return 1;
}

static int buffer_source_changed_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    bool changed = false;
#ifndef WIN32
    struct stat st;
    changed = !buffer->source_path || stat(buffer->source_path, &st) != 0 ||
        st.st_dev != buffer->source_device || st.st_ino != buffer->source_inode ||
        st.st_size != buffer->source_size || st.st_mtime != buffer->source_mtime;
#endif
    lua_pushboolean(L, changed);
    return 1;
}

static int buffer_source_safe_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    bool safe = true;
#ifndef WIN32
    struct stat st;
    safe = buffer->source_fd >= 0 && fstat(buffer->source_fd, &st) == 0 &&
        (uintmax_t)st.st_size >= buffer->mapped_size;
#endif
    lua_pushboolean(L, safe);
    return 1;
}

static int buffer_open_cb(lua_State* L)
{
    const char* filename = luaL_checkstring(L, 1);
    TextBuffer* buffer = (TextBuffer*)lua_newuserdata(L, sizeof(*buffer));
    memset(buffer, 0, sizeof(*buffer));
#ifndef WIN32
    buffer->source_fd = -1;
#endif
    buffer->source_path = (char*)malloc(strlen(filename) + 1);
    if (!buffer->source_path)
        goto error;
    memcpy(buffer->source_path, filename, strlen(filename) + 1);
#ifdef WIN32
    buffer->file = CreateFileA(filename, GENERIC_READ, FILE_SHARE_READ, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (buffer->file == INVALID_HANDLE_VALUE)
        goto error;
    LARGE_INTEGER size;
    if (!GetFileSizeEx(buffer->file, &size) || size.QuadPart <= 0 ||
        (uint64_t)size.QuadPart > SIZE_MAX)
        goto error;
    buffer->mapped_size = (size_t)size.QuadPart;
    buffer->map_handle = CreateFileMapping(buffer->file, NULL, PAGE_READONLY, 0, 0, NULL);
    if (!buffer->map_handle)
        goto error;
    buffer->mapping = (const unsigned char*)MapViewOfFile(buffer->map_handle,
        FILE_MAP_READ, 0, 0, 0);
    if (!buffer->mapping)
        goto error;
#else
    buffer->source_fd = open(filename, O_RDONLY);
    if (buffer->source_fd == -1)
        goto error;
    struct stat st;
    if (fstat(buffer->source_fd, &st) == -1 || !S_ISREG(st.st_mode) || st.st_size <= 0 ||
        (uintmax_t)st.st_size > SIZE_MAX)
    {
        errno = EINVAL;
        goto error;
    }
    buffer->mapped_size = (size_t)st.st_size;
    buffer->source_device = st.st_dev;
    buffer->source_inode = st.st_ino;
    buffer->source_size = st.st_size;
    buffer->source_mtime = st.st_mtime;
    buffer->mapping = (const unsigned char*)mmap(NULL, buffer->mapped_size,
        PROT_READ, MAP_SHARED, buffer->source_fd, 0);
    if (buffer->mapping == MAP_FAILED)
    {
        buffer->mapping = NULL;
        goto error;
    }
#endif
    buffer->size = buffer->mapped_size;
    buffer->pieces = piece_new(buffer->mapping, buffer->size, false);
    if (!buffer->pieces)
        goto error;
    luaL_getmetatable(L, TEXTBUFFER_MT);
    lua_setmetatable(L, -2);
    return 1;
error:
    close_buffer(buffer);
    lua_pop(L, 1);
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    lua_pushinteger(L, errno);
    return 3;
}

void textbuffer_init(void)
{
    static const luaL_Reg methods[] = {
        {"close", buffer_close_cb}, {"size", buffer_size_cb},
        {"slice", buffer_slice_cb}, {"find", buffer_find_cb},
        {"findstring", buffer_findstring_cb},
        {"rfind", buffer_rfind_cb},
        {"insert", buffer_insert_cb}, {"delete", buffer_delete_cb},
        {"save", buffer_save_cb},
        {"sourcechanged", buffer_source_changed_cb},
        {"sourcesafe", buffer_source_safe_cb},
        {"undo", buffer_undo_cb}, {"redo", buffer_redo_cb},
        {NULL, NULL},
    };
    luaL_newmetatable(L, TEXTBUFFER_MT);
    lua_pushstring(L, "__gc"); lua_pushcfunction(L, buffer_gc_cb); lua_settable(L, -3);
    lua_pushstring(L, "__index"); lua_pushvalue(L, -2); lua_settable(L, -3);
    luaL_setfuncs(L, methods, 0);
    lua_pop(L, 1);
    lua_getglobal(L, "wg");
    lua_pushcfunction(L, buffer_open_cb);
    lua_setfield(L, -2, "opentextbuffer");
    lua_pop(L, 1);
}
