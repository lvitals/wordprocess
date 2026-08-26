# Build-time code generators used to embed data files (Lua sources, TTF
# fonts, the window icon) into the binary as C arrays. Native executables
# so they still run on the build machine when cross-compiling.
meson_multibin2c = executable('multibin2c', 'meson-multibin2c.c',
  native: true,
)

makeicon = executable('makeicon', 'makeicon.c',
  native: true,
)
