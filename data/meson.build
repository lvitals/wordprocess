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

install_data('icons/wordprocess.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps',
)

# The apps/ icon above is what launchers/taskbars show for the application
# itself; file managers look up a *document's* icon separately, by mimetype
# id under icons/hicolor/scalable/mimetypes (freedesktop icon-naming-spec).
# Without this, *.wp/*.wg files fall back to a generic/unknown-file-type icon
# even once the mimetype and default-app association are both working.
install_data('icons/wordprocess.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/mimetypes',
  rename: 'application-x-wordprocess.svg',
)

install_data('wordprocess.xml',
  install_dir: get_option('datadir') / 'mime/packages',
)

# Without this, a freshly installed .desktop/icon/mime-type won't show up
# (or won't take over the *.wp/*.wg file association) until something else
# happens to invalidate the icon theme, desktop file, and shared-mime-info
# caches -- refresh them as part of `meson install`, on any system that
# ships these.
if find_program('gtk-update-icon-cache', required: false).found() or
   find_program('update-desktop-database', required: false).found() or
   find_program('update-mime-database', required: false).found()
  update_desktop_caches = executable('update-desktop-caches', 'update-desktop-caches.c',
    native: true,
  )
  meson.add_install_script(update_desktop_caches, get_option('datadir'))
endif
