project('wordprocess', 'c',
  version: '1.0',
  # gnu99, not strict c99: stb_ds.h's hashmap/array macros use the `typeof`
  # GNU extension, which strict ISO C99 (no GNU extensions) doesn't have.
  # gnu99 is still C99 -- it's the same standard with GCC/Clang's common
  # extensions left enabled, same as the vast majority of real-world C99
  # codebases (and the same compilers ab already builds this project with).
  default_options: ['c_std=gnu99', 'warning_level=1'],
)

fs = import('fs')

# Phase 4: every source built by this Meson project is plain C99 -- there
# is no 'cpp' language declared above. The legacy `ab` build system (which
# used to compile these same files as C++ via per-directory build.py files)
# is gone from this repository, so the sources were renamed src/c/**/*.cc
# -> *.c to match; nothing generator-copies them any more.

# Native-Linux scope: ncurses wp frontend and GLFW/OpenGL xwp frontend.
fileformat = 8
default_dictionary_path = get_option('dictionary_path')
dictionary_dir = get_option('dictionary_dir')
dictionary_available = default_dictionary_path != '' and fs.is_file(default_dictionary_path)
dictionary_dir_available = fs.is_dir(dictionary_dir)
if default_dictionary_path != '' and not dictionary_available
  warning(
    'Optional spelling dictionary not found at ' + default_dictionary_path + '.\n' +
    'Spellchecking can still use the personal dictionary. Install or provide a ' +
    'UTF-8 plain-text word list with one word per line, or configure ' +
    '-Ddictionary_path=/path/to/plain-word-list.',
  )
endif
hyphenation_dir = get_option('hyphenation_dir')
hyphenation_dir_available = fs.is_dir(hyphenation_dir)

summary({
  'Default spelling dictionary': default_dictionary_path,
  'Spelling dictionaries directory': dictionary_dir,
  'Dictionary available': dictionary_available,
  'Dictionaries directory available': dictionary_dir_available,
  'Hyphenation patterns directory': hyphenation_dir,
  'Hyphenation patterns directory available': hyphenation_dir_available,
}, section: 'Optional features')
build_date = run_command('date', '+%-d %B %Y', check: true).stdout().strip()

build_xwp = get_option('xwp')
app_version = get_option('app_version')

cmark_dep = dependency('libcmark')

# The system minizip.pc's Cflags only add -I<includedir>, but its headers
# live in <includedir>/minizip/ and zip.c includes them unprefixed
# (#include "unzip.h"), matching the flat layout of the old vendored
# third_party/minizip -- add that subdir explicitly.
minizip_pc_dep = dependency('minizip')
zlib_dep = dependency('zlib')
minizip_dep = declare_dependency(
  dependencies: [minizip_pc_dep, zlib_dep],
  include_directories: include_directories(
    minizip_pc_dep.get_variable(pkgconfig: 'includedir') / 'minizip',
    is_system: true,
  ),
)

# Phase 3: engine is the system's PUC-Rio Lua (5.1-5.5) via pkg-config, not
# the vendored third_party/luau anymore.
lua_version_opt = get_option('lua_version')
if lua_version_opt == 'auto'
  lua_versions_to_try = ['5.5', '5.4', '5.3', '5.2', '5.1']
else
  lua_versions_to_try = [lua_version_opt]
endif

lua_dep = dependency('lua' + lua_versions_to_try[0], required: false)
foreach v : lua_versions_to_try
  if not lua_dep.found()
    lua_dep = dependency('lua' + v, required: false)
  endif
endforeach
if not lua_dep.found()
  error('No system Lua found for lua_version=' + lua_version_opt +
        ' (looked for pkg-config package(s): ' +
        ', '.join(lua_versions_to_try) +
        '). Install one, e.g. sudo pacman -S lua54')
endif

# stb (stb_truetype.h/stb_rect_pack.h/stb_ds.h) is header-only with no
# pkg-config file; used by both the ncurses frontend (stb_ds.h, for a couple
# of small dynamic arrays) and the glfw frontend (all three headers).
stb_candidates = ['/usr/include/stb', '/usr/local/include/stb']
stb_dir = ''
foreach c : stb_candidates
  if stb_dir == '' and fs.is_dir(c)
    stb_dir = c
  endif
endforeach
if stb_dir == ''
  error('stb headers (stb_truetype.h, stb_rect_pack.h, stb_ds.h) not found under ' +
        ', '.join(stb_candidates) + ' -- install the system "stb" package')
endif
stb_inc = include_directories(stb_dir, is_system: true)

subdir('src/lua')
subdir('src/c')
subdir('src/c/arch/ncurses')
if build_xwp
  subdir('src/c/arch/glfw')
endif
subdir('extras')
subdir('tests')
