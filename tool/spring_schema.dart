// Makes a JSON Schema (draft 2020-12) for the application*.yml files of an
// app, from the spring_metadata.json of the app and of its dependencies
// (properties, value hints and, with the Flutter starter, the theme).
//
//   dart run tool/spring_schema.dart <app folder> [--out <file>]
//
// The default output is <app>/spring-application.schema.json. Any editor
// that understands JSON Schema then completes and checks the keys; point a
// file at it with a first line in the YAML:
//
//   # yaml-language-server: $schema=../../spring-application.schema.json
//
// The dependencies are found through .dart_tool/package_config.json (run
// `dart pub get` first); the metadata is written by the generator
// (`dart run build_runner build`). See roadmap/spring_metadata.md.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final rest = [...args];
  String? out;
  final outIndex = rest.indexOf('--out');
  if (outIndex >= 0) {
    out = rest[outIndex + 1];
    rest.removeRange(outIndex, outIndex + 2);
  }
  if (rest.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/spring_schema.dart <app folder> [--out <file>]',
    );
    exit(64);
  }
  final app = Directory(rest.single).absolute;
  final metadata = readMetadata(app);
  if (metadata.isEmpty) {
    stderr.writeln(
      'No lib/spring_gen/spring_metadata.json found for ${app.path} or its '
      'dependencies: run `dart run build_runner build` first.',
    );
    exit(1);
  }
  final file = File(out ?? '${app.path}/spring-application.schema.json');
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(buildSchema(metadata))}\n');
  stdout.writeln('${file.path}: ${metadata.length} packages');
}

/// The spring_metadata.json of the app and of the packages it depends on,
/// the app's own first.
List<Map<String, Object?>> readMetadata(Directory app) {
  final result = <Map<String, Object?>>[];
  final own = File('${app.path}/lib/spring_gen/spring_metadata.json');
  if (own.existsSync()) {
    result.add(_decode(own));
  }
  final config = _packageConfig(app);
  if (config == null) {
    return result;
  }
  final packages = (jsonDecode(config.readAsStringSync()) as Map)['packages'];
  for (final package in packages as List) {
    final root = config.uri.resolve('${(package as Map)['rootUri']}/');
    final file = File.fromUri(
      root
          .resolve('${package['packageUri'] ?? 'lib/'}spring_gen/')
          .resolve('spring_metadata.json'),
    );
    if (file.existsSync() && file.parent.parent.parent.path != app.path) {
      result.add(_decode(file));
    }
  }
  return result;
}

