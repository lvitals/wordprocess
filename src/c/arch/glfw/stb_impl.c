/* stb is header-only; exactly one translation unit must define the
 * *_IMPLEMENTATION macros before including the (system-installed) headers
 * to get actual function bodies, not just declarations. */
#define STB_TRUETYPE_IMPLEMENTATION
#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"
#include "stb_truetype.h"
/* stb_ds's *_IMPLEMENTATION lives in src/c/stb_ds_impl.c instead (in the
 * shared "globals" library, not just the glfw one) since the ncurses
 * frontend also uses stb_ds (a couple of small dynamic arrays) and needs
 * the implementation linked in exactly once, shared by both frontends. */
