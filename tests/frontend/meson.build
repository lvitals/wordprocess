# Frontend smoke tests: these exercise the real ncurses frontend (resize,
# key input, terminal output) through a pseudo-terminal, below the
# wg.getscreensize()/RedrawScreen() boundary the rest of tests/ mocks out.
# See ptysmoke.c for why a small native helper is needed at all, and
# wp-pty-smoke.lua for the actual checks -- that file, not this one, is
# where the pass/fail logic lives.

cc = meson.get_compiler('c')
libutil_dep = cc.find_library('util', required: false)

ptysmoke = executable('ptysmoke', 'ptysmoke.c',
  dependencies: [libutil_dep],
)

test('frontend-wp-pty-smoke', wordprocess_ncurses,
  args: ['--lua', meson.current_source_dir() / 'wp-pty-smoke.lua',
         wordprocess_ncurses.full_path(), ptysmoke.full_path()],
  workdir: meson.project_source_root(),
  timeout: 60,
)
