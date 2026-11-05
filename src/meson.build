sources = [
  'main.vala',
  'app.vala',
  'cycle_engine.vala',
  'database.vala',
  'day_dialog.vala',
  'preferences.vala',
  'window.vala',
]

deps = [
  config_dep,
  dependency ('gtk4'),
  dependency ('libadwaita-1'),
  dependency ('sqlite3'),
  dependency ('gee-0.8'),
]

blueprints = custom_target ('blueprints',
  input: files (
    'ui/day_dialog.blp',
    'ui/preferences.blp',
    'ui/window.blp',
  ),
  output: '.',
  command: [ find_program ('blueprint-compiler'), 'batch-compile', '@OUTPUT@', '@CURRENT_SOURCE_DIR@', '@INPUT@' ],
)

sources += gnome.compile_resources ('bloom-resources',
  'bloom.gresource.xml',
  c_name: 'bloom',
  dependencies: blueprints,
)

executable ('bloom', sources,
  dependencies: deps,
     vala_args: [ '--gresourcesdir=src/' ],
     include_directories: config_inc,
       install: true,
)
