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
#else
#include <io.h>
#endif

#define TEXTBUFFER_MT "wordprocess.textbuffer"
#define MAX_LUA_SLICE (16u * 1024u * 1024u)
#define MAX_HISTORY_BYTES (64u * 1024u * 1024u)

#ifdef WIN32
static int push_windows_error(lua_State* L, DWORD code)
{
    char* system_message = NULL;
    char message[1024];
    DWORD length = FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        (char*)&system_message, 0, NULL);
    while (length && (system_message[length - 1] == '\r' ||
        system_message[length - 1] == '\n'))
        system_message[--length] = '\0';
    if (length)
        snprintf(message, sizeof(message), "%s (Windows error %lu)",
            system_message, (unsigned long)code);
    else
        snprintf(message, sizeof(message), "Windows error %lu",
            (unsigned long)code);
    if (system_message) LocalFree(system_message);
    lua_pushnil(L);
    lua_pushstring(L, message);
    return 2;
}
#endif

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
    BY_HANDLE_FILE_INFORMATION source_info;
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

static void pieces_free(Piece* piece)
{
    while (piece)
    {
        Piece* next = piece->next;
        piece_free(piece);
        piece = next;
    }
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
    pieces_free(buffer->pieces);
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

static int buffer_piece_count_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    size_t count = 0;
    for (Piece* piece = buffer->pieces; piece; piece = piece->next) count++;
    lua_pushnumber(L, (lua_Number)count);
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

static Change* change_new_with_removed(size_t position,
    unsigned char* removed, size_t removed_length)
{
    Change* change = (Change*)calloc(1, sizeof(*change));
    if (!change)
        return NULL;
    change->position = position;
    change->removed = removed;
    change->removed_length = removed_length;
    return change;
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
	if (length > MAX_HISTORY_BYTES)
	{
		if (!buffer_delete_raw(buffer, start, length))
			return luaL_error(L, "out of memory deleting from text buffer");
		changes_free(buffer->undo);
		changes_free(buffer->redo);
		buffer->undo = buffer->redo = NULL;
		buffer->modified = true;
		lua_pushboolean(L, false);
		return 1;
	}
    unsigned char* removed = buffer_copy(buffer, start, length);
	Change* change = removed ? change_new_with_removed(start, removed, length) : NULL;
    if (!change || !buffer_delete_raw(buffer, start, length))
    {
		if (!change) free(removed);
        changes_free(change);
        return luaL_error(L, "out of memory deleting from text buffer");
    }
    changes_free(buffer->redo);
    buffer->redo = NULL;
    push_change(&buffer->undo, change);
    trim_changes(&buffer->undo, 500);
    buffer->modified = true;
	lua_pushboolean(L, true);
	return 1;
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
		/* locate() deliberately represents an exact boundary as the end of
		 * the left piece because insertion/deletion need that convention.
		 * rfind(), however, is locating an actual byte at limit-1, so that
		 * byte belongs to the right piece. Without this adjustment, an append
		 * at EOF makes the reverse newline search scan the entire mmap. */
		if (inner == piece->length && piece->next)
		{
			piece = piece->next;
			inner = 0;
		}
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

/* After every successful save, make the saved file the sole backing store.
 * Path, descriptor/handle, mapping and identity must always describe the same
 * object; otherwise truncating an older Save-As source could SIGBUS us. */
static bool rebase_after_save(TextBuffer* buffer, const char* filename)
{
    const unsigned char* new_mapping = NULL;
    size_t new_size = 0;
    Piece* new_piece = NULL;
#ifdef WIN32
    HANDLE new_file = CreateFileA(filename, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    HANDLE new_map = NULL;
    if (new_file == INVALID_HANDLE_VALUE)
        return false;
    LARGE_INTEGER size;
    if (!GetFileSizeEx(new_file, &size) || size.QuadPart < 0 ||
        (uint64_t)size.QuadPart > SIZE_MAX)
        goto error;
    new_size = (size_t)size.QuadPart;
    if (new_size)
    {
        new_map = CreateFileMapping(new_file, NULL, PAGE_READONLY, 0, 0, NULL);
        if (!new_map) goto error;
        new_mapping = (const unsigned char*)MapViewOfFile(new_map,
            FILE_MAP_READ, 0, 0, 0);
        if (!new_mapping) goto error;
    }
#else
    int new_fd = open(filename, O_RDONLY);
    struct stat st;
    if (new_fd < 0)
        return false;
    if (fstat(new_fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 ||
        (uintmax_t)st.st_size > SIZE_MAX)
        goto error;
    new_size = (size_t)st.st_size;
    if (new_size)
    {
        new_mapping = (const unsigned char*)mmap(NULL, new_size,
            PROT_READ, MAP_SHARED, new_fd, 0);
        if (new_mapping == MAP_FAILED)
        {
            new_mapping = NULL;
            goto error;
        }
    }
#endif
    new_piece = piece_new(new_mapping, new_size, false);
    if (!new_piece) goto error;
    char* new_path = (char*)malloc(strlen(filename) + 1);
    if (!new_path) goto error;
    memcpy(new_path, filename, strlen(filename) + 1);

    pieces_free(buffer->pieces);
#ifdef WIN32
    if (buffer->mapping) UnmapViewOfFile(buffer->mapping);
    if (buffer->map_handle) CloseHandle(buffer->map_handle);
    if (buffer->file && buffer->file != INVALID_HANDLE_VALUE) CloseHandle(buffer->file);
    buffer->file = new_file;
    buffer->map_handle = new_map;
    if (!GetFileInformationByHandle(new_file, &buffer->source_info))
        memset(&buffer->source_info, 0, sizeof(buffer->source_info));
#else
    if (buffer->mapping) munmap((void*)buffer->mapping, buffer->mapped_size);
    if (buffer->source_fd >= 0) close(buffer->source_fd);
    buffer->source_fd = new_fd;
    buffer->source_device = st.st_dev;
    buffer->source_inode = st.st_ino;
    buffer->source_size = st.st_size;
    buffer->source_mtime = st.st_mtime;
#endif
    free(buffer->source_path);
    buffer->source_path = new_path;
    buffer->mapping = new_mapping;
    buffer->mapped_size = new_size;
    buffer->size = new_size;
    buffer->pieces = new_piece;
    buffer->modified = false;
    return true;

error:
    piece_free(new_piece);
#ifdef WIN32
    if (new_mapping) UnmapViewOfFile(new_mapping);
    if (new_map) CloseHandle(new_map);
    if (new_file != INVALID_HANDLE_VALUE) CloseHandle(new_file);
#else
    if (new_mapping) munmap((void*)new_mapping, new_size);
    close(new_fd);
#endif
    return false;
}

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
    char* temporary = (char*)malloc(
#ifdef WIN32
        MAX_PATH
#else
        namelen + 16
#endif
    );
    if (!temporary)
        return luaL_error(L, "out of memory creating save path");
#ifndef WIN32
    const char* slash = strrchr(filename, '/');
    if (slash)
    {
        size_t directory_length = (size_t)(slash - filename) + 1;
        memcpy(temporary, filename, directory_length);
        temporary[directory_length] = '.';
        strcpy(temporary + directory_length + 1, slash + 1);
    }
    else
    {
        temporary[0] = '.';
        strcpy(temporary + 1, filename);
    }
    strcat(temporary, ".wp-XXXXXX");
    struct stat old_metadata;
    bool had_old_metadata = stat(filename, &old_metadata) == 0;
    int output = mkstemp(temporary);
    if (output >= 0 && had_old_metadata)
    {
        (void)fchown(output, old_metadata.st_uid, old_metadata.st_gid);
        (void)fchmod(output, old_metadata.st_mode & 07777);
    }
    if (output < 0)
#else
    if (namelen >= MAX_PATH)
    {
        free(temporary);
        lua_pushnil(L); lua_pushstring(L, "destination path is too long"); return 2;
    }
    char directory[MAX_PATH];
    memcpy(directory, filename, namelen + 1);
    char* slash = strrchr(directory, '\\');
    char* forward_slash = strrchr(directory, '/');
    if (!slash || (forward_slash && forward_slash > slash)) slash = forward_slash;
    if (slash) *slash = '\0'; else memcpy(directory, ".", 2);
    if (!GetTempFileNameA(directory[0] ? directory : "\\", "xwp", 0, temporary))
    {
        DWORD saved = GetLastError();
        free(temporary);
        return push_windows_error(L, saved);
    }
    FILE* output = fopen(temporary, "wb");
    if (!output)
#endif
    {
        free(temporary);
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
    bool ok = true;
#ifdef WIN32
    DWORD windows_error = ERROR_SUCCESS;
#endif
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
    if (ok && !FlushFileBuffers((HANDLE)_get_osfhandle(_fileno(output))))
    {
        windows_error = GetLastError();
        ok = false;
    }
    if (fclose(output) != 0)
        ok = false;
#endif
    if (!ok)
    {
        int saved = errno;
        remove(temporary);
        free(temporary);
#ifdef WIN32
        if (windows_error != ERROR_SUCCESS)
            return push_windows_error(L, windows_error);
#endif
        errno = saved;
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
#ifdef WIN32
    DWORD destination_attributes = GetFileAttributesA(filename);
    bool replaced = destination_attributes != INVALID_FILE_ATTRIBUTES
        ? ReplaceFileA(filename, temporary, NULL, REPLACEFILE_WRITE_THROUGH,
            NULL, NULL) != 0
        : MoveFileExA(temporary, filename,
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
    if (!replaced)
#else
    if (rename(temporary, filename) != 0)
#endif
    {
#ifdef WIN32
        DWORD saved = GetLastError();
        free(temporary);
        return push_windows_error(L, saved);
#else
        free(temporary);
        lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
#endif
    }
    free(temporary);
#ifndef WIN32
    char* directory = (char*)malloc(namelen + 1);
    if (directory)
    {
        memcpy(directory, filename, namelen + 1);
        char* slash = strrchr(directory, '/');
        if (slash) *slash = '\0'; else memcpy(directory, ".", 2);
#ifdef O_DIRECTORY
        int directory_fd = open(directory[0] ? directory : "/",
            O_RDONLY | O_DIRECTORY);
#else
        int directory_fd = open(directory[0] ? directory : "/", O_RDONLY);
#endif
        if (directory_fd >= 0)
        {
            (void)fsync(directory_fd);
            close(directory_fd);
        }
        free(directory);
    }
#endif
    if (!rebase_after_save(buffer, filename))
    {
#ifdef WIN32
        DWORD saved = GetLastError();
        if (saved != ERROR_SUCCESS)
            return push_windows_error(L, saved);
#endif
        lua_pushnil(L);
        lua_pushstring(L, "file was saved but could not be remapped safely");
        return 2;
    }
    lua_pushboolean(L, true);
    return 1;
}

static int buffer_source_changed_cb(lua_State* L)
{
    TextBuffer* buffer = check_buffer(L, 1);
    bool changed = false;
#ifdef WIN32
    HANDLE path_file = buffer->source_path ? CreateFileA(buffer->source_path,
        GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL) : INVALID_HANDLE_VALUE;
    BY_HANDLE_FILE_INFORMATION path;
    changed = path_file == INVALID_HANDLE_VALUE ||
        !GetFileInformationByHandle(path_file, &path) ||
        buffer->source_info.dwVolumeSerialNumber != path.dwVolumeSerialNumber ||
        buffer->source_info.nFileIndexHigh != path.nFileIndexHigh ||
        buffer->source_info.nFileIndexLow != path.nFileIndexLow ||
        buffer->source_info.nFileSizeHigh != path.nFileSizeHigh ||
        buffer->source_info.nFileSizeLow != path.nFileSizeLow ||
        CompareFileTime(&buffer->source_info.ftLastWriteTime,
            &path.ftLastWriteTime) != 0;
    if (path_file != INVALID_HANDLE_VALUE) CloseHandle(path_file);
#else
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
#ifdef WIN32
    LARGE_INTEGER size;
    safe = buffer->file && buffer->file != INVALID_HANDLE_VALUE &&
        GetFileSizeEx(buffer->file, &size) && size.QuadPart >= 0 &&
        (uint64_t)size.QuadPart >= buffer->mapped_size;
#else
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
    buffer->file = CreateFileA(filename, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
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
    if (!GetFileInformationByHandle(buffer->file, &buffer->source_info))
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
#ifdef WIN32
    DWORD saved_error = GetLastError();
#else
    int saved_error = errno;
#endif
    close_buffer(buffer);
    lua_pop(L, 1);
#ifdef WIN32
    return push_windows_error(L, saved_error);
#else
    errno = saved_error;
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    lua_pushinteger(L, errno);
    return 3;
#endif
}

void textbuffer_init(void)
{
    static const luaL_Reg methods[] = {
        {"close", buffer_close_cb}, {"size", buffer_size_cb},
        {"piececount", buffer_piece_count_cb},
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
