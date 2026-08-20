/* stb_ds is header-only; exactly one translation unit must define
 * STB_DS_IMPLEMENTATION before including it, to get actual function
 * bodies rather than just declarations. This is a Meson-only file (`ab`
 * gets the same implementation from third_party/libstb/stb.c, which
 * already bundles it alongside stb_truetype/stb_rect_pack) -- shared by
 * both frontends here since the ncurses frontend uses stb_ds too (see
 * src/c/arch/ncurses/dpy.cc's colourPairs), not just the glfw one. */
#define STB_DS_IMPLEMENTATION
#include "stb_ds.h"