Map<String, Object?> _decode(File file) =>
    (jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>();

// The nearest .dart_tool/package_config.json, up from the app (a workspace
// keeps it at its root).
File? _packageConfig(Directory app) {
  for (var dir = app; ; dir = dir.parent) {
    final file = File('${dir.path}/.dart_tool/package_config.json');
    if (file.existsSync()) {
      return file;
    }
    if (dir.parent.path == dir.path) {
      return null;
    }
  }
}

/// The JSON Schema of `application*.yml` for the [metadata] of the packages.
Map<String, Object?> buildSchema(List<Map<String, Object?>> metadata) {
  final root = _Node();
  final defs = <String, Object?>{
    'placeholder': {
      'type': 'string',
      'pattern': r'^\s*\$\{.*\}\s*$',
      'description': 'A placeholder, resolved when the app starts.',
    },
  };
  final hints = <String, Map<String, Object?>>{};
  for (final package in metadata) {
    for (final property in _maps(package['properties'])) {
      root.at('${property['name']}').property = property;
    }
    for (final hint in _maps(package['hints'])) {
      hints['${hint['name']}'] = {...?hints['${hint['name']}'], ...hint};
    }
    final theme = package['theme'];
    if (theme is Map) {
      _addTheme(root, defs, theme.cast<String, Object?>());
    }
  }
  for (final MapEntry(:key, :value) in hints.entries) {
    root.at(key).hint = value;
  }
  final schema = root.schema();
  return {
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id': 'https://github.com/NeonMaliket/spring_core_dart/spring-application.schema.json',
    'title': 'Spring application properties (application*.yml)',
    ...schema,
    r'$defs': defs,
  };
}

List<Map<String, Object?>> _maps(Object? value) => [
  for (final item in value as List? ?? const [])
    if (item is Map) item.cast<String, Object?>(),
];

// -- The tree of keys ---------------------------------------------------

// A key of the YAML: its own info (a property, a hint) and the keys below.
final class _Node {
  final children = <String, _Node>{};
  _Node? wildcard;
  _Node? items;
  Map<String, Object?>? property;
  Map<String, Object?>? hint;
  Map<String, Object?>? raw;

  // The node of a dotted name: `a.b[*].c` and `a.*.c` as in the metadata.
  _Node at(String name) {
    var node = this;
    for (final part in name.split('.')) {
      var segment = part;
      var list = false;
      if (segment.endsWith('[*]')) {
        segment = segment.substring(0, segment.length - 3);
        list = true;
      }
      if (segment == '*') {
        node = node.wildcard ??= _Node();
      } else if (segment.isNotEmpty) {
        node = node.children.putIfAbsent(segment, _Node.new);
      }
      if (list) {
        node = node.items ??= _Node();
      }
    }
    return node;
  }

  Map<String, Object?> schema() {
    if (raw != null && children.isEmpty && wildcard == null && items == null) {
      return raw!;
    }
    final type = '${property?['type'] ?? ''}';
    final isList = items != null || type.startsWith('List<') || type == 'List';
    final isMap = wildcard != null || type.startsWith('Map<') || type == 'Map';
    final result = <String, Object?>{};
    if (isList && children.isEmpty) {
      // A list may also be written as one comma-separated text.
      result['anyOf'] = [
        {
          'type': 'array',
          'items': items?.schema() ?? _scalar(_argument(type, 0), null),
        },
        {'type': 'string'},
      ];
    } else if (children.isNotEmpty || isMap) {
      result['type'] = 'object';
      if (children.isNotEmpty) {
        result['properties'] = {
          for (final key in children.keys.toList()..sort())
            key: children[key]!.schema(),
        };
      }
      result['additionalProperties'] =
          wildcard?.schema() ??
          (children.isEmpty ? _scalar(_argument(type, 1), null) : true);
    } else {
      result.addAll(_scalar(type, hint));
    }
    final description = property?['description'] ?? hint?['description'];
    if (description != null) {
      result['description'] = description;
    }
    final defaultValue = property?['default'];
    if (defaultValue != null) {
      result['default'] = defaultValue;
    }
    if (property?['deprecated'] != null) {
      result['deprecated'] = true;
    }
    if (hint != null && result['type'] == null && result['anyOf'] == null) {
      result.addAll(_scalar('', hint));
    }
    return result;
  }
}

// The first values of a list, for a hover text.
String _sample(Object? values) =>
    '${(values! as List).take(6).join(', ')}, ...';

// `List<String>` -> `String`; `Map<String, int>` -> `int` (index 1).
String _argument(String type, int index) {
  final open = type.indexOf('<');
  if (open < 0 || !type.endsWith('>')) {
    return '';
  }
  final parts = type.substring(open + 1, type.length - 1).split(',');
  return parts.length > index ? parts[index].trim() : '';
}

// The schema of a value of a Dart [type], narrowed by a [hint].
Map<String, Object?> _scalar(String type, Map<String, Object?>? hint) {
  final base = type.endsWith('?') ? type.substring(0, type.length - 1) : type;
  final json = switch (base) {
    'String' => 'string',
    'int' => 'integer',
    'double' || 'num' => 'number',
    'bool' => 'boolean',
    'Duration' || 'Uri' || 'DateTime' => 'string',
    _ => null,
  };
  final result = <String, Object?>{};
  final values = hint?['values'];
  final range = hint?['range'];
  if (values is List && values.isNotEmpty) {
    final choices = [
      for (final value in values)
        if (value is Map)
          {
            'const': value['value'],
            if (value['description'] != null)
              'description': value['description'],
          }
        else
          {'const': value},
    ];
    result['anyOf'] = [
      ...choices,
      {r'$ref': r'#/$defs/placeholder'},
    ];
    return result;
  }
  if (json == null) {
    return result;
  }
  if (json == 'string') {
    result['type'] = 'string';
  } else {
    result['anyOf'] = [
      {
        'type': json,
        if (range is List && range.length == 2) ...{
          'minimum': range[0],
          'maximum': range[1],
        },
      },
      {r'$ref': r'#/$defs/placeholder'},
    ];
  }
  final warn = hint?['warn'];
  if (warn is List && warn.isNotEmpty) {
    // JSON Schema has no warnings: say it in the hover text.
    result['markdownDescription'] = [
      for (final entry in warn)
        if (entry is Map) '${entry['message']} (${_sample(entry['values'])})',
    ].join('\n');
  }
  return result;
}

// -- The theme ----------------------------------------------------------

const _defaultStates = [
  'default',
  'hovered',
  'focused',
  'pressed',
  'dragged',
  'selected',
  'scrolled-under',
  'disabled',
  'error',
];

// The theme types become $defs, its properties go under
// spring.flutter.theme (the root shared by all themes, `light`, `dark` and
// `themes.*`).
void _addTheme(
  _Node root,
  Map<String, Object?> defs,
  Map<String, Object?> theme,
) {
  final types = (theme['types'] as Map? ?? const {}).cast<String, Object?>();
  final states = [
    for (final s in theme['states'] as List? ?? _defaultStates) '$s',
  ];
  for (final MapEntry(:key, :value) in types.entries) {
    defs[_defName(key)] = _typeSchema((value! as Map).cast<String, Object?>());
  }
  defs['theme-state-name'] = {'enum': states};
  final theNode = root.at('spring.flutter.theme');
  final inThemes = [
    theNode.at('light'),
    theNode.at('dark'),
    theNode.at('themes.*'),
  ];
  for (final property in _maps(theme['properties'])) {
    final name = '${property['name']}';
    final schema = _propertySchema(property, types);
    // `scope` says where a key works: only at the root, only inside a
    // theme, or (without it) both.
    final scope = property['scope'];
    final mounts = [
      if (scope != 'theme') theNode,
      if (scope != 'root') ...inThemes,
    ];
    for (final mount in mounts) {
      (name.startsWith('spring.flutter.theme.') ? root : mount).at(name).raw =
          schema;
    }
  }
}

String _defName(String type) => type
    .replaceAll(RegExp('[^A-Za-z0-9_-]+'), '-')
    .replaceAll(RegExp(r'-+$'), '');

Map<String, Object?> _ref(String type) => {
  r'$ref': '#/\$defs/${_defName(type)}',
};

Map<String, Object?> _propertySchema(
  Map<String, Object?> property,
  Map<String, Object?> types,
) {
  final type = '${property['type']}';
  final values = property['values'];
  Map<String, Object?> value;
  if (type == 'choice' ||
      (values is List && values.isNotEmpty && !types.containsKey(type))) {
    value = {'enum': values};
  } else if (types.containsKey(type)) {
    value = _ref(type);
  } else {
    value = {};
  }
  final alternatives = <Map<String, Object?>>[
    value,
    if (property['states'] == true)
      {
        'type': 'object',
        'propertyNames': {r'$ref': r'#/$defs/theme-state-name'},
        'additionalProperties': value,
      },
    {r'$ref': r'#/$defs/placeholder'},
  ];
  return {
    'anyOf': alternatives,
    if (property['description'] != null) 'description': property['description'],
    if (property['default'] != null) 'default': property['default'],
  };
}

// A type of the theme schema as JSON Schema.
Map<String, Object?> _typeSchema(Map<String, Object?> type) {
  final description = type['description'];
  final result = <String, Object?>{
    'description': ?description,
  };
  switch (type['kind']) {
    case 'string':
      result['type'] = 'string';
      if (type['pattern'] != null) {
        result['pattern'] = type['pattern'];
      }
      if (type['examples'] != null) {
        result['examples'] = type['examples'];
      }
    case 'number':
      result['type'] = 'number';
      if (type['min'] != null) {
        result['minimum'] = type['min'];
      }
      if (type['max'] != null) {
        result['maximum'] = type['max'];
      }
    case 'boolean':
      result['type'] = 'boolean';
    case 'enum':
      result['enum'] = type['values'];
    case 'object':
      final keys = (type['keys'] as Map? ?? const {}).cast<String, Object?>();
      result['type'] = 'object';
      result['properties'] = {
        for (final MapEntry(:key, :value) in keys.entries)
          key: {
            ..._ref('${(value! as Map)['type']}'),
            'description': ?(value as Map)['description'],
          },
      };
      final required = [
        for (final MapEntry(:key, :value) in keys.entries)
          if ((value! as Map)['required'] == true) key,
      ];
      if (required.isNotEmpty) {
        result['required'] = required;
      }
      result['additionalProperties'] = false;
    case 'oneOf':
      result['anyOf'] = [for (final t in type['of']! as List) _ref('$t')];
  }
  return result;
}
