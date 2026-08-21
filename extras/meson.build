sed_prog = find_program('sed')

xwp_man = custom_target('xwp.1',
  input: meson.project_source_root() / 'xwp.man',
  output: 'xwp.1',
  command: [sed_prog,
    's/@@@DATE@@@/' + build_date + '/g; s/@@@VERSION@@@/' + app_version + '/g',
    '@INPUT@'],
  capture: true,
  install: true,
  install_dir: get_option('mandir') / 'man1',
)

wp_man = custom_target('wp.1',
  input: meson.project_source_root() / 'wp.man',
  output: 'wp.1',
  command: [sed_prog,
    's/@@@DATE@@@/' + build_date + '/g; s/@@@VERSION@@@/' + app_version + '/g',
    '@INPUT@'],
  capture: true,
  install: true,
  install_dir: get_option('mandir') / 'man1',
)

install_data('wordprocess.desktop',
  install_dir: get_option('datadir') / 'applications',
)

install_data('wordprocess.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps',
)

install_data('wordprocess.xml',
  install_dir: get_option('datadir') / 'mime/packages',
)
