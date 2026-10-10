project('singularity-colorpicker', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-colorpicker"', language: 'c')
subdir('po')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')
json_dep = dependency('json-glib-1.0')
gio_dep  = dependency('gio-2.0')
math_dep = meson.get_compiler('c').find_library('m')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core = files('src/color.vala', 'src/named.vala', 'src/portal.vala', 'src/vision.vala', 'src/extract.vala',
  'src/export.vala', 'src/fix.vala')

executable('singularity-colorpicker',
  core + files('src/wheel.vala', 'src/image.vala', 'src/window.vala', 'src/search.vala', 'src/colors_bus.vala', 'src/app.vala'),
  dependencies: [gtk_dep, gee_dep, json_dep, gio_dep, math_dep, libsingularity_dep],
  install: true
)

plugin_dir = get_option('libdir') / 'singularity' / 'plugins' / 'colorpicker'
shared_module('colorpicker',
  files('src/color.vala', 'src/named.vala', 'src/portal.vala', 'src/wheel.vala', 'src/plugin/plugin.vala'),
  dependencies: [gtk_dep, gee_dep, json_dep, gio_dep, dependency('gio-unix-2.0'), math_dep, libsingularity_dep, dependency('libpeas-2')],
  install: true,
  install_dir: plugin_dir
)
install_data('data/colorpicker.plugin', install_dir: plugin_dir)

install_data('data/capabilities/dev.sinty.ColorPicker1.ini',
  install_dir: get_option('datadir') / 'singularity' / 'capabilities'
)

install_data('data/dev.sinty.colorpicker.search.ini',
  rename: 'dev.sinty.colorpicker.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.colorpicker.service.in',
  output: 'dev.sinty.colorpicker.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

color_test = executable('colorpicker-test',
  core + files('tests/color_test.vala'),
  dependencies: [gee_dep, json_dep, gio_dep, math_dep],
)
test('color', color_test)

features_test = executable('colorpicker-features-test',
  core + files('tests/features_test.vala'),
  dependencies: [gee_dep, json_dep, gio_dep, math_dep],
)
test('features', features_test)

install_data('data/dev.sinty.colorpicker.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.colorpicker.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.colorpicker.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.colorpicker.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
