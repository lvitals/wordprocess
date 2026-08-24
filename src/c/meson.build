globals_c_srcs = files(
  'utils.c', 'cmark.c', 'filesystem.c', 'textbuffer.c', 'main.c', 'screen.c', 'word.c', 'zip.c',
)

globals_lib = static_library('globals',
  globals_c_srcs, files('stb_ds_impl.c'),
  script_table_h,
  include_directories: [include_directories('.'), script_table_inc, stb_inc],
  c_args: ['-DFILEFORMAT=' + fileformat.to_string(), '-DCMARK_STATIC_DEFINE', '-DWORDPROCESS_STOCK_LUA'],
  dependencies: [cmark_dep, minizip_dep, lua_dep],
)

globals_dep = declare_dependency(
  link_with: globals_lib,
  include_directories: include_directories('.'),
  compile_args: ['-DFILEFORMAT=' + fileformat.to_string(), '-DWORDPROCESS_STOCK_LUA'],
  dependencies: [cmark_dep, minizip_dep, lua_dep],
)

# Sources common to every frontend (ncurses/glfw), compiled once per
# executable() since they read the -DFRONTEND define set by each frontend.
wordprocess_common_srcs = files('lua.c', 'clipboard.c')
wordprocess_common_c_args = [
  '-DDEFAULT_DICTIONARY_PATH=' + default_dictionary_path,
  '-DDICTIONARY_DIR=' + dictionary_dir,
  '-DVERSION=' + app_version,
  '-DWORDPROCESS_STOCK_LUA',
]
