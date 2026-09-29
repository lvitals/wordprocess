AC_PREREQ([2.69])
AC_INIT([WordProcess], [1.0], [], [wordprocess])
AC_CONFIG_SRCDIR([src/c/main.c])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([1.14 foreign subdir-objects parallel-tests])

AC_PROG_CC
AC_PROG_RANLIB
PKG_PROG_PKG_CONFIG

AC_ARG_ENABLE([xwp],
  [AS_HELP_STRING([--disable-xwp], [do not build the GLFW/OpenGL frontend])],
  [], [enable_xwp=yes])
AM_CONDITIONAL([BUILD_XWP], [test "x$enable_xwp" = xyes])

AC_ARG_ENABLE([update-desktop-caches],
  [AS_HELP_STRING([--disable-update-desktop-caches],
    [do not refresh desktop, icon, and MIME caches during installation])],
  [], [enable_update_desktop_caches=yes])
AM_CONDITIONAL([UPDATE_DESKTOP_CACHES],
  [test "x$enable_update_desktop_caches" = xyes])

AC_ARG_WITH([app-version],
  [AS_HELP_STRING([--with-app-version=VERSION],
    [version displayed by WordProcess @<:@default=package version@:>@])],
  [app_version=$withval], [app_version=$PACKAGE_VERSION])
AC_SUBST([APP_VERSION], [$app_version])

AC_ARG_WITH([lua-version],
  [AS_HELP_STRING([--with-lua-version=VERSION],
    [Lua ABI to use (auto, 5.1, 5.2, 5.3, 5.4, or 5.5) @<:@default=auto@:>@])],
  [lua_version=$withval], [lua_version=auto])
AS_CASE([$lua_version],
  [auto], [lua_packages="lua5.5 lua5.4 lua5.3 lua5.2 lua5.1"],
  [5.1|5.2|5.3|5.4|5.5], [lua_packages="lua$lua_version"],
  [AC_MSG_ERROR([invalid Lua version '$lua_version'])])
for lua_package in $lua_packages; do
  AS_IF([$PKG_CONFIG --exists "$lua_package"], [break])
done
AS_IF([! $PKG_CONFIG --exists "$lua_package"],
  [AC_MSG_ERROR([no supported system Lua found (tried: $lua_packages)])])
PKG_CHECK_MODULES([LUA], [$lua_package])

PKG_CHECK_MODULES([CMARK], [libcmark])
PKG_CHECK_MODULES([MINIZIP], [minizip zlib])
MINIZIP_HEADER_DIR=`$PKG_CONFIG --variable=includedir minizip`/minizip
AC_SUBST([MINIZIP_HEADER_DIR])
PKG_CHECK_MODULES([NCURSESW], [ncursesw])

AS_IF([test "x$enable_xwp" = xyes], [
  PKG_CHECK_MODULES([XWP], [glfw3 gl])
  AC_PATH_PROG([RSVG_CONVERT], [rsvg-convert])
  AS_IF([test -z "$RSVG_CONVERT"],
    [AC_MSG_ERROR([rsvg-convert is required when building xwp])])
])
AC_SUBST([RSVG_CONVERT])

stb_include=
for candidate in /usr/include/stb /usr/local/include/stb; do
  AS_IF([test -f "$candidate/stb_ds.h" &&
         test -f "$candidate/stb_truetype.h" &&
         test -f "$candidate/stb_rect_pack.h"], [stb_include=$candidate; break])
done
AS_IF([test -z "$stb_include"],
  [AC_MSG_ERROR([stb headers not found under /usr/include/stb or /usr/local/include/stb])])
STB_CFLAGS="-isystem $stb_include"
AC_SUBST([STB_CFLAGS])

AC_ARG_WITH([dictionary-path],
  [AS_HELP_STRING([--with-dictionary-path=FILE],
    [initial plain-text spelling dictionary @<:@default=none@:>@])],
  [dictionary_path=$withval], [dictionary_path=])
AC_ARG_WITH([dictionary-dir],
  [AS_HELP_STRING([--with-dictionary-dir=DIR],
    [directory containing spelling dictionaries @<:@default=/usr/share/dict@:>@])],
  [dictionary_dir=$withval], [dictionary_dir=/usr/share/dict])
AC_ARG_WITH([hyphenation-dir],
  [AS_HELP_STRING([--with-hyphenation-dir=DIR],
    [directory containing hyphenation patterns @<:@default=/usr/share/hyphen@:>@])],
  [hyphenation_dir=$withval], [hyphenation_dir=/usr/share/hyphen])
AC_SUBST([DICTIONARY_PATH], [$dictionary_path])
AC_SUBST([DICTIONARY_DIR], [$dictionary_dir])
AC_SUBST([HYPHENATION_DIR], [$hyphenation_dir])

AC_DEFINE([FILEFORMAT], [8], [Native document format version])
AC_DEFINE([WORDPROCESS_STOCK_LUA], [1], [Use the system PUC-Rio Lua runtime])
AC_DEFINE([CMARK_STATIC_DEFINE], [1], [Do not import libcmark symbols])

AC_CONFIG_FILES([Makefile])
AC_OUTPUT

AC_MSG_NOTICE([configuration summary:])
AC_MSG_NOTICE([  application version:  $app_version])
AC_MSG_NOTICE([  Lua package:          $lua_package])
AC_MSG_NOTICE([  graphical frontend:  $enable_xwp])
AC_MSG_NOTICE([  update caches:        $enable_update_desktop_caches])
AC_MSG_NOTICE([  default dictionary:  ${dictionary_path:-none}])
AC_MSG_NOTICE([  dictionaries dir:    $dictionary_dir])
AC_MSG_NOTICE([  hyphenation dir:     $hyphenation_dir])
