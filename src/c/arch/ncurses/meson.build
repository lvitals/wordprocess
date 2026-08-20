ncursesw_dep = dependency('ncursesw')

ncurses_c_srcs = files('dpy.c')

ncurses_lib = static_library('ncurses-frontend', ncurses_c_srcs,
  include_directories: stb_inc,
  dependencies: [globals_dep, ncursesw_dep],
)
ncurses_frontend_dep = declare_dependency(
  link_with: ncurses_lib,
  dependencies: [globals_dep, ncursesw_dep],
)

wordprocess_ncurses = executable('wp',
  wordprocess_common_srcs,
  c_args: wordprocess_common_c_args + ['-DFRONTEND=ncurses'],
  dependencies: [globals_dep, ncurses_frontend_dep],
  install: true,
)
