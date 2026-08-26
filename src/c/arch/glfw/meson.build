glfw3_dep = dependency('glfw3')
opengl_dep = dependency('opengl')

# Embeds the 4 bundled TTF fonts into font_table.h, same mechanism as
# src/lua/meson.build's script_table.h.
font_table_srcs = files(
  '../../../../data/fonts/FantasqueSansMono-Regular.ttf',
  '../../../../data/fonts/FantasqueSansMono-Italic.ttf',
  '../../../../data/fonts/FantasqueSansMono-Bold.ttf',
  '../../../../data/fonts/FantasqueSansMono-BoldItalic.ttf',
)
font_table_inc = include_directories('.')
font_table_h = custom_target('font_table.h',
  input: font_table_srcs,
  output: 'font_table.h',
  command: [find_program('python3'),
            meson.project_source_root() / 'tools/meson-multibin2c.py',
            '--root', meson.project_source_root(),
            'font_table', '@INPUT@'],
  capture: true,
)

# Keep the installed desktop icon and the GLFW window icon derived from the
# same vector source. GLFW consumes RGBA pixels, so rasterise a deterministic
# 128x128 PNG at build time; a Windows .ico container is neither used nor
# understood by glfwSetWindowIcon().
rsvg_convert = find_program('rsvg-convert')
window_icon_png = custom_target('wordprocess-window-icon.png',
  input: meson.project_source_root() / 'data/icons/wordprocess.svg',
  output: 'wordprocess-window-icon.png',
  command: [rsvg_convert, '--width', '128', '--height', '128',
            '--output', '@OUTPUT@', '@INPUT@'],
)

icon_c = custom_target('icon.c',
  input: window_icon_png,
  output: 'icon.c',
  command: [find_program('python3'),
            meson.project_source_root() / 'tools/makeicon.py', '@INPUT@'],
  capture: true,
)

glfw_c_srcs = files('font.c', 'main.c', 'utils.c', 'stb_impl.c')

glfw_lib = static_library('glfw-frontend',
  glfw_c_srcs, icon_c, font_table_h,
  include_directories: [font_table_inc, stb_inc],
  dependencies: [globals_dep, glfw3_dep, opengl_dep],
)
glfw_frontend_dep = declare_dependency(
  link_with: glfw_lib,
  include_directories: [stb_inc],
  dependencies: [globals_dep, glfw3_dep, opengl_dep],
)

wordprocess_glfw = executable('xwp',
  wordprocess_common_srcs,
  c_args: wordprocess_common_c_args + ['-DFRONTEND=glfw'],
  dependencies: [globals_dep, glfw_frontend_dep],
  install: true,
)
