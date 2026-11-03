// Builds tool/theme_metadata.json: every property the theme reader accepts
// for the components of `components.*` (and `cupertino`), with its type,
// choices, per-state flag, the Flutter field it sets, a description and
// the default. The single source of truth for the generated theme pages
// (tool/theme_docs.dart), and meant to be loaded by the language server.
//
// What it reads:
//  - the properties and their types: the reader itself, through
//    test/support/theme_catalog_dump.dart (a `flutter test` run);
//  - the Flutter class of each component: lib/src/theme/theme_components.dart;
//  - the descriptions: the `///` docs of the fields in the Flutter SDK,
//    shortened and put in plain words; what cannot be derived is in the
//    override maps below. The tool fails when any description is empty.
//
// Run from spring_boot_starter_flutter, after a Flutter update or when a
// component or property is added:
//
//   dart run tool/theme_metadata.dart [--catalog build/theme_catalog.json]
//
// Then `dart run tool/theme_docs.dart` for the pages.
//
// The JSON (tool/theme_metadata.json), stable and read by the tools that
// make spring_metadata.json (its `theme` section), the language server and
// the pages:
//
//   {
//     "generatedBy": "tool/theme_metadata.dart",
//     "flutterVersion": "3.47.7",
//     "states": ["default", "hovered", ...],   // keys of a value per state
//     "types": { "<type name>": <type>, ... }, // the type schema, below
//     "properties": [ { "name": "components.app-bar.background-color",
//                       "type", "states", "values", "description",
//                       "default", "flutter"?, "scope"?, "open"? } ],
//     "components": [ { "name", "title", "flutterClass", "themeDataField",
//                       "description", "ownRoot", "base",
//                       "properties": [ { "key", "component", "type",
//                           "values", "states", "flutterField",
//                           "description", "default" } ] } ]
//   }
//
// `properties` is the `theme` section of spring_metadata.json: every key
// below `spring.flutter.theme`, flat, with dotted names relative to a theme
// (the sections first, then each component). `*` stands for a free name.
// `scope` is `root` (only at the root) or `theme` (only in `themes.<name>`);
// without it the key works in both. `open: true` means anything may follow
// (tokens, styles). The sections come from the reader's rules and the
// hand-written pages in docs/flutter/theme.
//
// A property's `type` is a name in `types`, or `choice` (then `values`
// lists the choices), `text`, `map` or a list (`list of colors`). `states: true` means the value may also be a map from
// the names in `states` to values of that type.
//
// The type schema. Every type has a `kind` and a `description`:
//   - "string":  a text, optionally with a `pattern` (a regular expression
//                for the whole trimmed text) and `examples`;
//   - "number":  a number, with optional `min` and `max`;
//   - "boolean": `true` or `false`;
//   - "enum":    one of `values` (compared without case, `-` and `_`);
//   - "object":  a map of `keys`, each `{ "type": <type name>, "required":
//                bool, "description" }`; a key not listed is an error;
//   - "oneOf":   any of the types named in `of`.
// `color` is the type of every color: a plain string (`hex-color`,
// `color-name` or a `reference` such as `$colors.primary`) or a
// `color-object` `{ color, mix: { with, amount }, alpha }`. `mix` is
// applied first, then `alpha`; `color` is required; an unknown key is an
// error (with a "did you mean"). A `percent` is `0%` to `100%` or `0` to
// `1`. A `duration` is a number with the unit ms, s, m, h or d (decimals
// allowed); one syntax for motion, animations, styles, tokens,
// `transition`, `refresh` and `timeout`.
import 'dart:convert';
import 'dart:io';

import 'theme_sections.dart';

void main(List<String> args) {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final catalogIndex = args.indexOf('--catalog');
  final catalogPath = catalogIndex >= 0
      ? args[catalogIndex + 1]
      : _dumpCatalog();
  final catalog = (jsonDecode(File(catalogPath).readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final sdk = _Sdk(_flutterRoot());
  final classes = _componentClasses(
    File('lib/src/theme/theme_components.dart').readAsStringSync(),
  );

  final problems = <String>[];
  final components = <Map<String, Object?>>[];
  for (final MapEntry(key: name, value: list) in catalog.entries) {
    final info = classes[name] ?? const _ClassInfo();
    final propertyClass = _propertyClass[name] ?? info.dataClass;
    if (propertyClass == null) {
      problems.add('$name: no Flutter class found');
      continue;
    }
    final description = _componentDescriptions[name];
    if (description == null || description.isEmpty) {
      problems.add('$name: no component description');
    }
    final properties = <Map<String, Object?>>[];
    for (final raw in (list as List).cast<Map<String, dynamic>>()) {
      final key = raw['name'] as String;
      final kind = raw['kind'] as String;
      final isChoice = kind.startsWith('one of: ');
      final (cls, field) = _target(name, key, propertyClass);
      final override = _propertyOverrides['$name.$key'];
      final found = sdk.describe(cls, field);
      final text =
          override ??
          _fieldOverrides['$cls.$field'] ??
          _anyClassOverrides[field] ??
          found?.$1;
      if (text == null || text.trim().isEmpty) {
        problems.add('$name.$key ($cls.$field): no description');
        continue;
      }
      final base = "Flutter's Material 3 default";
      final fallback = found?.$2;
      properties.add({
        'key': key,
        'component': name,
        'type': isChoice ? 'choice' : kind,
        'values': isChoice
            ? kind.substring('one of: '.length).split(' | ')
            : <String>[],
        'states': raw['states'],
        'flutterField': _targetOverrides['$cls.$field'] ?? '$cls.$field',
        'description': text,
        'default':
            _defaultOverrides['$name.$key'] ??
            (fallback == null ? base : 'Flutter default: $fallback'),
      });
    }
    components.add({
      'name': name,
      'title': _title(name),
      'flutterClass': info.themeClass ?? propertyClass,
      'themeDataField': info.themeDataField,
      'description': description,
      'ownRoot': name == 'cupertino',
      'base':
          name.endsWith('-button') &&
              name != 'icon-button' &&
              name != 'segmented-button' &&
              name != 'menu-button'
          ? 'button'
          : null,
      'properties': properties,
    });
  }
  if (problems.isNotEmpty) {
    stderr
      ..writeln('theme metadata is incomplete (${problems.length}):')
      ..writeln(problems.join('\n'))
      ..writeln('Add them to the override maps in tool/theme_metadata.dart.');
    exitCode = 1;
    return;
  }
  File('tool/theme_metadata.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'generatedBy': 'tool/theme_metadata.dart',
      'flutterVersion': sdk.version,
      'states': _states,
      'types': _types(),
      'properties': [
        ...themeSections(),
        ...componentProperties(components),
      ],
      'components': components,
    })}\n',
  );
  final count = components.fold<int>(
    0,
    (n, c) => n + (c['properties']! as List).length,
  );
  stdout.writeln(
    'tool/theme_metadata.json: ${components.length} components, '
    '$count properties',
  );
}

// ---------------------------------------------------------------------
// The type schema
// ---------------------------------------------------------------------

// The states a value may be given for (themeStateNames of the reader).
const _states = [
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

// The names `Colors` has, from the starter's own table.
List<String> _colorNames() => [
  for (final m in RegExp(
    "^  '([A-Za-z0-9.]+)':",
    multiLine: true,
  ).allMatches(File('lib/src/theme/material_colors.dart').readAsStringSync()))
    m[1]!,
];

Map<String, Object?> _types() => {
  'percent': {
    'kind': 'string',
    'description':
        'A share: 0% to 100%, or a number from 0 to 1 (12% and 0.12 are '
        'the same).',
    'pattern': r'^(\d+(\.\d+)?|\.\d+)%?$',
    'min': 0,
    'max': 1,
    'examples': ['12%', '0.12', '100%'],
  },
  'hex-color': {
    'kind': 'string',
    'description': 'A color as #RGB, #RRGGBB or #AARRGGBB.',
    'pattern': r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
    'examples': ['#F00', '#FF40A0', '#80FF0000'],
  },
  'color-name': {
    'kind': 'enum',
    'description':
        "A name of Flutter's Colors: camelCase, kebab-case or snake_case "
        '(deepPurple, deep-purple); shades as deepPurple.shade200.',
    'values': _colorNames(),
  },
  'reference': {
    'kind': 'string',
    'description':
        'A reference to another value of the theme or to a Material '
        'color role: \$colors.primary, \$brand.accent.',
    'pattern': r'^\$[A-Za-z][A-Za-z0-9_.\-]*$',
    'examples': [r'$colors.primary', r'$brand.accent'],
  },
  'color-mix': {
    'kind': 'object',
    'description': 'Moves the color towards another one.',
    'keys': {
      'with': {
        'type': 'color',
        'required': true,
        'description': 'The color to move towards.',
      },
      'amount': {
        'type': 'percent',
        'required': true,
        'description': 'How far to move: 0% is the color, 100% is `with`.',
      },
    },
  },
  'color-object': {
    'kind': 'object',
    'description':
        'A color with changes: `mix` is applied first, then `alpha`.',
    'keys': {
      'color': {
        'type': 'color',
        'required': true,
        'description': 'The color to start from.',
      },
      'mix': {
        'type': 'color-mix',
        'required': false,
        'description': 'Mixes the color with another one.',
      },
      'alpha': {
        'type': 'percent',
        'required': false,
        'description': 'The opacity of the result; replaces the one it has.',
      },
    },
  },
  'color': {
    'kind': 'oneOf',
    'description':
        'A color: #RRGGBB, a Colors name, a \$ reference, or a color object.',
    'of': ['hex-color', 'color-name', 'reference', 'color-object'],
  },
  'duration': {
    'kind': 'string',
    'description':
        'A time: a number with the unit ms, s, m, h or d; decimals are '
        'allowed. A bare number is milliseconds where a duration is '
        'expected.',
    'pattern': r'^(\d+(\.\d+)?|\.\d+)\s*(ms|s|m|h|d)?$',
    'examples': ['250ms', '1.5s', '2m', '0.5d'],
  },
  'curve': {
    'kind': 'string',
    'description':
        'A curve name (ease-out, standard, bounce-out, ...) or four '
        'numbers, `0.2, 0, 0, 1`.',
    'examples': ['ease-out', '0.2, 0, 0, 1'],
  },
  'number': {'kind': 'number', 'description': 'A number.'},
  'whole number': {'kind': 'number', 'description': 'A whole number.'},
  'true / false': {
    'kind': 'boolean',
    'description': 'true or false.',
  },
  'elevation': {
    'kind': 'string',
    'description': 'level0 to level5 (Material 3), or a number.',
    'examples': ['level2', '3'],
  },
  'insets': {
    'kind': 'string',
    'description':
        '16, `h, v`, `l, t, r, b`, or a map of all, horizontal, vertical, '
        'left, top, right, bottom.',
    'examples': ['16', '12, 6', '8, 4, 8, 4'],
  },
  'shape': {
    'kind': 'string',
    'description': 'A shape token (small), a radius, or a map.',
  },
  'corner radius': {
    'kind': 'string',
    'description': 'A shape token (medium) or a number.',
  },
  'text style': {
    'kind': 'string',
    'description': 'A style name (title-large) or a map.',
  },
  'icon theme': {
    'kind': 'string',
    'description': 'A color, or a map of color, size, fill, weight, ...',
  },
  'size': {
    'kind': 'string',
    'description': '`width, height`, one number, or a map.',
  },
  'constraints': {
    'kind': 'object',
    'description': 'The least and most size of a widget.',
    'keys': {
      for (final key in ['min-width', 'max-width', 'min-height', 'max-height'])
        key: {'type': 'number', 'required': false, 'description': key},
    },
  },
  'border side': {
    'kind': 'string',
    'description': 'none, or a map of color, width, style, stroke-align.',
  },
  'mouse cursor': {
    'kind': 'string',
    'description': 'click, basic, forbidden, text, ...',
  },
  'alignment': {
    'kind': 'string',
    'description': 'center, top-left, ..., or `x, y` from -1 to 1.',
  },
  'offset': {'kind': 'string', 'description': '`x, y`.'},
  'visual density': {
    'kind': 'string',
    'description': 'standard, compact, comfortable, adaptive, or `h, v`.',
  },
  'decoration': {
    'kind': 'string',
    'description': 'A color, or a map of color, radius, border, shape.',
  },
  'input border': {
    'kind': 'string',
    'description': 'outline, underline, none, or a map.',
  },
  'animation': {
    'kind': 'object',
    'description': 'How long an animation of a component takes.',
    'keys': {
      'duration': {
        'type': 'duration',
        'required': true,
        'description': 'The time it takes.',
      },
      'reverse-duration': {
        'type': 'duration',
        'required': false,
        'description': 'The time it takes backwards.',
      },
    },
  },
};

// ---------------------------------------------------------------------
// The reader's properties
// ---------------------------------------------------------------------

String _dumpCatalog() {
  Directory('build').createSync();
  final result = Process.runSync(
    'flutter',
    ['test', 'test/support/theme_catalog_dump.dart'],
    environment: {'THEME_CATALOG_OUT': 'build/theme_catalog.json'},
  );
  if (result.exitCode != 0) {
    stderr
      ..write(result.stdout)
      ..write(result.stderr);
    exit(1);
  }
  return 'build/theme_catalog.json';
}

String _flutterRoot() {
  final result = Process.runSync('flutter', ['--version', '--machine']);
  final text = result.stdout as String;
  final json = jsonDecode(text.substring(text.indexOf('{'))) as Map;
  return json['flutterRoot']! as String;
}

// ---------------------------------------------------------------------
// The Flutter class of a component
// ---------------------------------------------------------------------

final class _ClassInfo {
  const _ClassInfo({this.themeClass, this.dataClass, this.themeDataField});

  /// The class the component's theme is (`AppBarTheme`).
  final String? themeClass;

  /// The class whose fields the properties are (`AppBarTheme`, or
  /// `ButtonStyle` for a button theme).
  final String? dataClass;

  /// The `ThemeData` field that holds it (`appBarTheme`).
  final String? themeDataField;
}

// Components whose properties are the fields of another class than the
// one they are set on.
const _propertyClass = <String, String>{
  'button': 'ButtonStyle',
  'elevated-button': 'ButtonStyle',
  'filled-button': 'ButtonStyle',
  'outlined-button': 'ButtonStyle',
  'text-button': 'ButtonStyle',
  'icon-button': 'ButtonStyle',
  'segmented-button': 'ButtonStyle',
  'menu-button': 'ButtonStyle',
  'menu': 'MenuStyle',
  'menu-bar': 'MenuStyle',
  'icon': 'IconThemeData',
  'primary-icon': 'IconThemeData',
  'input': 'InputDecorationThemeData',
  'cupertino': 'CupertinoThemeData',
};

// Nested groups: the class their properties are the fields of.
const _groupClass = <String, String>{
  'input-decoration': 'InputDecorationThemeData',
  'cancel-button-style': 'ButtonStyle',
  'confirm-button-style': 'ButtonStyle',
  'menu-style': 'MenuStyle',
  'text-theme': 'CupertinoTextThemeData',
};

Map<String, _ClassInfo> _componentClasses(String source) {
  final result = <String, _ClassInfo>{};
  final starts = RegExp(r"ThemeComponent\(\s*'([a-z-]+)'").allMatches(source);
  final list = starts.toList();
  for (var i = 0; i < list.length; i++) {
    final end = i + 1 < list.length ? list[i + 1].start : source.length;
    final block = source.substring(list[i].start, end);
    final match = RegExp(r'copyWith\(\s*(\w+):\s*(\w+)\(').firstMatch(block);
    final field = RegExp(r'copyWith\(\s*(\w+):').firstMatch(block)?[1];
    final themeClass = match?[2];
    result[list[i][1]!] = _ClassInfo(
      themeClass:
          themeClass != null && themeClass[0].toUpperCase() == themeClass[0]
          ? themeClass
          : null,
      dataClass:
          themeClass != null && themeClass[0].toUpperCase() == themeClass[0]
          ? themeClass
          : null,
      themeDataField: field,
    );
  }
  result['icon'] = const _ClassInfo(
    themeClass: 'IconThemeData',
    themeDataField: 'iconTheme',
  );
  result['primary-icon'] = const _ClassInfo(
    themeClass: 'IconThemeData',
    themeDataField: 'primaryIconTheme',
  );
  result['cupertino'] = const _ClassInfo(themeClass: 'CupertinoThemeData');
  result['button'] = const _ClassInfo(themeClass: 'ButtonStyle');
  return result;
}

// The class and field of a property: `date-picker`'s
// `input-decoration.border` is InputDecorationThemeData.border.
(String, String) _target(String component, String key, String componentClass) {
  final parts = key.split('.');
  final cls = parts.length > 1 ? _groupClass[parts.first]! : componentClass;
  return (cls, _camel(parts.last));
}

String _camel(String kebab) {
  final words = kebab.split('-');
  return words.first +
      words
          .skip(1)
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join();
}

String _title(String name) {
  final words = name.replaceAll('-', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

// ---------------------------------------------------------------------
// Flutter's dartdoc
// ---------------------------------------------------------------------

final class _Sdk {
  _Sdk(this.root) {
    final dir = Directory('$root/packages/flutter/lib/src');
    for (final file in dir.listSync(recursive: true)) {
      if (file is File && file.path.endsWith('.dart')) {
        _index(file);
      }
    }
    final info = Process.runSync('flutter', ['--version', '--machine']);
    final text = info.stdout as String;
    version =
        (jsonDecode(text.substring(text.indexOf('{')))
                as Map)['frameworkVersion']
            as String? ??
        'unknown';
  }

  final String root;
  late final String version;

  // class -> field -> doc lines
  final _docs = <String, Map<String, List<String>>>{};
  // file of the class
  final _classFile = <String, String>{};
  final _templates = <String, String>{};

  void _index(File file) {
    final lines = file.readAsLinesSync();
    String? current;
    var docs = <String>[];
    String? template;
    final templateLines = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final cls = RegExp(
        r'^(?:(?:abstract|final|base|sealed|interface|mixin)\s+)*class\s+(\w+)',
      ).firstMatch(line);
      if (cls != null) {
        current = cls[1];
        _docs.putIfAbsent(current!, () => {});
        _classFile.putIfAbsent(current, () => file.path);
      }
      final doc = RegExp(r'^\s*///\s?(.*)$').firstMatch(line);
      if (doc != null) {
        final text = doc[1]!;
        final start = RegExp(r'^\{@template ([\w.]+)\}').firstMatch(text);
        if (start != null) {
          template = start[1];
          templateLines.clear();
        } else if (text.startsWith('{@endtemplate}')) {
          if (template != null) {
            _templates[template] = templateLines.join('\n');
          }
          template = null;
        } else if (template != null) {
          templateLines.add(text);
        }
        docs.add(text);
        continue;
      }
      if (line.trim().startsWith('@')) {
        continue;
      }
      final field = RegExp(
        r'^  (?:static\s+)?(?:late\s+)?(?:final|const)?\s*[\w<>?,\s().]*?\b(\w+);\s*$',
      ).firstMatch(line);
      final getter = RegExp(r'^  [\w<>?,\s]+\bget (\w+)\b').firstMatch(line);
      final name = field?[1] ?? getter?[1];
      if (name != null && current != null && docs.isNotEmpty) {
        _docs[current]!.putIfAbsent(name, () => List.of(docs));
      }
      docs = <String>[];
    }
  }

  List<String>? _lookup(String cls, String field) {
    final direct = _docs[cls]?[field];
    if (direct != null) {
      return direct;
    }
    // The same file's other classes (`AppBarTheme` and `AppBarThemeData`).
    final path = _classFile[cls];
    if (path != null) {
      for (final MapEntry(:key, :value) in _docs.entries) {
        if (_classFile[key] == path && value.containsKey(field)) {
          return value[field];
        }
      }
    }
    return null;
  }

  /// A plain description and Flutter's default sentence (if it states
  /// one) of [cls].[field], or null when Flutter documents nothing.
  (String, String?)? describe(String cls, String field, [int depth = 0]) {
    final lines = _lookup(cls, field);
    if (lines == null || depth > 3) {
      return null;
    }
    final sentences = _sentences(_expand(lines.join('\n')));
    // "Overrides the default value of [AppBar.backgroundColor]": say what
    // that field does.
    for (final s in sentences) {
      final redirect = RegExp(
        r'overrides the default (?:value |shape |color )?(?:of|for) '
        r'(?:the )?(?:obsolete )?\[(\w+)\.(\w+)\]|'
        r'default value for \[(\w+)\.(\w+)\]',
        caseSensitive: false,
      ).firstMatch(s);
      if (redirect != null) {
        final target = describe(
          redirect[1] ?? redirect[3]!,
          redirect[2] ?? redirect[4]!,
          depth + 1,
        );
        if (target != null) {
          return target;
        }
      }
    }
    final main = <String>[];
    String? fallback;
    for (final s in sentences) {
      final clean = _plain(s);
      if (clean.isEmpty) {
        continue;
      }
      if (_isDefault(s)) {
        final value = _defaultSentence(clean);
        if (value.isNotEmpty) {
          fallback ??= value;
        }
        continue;
      }
      if (_isCode(s) ||
          RegExp(
            r'^(Overrides the default|See |This property is supported)|:$|'
            r'\bk [a-z]+|^[a-z]',
          ).hasMatch(clean)) {
        continue;
      }
      main.add(clean);
    }
    if (main.isEmpty) {
      // Only default or code sentences: say the first anyway.
      final any = [for (final s in sentences) _plain(s)].where(
        (s) => s.isNotEmpty && !RegExp(r'^See also').hasMatch(s),
      );
      if (any.isEmpty) {
        return null;
      }
      main.add(any.first);
    }
    var text = main.take(2).join(' ');
    if (text.length > 260) {
      text = main.first;
    }
    return (text, fallback);
  }

  String _expand(String text) => text.replaceAllMapped(
    RegExp(r'\{@macro ([\w.]+)\}'),
    (m) => _templates[m[1]] ?? '',
  );
}

bool _isDefault(String s) => RegExp(
  r'\b(null|defaults? to|default is|the default|by default)\b',
  caseSensitive: false,
).hasMatch(s);

bool _isCode(String s) => RegExp(
  r'WidgetStateProperty|MaterialStateProperty|copyWith|\{@|'
  r'WidgetState|widget state|https?://|ColorScheme|Theme\.of|ThemeData|MaterialApp|constructor|parameter|'
  r'\bTheme\b|[a-z]\.[a-z]+\(\)|\bTextTheme\b|\bthis class\b',
).hasMatch(s);

// What Flutter says the default is, when it is a plain value: "defaults to
// 4.0", "the default is 56 pixels". Empty otherwise.
String _defaultSentence(String clean) {
  final m = RegExp(
    r'(?:defaults? to|default (?:value )?is|default (?:value )?of) '
    r'([^.,;()]{1,40})(?:\.|,|;|$)',
    caseSensitive: false,
  ).firstMatch(clean);
  final value = m?[1]?.trim() ?? '';
  // Only true or false: numbers in the docs are often from Material 2.
  if (!RegExp(
    r'^(?:true|false)$',
  ).hasMatch(value)) {
    return '';
  }
  return value;
}

/// The paragraphs of a doc before its first list, code, tool or
/// "See also", as sentences.
List<String> _sentences(String doc) {
  var text = doc
      .replaceAll(RegExp(r'\{@tool[\s\S]*?\{@end-tool\}'), '')
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'\{@(template|endtemplate)[^}]*\}'), '')
      .replaceAll(RegExp(r'\{@(animation|image)[^}]*\}'), '');
  final cut = RegExp(r'^(See also|## )', multiLine: true).firstMatch(text);
  if (cut != null) {
    text = text.substring(0, cut.start);
  }
  final out = <String>[];
  for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
    final p = paragraph.trim();
    if (p.isEmpty ||
        p.startsWith('*') ||
        p.startsWith('-') ||
        p.startsWith('```') ||
        p.startsWith('{@') ||
        p.startsWith('    ') ||
        p.startsWith('![')) {
      continue;
    }
    final flat = p
        .replaceAll('e.g.', 'for example')
        .replaceAll('i.e.', 'that is')
        .replaceAll(RegExp(r'\s*\n\s*'), ' ');
    out.addAll(flat.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z`\[])')));
  }
  return out;
}

/// A sentence without Dartdoc markup: `[Foo.barBaz]` is "bar baz".
String _plain(String sentence) {
  var s = sentence
      .replaceAllMapped(RegExp(r'\[([\w.]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r'\[([\w.<>?]+)\]'), (m) {
        final last = m[1]!.split('.').last;
        return last
            .replaceAllMapped(
              RegExp(r'(?<=[a-z])(?=[A-Z])'),
              (_) => ' ',
            )
            .toLowerCase();
      })
      .replaceAll('`', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  s = s
      .replaceAll('MaterialStateProperty', 'state')
      .replaceAll('i os', 'iOS')
      .replaceAll('of the of the', 'of the')
      .replaceFirst(RegExp(r'^\(optional\)\s*'), '')
      .replaceFirst(RegExp(r'[;:]$'), '.')
      .replaceAll(
        RegExp(r',? in all (?:descendant )?[a-z ]*(?:widgets|states)'),
        '',
      )
      .replaceFirstMapped(
        RegExp(r'^Overrides (?:the )?(?:default )?(?:value (?:of|for) )?(.*)$'),
        (m) => 'Sets the ${m[1]!.replaceAll(" default ", " ")}',
      );
  return s;
}

// ---------------------------------------------------------------------
// By hand: what Flutter's docs cannot give
// ---------------------------------------------------------------------

// One phrase per component: what it is on screen.
const _componentDescriptions = <String, String>{
  'app-bar': 'The bar at the top of a screen, with a title and actions.',
  'badge':
      'A small dot or number shown on top of another widget, such as '
      'an unread count on an icon.',
  'banner':
      'A message bar at the top of a screen with actions to dismiss '
      'or follow it.',
  'bottom-app-bar':
      'The bar at the bottom of a screen that can hold '
      'actions and a floating action button.',
  'bottom-navigation-bar':
      'The bar at the bottom of a screen to switch '
      'between a few top-level pages.',
  'bottom-sheet': 'A panel that slides up from the bottom of the screen.',
  'button':
      'The settings every button shares: elevated, filled, outlined '
      'and text buttons start from them.',
  'elevated-button': 'A raised button with a shadow.',
  'filled-button': 'A button with a solid fill, for the main action.',
  'outlined-button': 'A button with a border and no fill.',
  'text-button': 'A flat button with no border and no fill.',
  'icon-button': 'A button that shows only an icon.',
  'segmented-button':
      'A row of connected buttons, one or more of them '
      'selected.',
  'menu-button': 'The buttons inside a menu or a menu bar.',
  'toggle-buttons': 'A row of buttons that can each be switched on or off.',
  'floating-action-button':
      'The round button floating over the content '
      'for the main action of a screen.',
  'card': 'A rounded panel with a shadow that groups related content.',
  'carousel-view':
      'A scrolling row of large items that stretch and '
      'shrink as you swipe.',
  'checkbox': 'A box that is ticked or cleared.',
  'chip': 'A small pill for a tag, a filter, a choice or an input.',
  'data-table': 'A table of rows and columns of data.',
  'date-picker': 'The dialog to pick a day or a range of days.',
  'dialog':
      'A window that appears over the content and asks for a '
      'decision.',
  'divider': 'A thin line between two pieces of content.',
  'drawer': 'A panel that slides in from the side of the screen.',
  'dropdown-menu': 'A text field with a menu of choices.',
  'expansion-tile': 'A list row that opens to show more content.',
  'icon': 'The default look of every icon.',
  'primary-icon': 'The default look of icons drawn on the primary color.',
  'input': 'Text fields: the border, fill, labels and hints.',
  'list-tile': 'A row in a list with a title, a subtitle and icons.',
  'menu': 'The panel of a menu that opens from a button.',
  'menu-bar':
      'A horizontal bar of menus, as at the top of a desktop '
      'window.',
  'navigation-bar':
      'The Material 3 bar at the bottom of the screen to '
      'switch between pages.',
  'navigation-drawer':
      'The Material 3 side panel with the destinations of '
      'the app.',
  'navigation-rail':
      'A narrow bar at the side of the screen to switch '
      'between pages.',
  'popup-menu': 'The small menu that pops up from a button or a tap.',
  'progress-indicator':
      'The circular and linear bars that show progress '
      'or waiting.',
  'radio': 'A round button to pick one option out of several.',
  'scrollbar': 'The bar that shows where you are in a scrolling list.',
  'search-bar':
      'A field to type a search, with a leading icon and '
      'actions.',
  'search-view':
      'The full-screen view with suggestions that opens from a '
      'search bar.',
  'slider': 'A control to pick a value by dragging a thumb along a track.',
  'snack-bar': 'A short message that appears at the bottom of the screen.',
  'switch': 'An on and off toggle.',
  'tab-bar': 'The row of tabs to switch between pages of content.',
  'text-selection':
      'The cursor, the highlight and the handles when you '
      'select text.',
  'time-picker': 'The dialog to pick a time of day.',
  'tooltip':
      'The small label that appears when you hover or long-press '
      'something.',
  'cupertino':
      'The iOS look of Cupertino widgets. It is read from its own '
      'root, not below components.',
};

// By "component.key": wins over everything.
const _propertyOverrides = <String, String>{};

// By "FlutterClass.field": for fields Flutter's docs do not describe in a
// way the tool can use, or that are the starter's own shortcut for another
// field.
const _fieldOverrides = <String, String>{
  'BottomSheetThemeData.surfaceTintColor':
      'The surface tint color of the sheet. Material 3 does not need it.',
  'InputDecorationThemeData.focusColor':
      'The color blended with the fill color while the field has focus.',
  'InputDecorationThemeData.hoverColor':
      'The color blended with the fill color while the pointer is over the '
      'field.',
  'TooltipThemeData.preferBelow':
      'Whether the tooltip appears below the widget when there is room. '
      'Set it to false to show it above, so a finger or the cursor does '
      'not cover it.',
  'MaterialBannerThemeData.elevation':
      'How far the banner is raised above the screen, which sets the size '
      'of its shadow.',
  'ButtonStyle.minHeight':
      'The least height of the button. A shortcut for the height of '
      'minimum-size, with no minimum width.',
  'ButtonStyle.borderColor':
      'The color of the button border, with the default border width. A '
      'shortcut for the color of side.',
  'ButtonStyle.iconAlignment':
      'Whether the icon of a button that has an icon and a label sits '
      'before (start) or after (end) the label.',
  'InputDecorationThemeData.style':
      'The look of the field: outline draws a box around it, underline a '
      'line below it and filled paints the field with a fill color and a '
      'line below it. It sets the border and the fill together.',
  'InputDecorationThemeData.shape':
      'The corner shape of the field border. A rounded shape rounds the '
      'corners of an outline field and the top corners of a filled one.',
  'InputDecorationThemeData.alignLabelWithHint':
      'Aligns the label with the hint at the top of the field instead of '
      'the center. Use it for fields with several lines.',
  'InputDecorationThemeData.outlineBorder':
      'The color and width of the border of an outline field.',
  'InputDecorationThemeData.activeIndicatorBorder':
      'The color and width of the line of an underline field.',
  'TooltipThemeData.shape':
      'The shape of the tooltip background. Together with background it '
      'replaces decoration.',
  'TooltipThemeData.background':
      'The fill color of the tooltip. Together with shape it replaces '
      'decoration.',
  'TooltipThemeData.padding':
      'The space between the tooltip text and the edge of the tooltip.',
  'TooltipThemeData.margin': 'The empty space around the tooltip.',
  'CupertinoTextThemeData.primaryColor':
      'The color of the text that shows an action, such as a button label '
      'or a link. The tint of the iOS text styles.',
  'IconThemeData.color': 'The color of icons.',
  'IconThemeData.size': 'The width and height of icons, in logical pixels.',
  'IconThemeData.fill':
      'How filled in the icon is, from 0 (outlined) to 1 (filled). Only '
      'for icon fonts with variable axes, such as Material Symbols.',
  'IconThemeData.weight':
      'The stroke weight of the icon, from 100 (thin) to 700 (bold). Only '
      'for icon fonts with variable axes.',
  'IconThemeData.grade':
      'A fine adjustment of the stroke thickness, from -25 to 200, '
      'without changing the size of the icon. Only for icon fonts with '
      'variable axes.',
  'IconThemeData.opticalSize':
      'The size the icon design is tuned for, from 20 to 48. Only for icon '
      'fonts with variable axes.',
  'IconThemeData.opacity':
      'How see-through icons are, from 0 (invisible) to 1 (opaque). It '
      'applies to the color you set and to the default one.',
  'AppBarTheme.systemOverlayStyle':
      'The look of the phone status bar (clock, battery) above the app '
      'bar: light or dark icons.',
  'ToggleButtonsThemeData.textStyle':
      'The text style of the button labels. Its color is ignored: color, '
      'selected-color and disabled-color are used instead.',
  'FloatingActionButtonThemeData.iconSize':
      'The size of the icon inside the floating action button.',
  'FloatingActionButtonThemeData.sizeConstraints':
      'The size limits of the regular floating action button.',
  'FloatingActionButtonThemeData.smallSizeConstraints':
      'The size limits of the small floating action button.',
  'FloatingActionButtonThemeData.largeSizeConstraints':
      'The size limits of the large floating action button.',
  'FloatingActionButtonThemeData.extendedSizeConstraints':
      'The size limits of the extended floating action button, the one '
      'with a label.',
  'BottomNavigationBarThemeData.landscapeLayout':
      'How the items are laid out when the screen is wide: spread across '
      'the bar, centered, or in a line.',
  'BottomSheetThemeData.dragHandleSize':
      'The size of the drag handle shown at the top of the sheet.',
  'BottomSheetThemeData.modalBarrierColor':
      'The color of the dimmed layer behind a modal bottom sheet.',
  'BadgeThemeData.smallSize':
      'The diameter of the badge when it is a plain dot, with no label.',
  'BadgeThemeData.largeSize': 'The height of the badge when it has a label.',
  'ChipThemeData.secondarySelectedColor':
      'The fill color of the chip when it is selected.',
  'ChipThemeData.deleteIconColor': 'The color of the delete icon.',
  'ChipThemeData.checkmarkColor':
      'The color of the check mark shown when the chip is selected.',
  'ChipThemeData.labelStyle': 'The text style of the chip label.',
  'ChipThemeData.secondaryLabelStyle':
      'The text style of the label when the chip is selected.',
  'ChipThemeData.shape': 'The shape of the chip border.',
  'CheckboxThemeData.overlayColor':
      'The highlight color when the checkbox is hovered, focused or '
      'pressed.',
  'RadioThemeData.overlayColor':
      'The highlight color when the radio button is hovered, focused or '
      'pressed.',
  'SwitchThemeData.overlayColor':
      'The highlight color when the switch is hovered, focused or pressed.',
  'CheckboxThemeData.side': 'The color and width of the checkbox border.',
  'DatePickerThemeData.dayStyle':
      'The text style of the day numbers. Its color is ignored: '
      'day-foreground-color is used instead.',
  'DatePickerThemeData.dayForegroundColor':
      'The color of the day numbers in the grid.',
  'DatePickerThemeData.dayOverlayColor':
      'The highlight color of a day when it is hovered, focused or pressed.',
  'DatePickerThemeData.dayShape':
      'The shape drawn behind a day number, for example a circle for the '
      'selected day.',
  'DatePickerThemeData.todayForegroundColor':
      "The color of today's number in the grid.",
  'DatePickerThemeData.yearStyle':
      'The text style of the years in the year selector. Its color is '
      'ignored: year-foreground-color is used instead.',
  'DatePickerThemeData.yearForegroundColor':
      'The color of the years in the year selector.',
  'DatePickerThemeData.yearShape':
      'The shape drawn behind a year in the year selector.',
  'DatePickerThemeData.rangePickerSurfaceTintColor':
      'The surface tint color of the date range picker dialog.',
  'DatePickerThemeData.rangePickerShape':
      'The shape of the full-screen date range picker dialog.',
  'DatePickerThemeData.rangePickerHeaderBackgroundColor':
      'The background color of the header of the date range picker, which '
      'shows the selected range.',
  'DatePickerThemeData.rangePickerHeaderForegroundColor':
      'The color of the text and icons in the header of the date range '
      'picker.',
  'DatePickerThemeData.rangePickerHeaderHeadlineStyle':
      'The text style of the headline in the date range picker header. '
      'Its color is ignored: range-picker-header-foreground-color is used '
      'instead.',
  'DatePickerThemeData.rangePickerHeaderHelpStyle':
      'The text style of the help text at the top of the date range picker '
      'header, such as "Select range".',
  'DatePickerThemeData.toggleButtonTextStyle':
      'The text style of the button that switches between the calendar '
      'and typing a date.',
  'DatePickerThemeData.subHeaderForegroundColor':
      'The color of the row with the month and the year, and its arrows.',
  'DialogThemeData.titleTextStyle': 'The text style of the dialog title.',
  'DialogThemeData.contentTextStyle': 'The text style of the dialog content.',
  'DialogThemeData.iconColor':
      'The color of the icon at the top of the dialog.',
  'DialogThemeData.barrierColor':
      'The color of the dimmed layer behind the dialog.',
  'DrawerThemeData.endShape':
      'The shape of a drawer that opens from the end side (the right in '
      'left-to-right languages).',
  'DropdownMenuThemeData.textStyle':
      'The text style of the text field of the dropdown menu.',
  'ExpansionTileThemeData.collapsedBackgroundColor':
      'The background color of the tile when it is collapsed.',
  'ListTileThemeData.style':
      'The style of the tile, list or drawer. It changes the default font '
      'of the title.',
  'ListTileThemeData.minTileHeight': 'The least height of the tile.',
  'ListTileThemeData.controlAffinity':
      'Where the checkbox, radio button or switch goes in a list tile: '
      'leading, trailing or platform.',
  'NavigationBarThemeData.indicatorColor':
      'The color of the pill behind the selected destination.',
  'NavigationBarThemeData.indicatorShape':
      'The shape of the pill behind the selected destination.',
  'NavigationBarThemeData.labelTextStyle':
      'The text style of the destination labels. A value per state can '
      'give the selected label another style.',
  'NavigationBarThemeData.iconTheme':
      'The style of the destination icons. A value per state can give the '
      'selected icon another style.',
  'NavigationDrawerThemeData.tileHeight': 'The height of each destination.',
  'NavigationDrawerThemeData.indicatorColor':
      'The color of the pill behind the selected destination.',
  'NavigationDrawerThemeData.indicatorShape':
      'The shape of the pill behind the selected destination.',
  'NavigationDrawerThemeData.indicatorSize':
      'The size of the pill behind the selected destination.',
  'NavigationDrawerThemeData.labelTextStyle':
      'The text style of the destination labels. A value per state can '
      'give the selected label another style.',
  'NavigationDrawerThemeData.iconTheme':
      'The style of the destination icons. A value per state can give the '
      'selected icon another style.',
  'NavigationRailThemeData.indicatorColor':
      'The color of the pill behind the selected destination, when '
      'use-indicator is on.',
  'NavigationRailThemeData.indicatorShape':
      'The shape of the pill behind the selected destination.',
  'NavigationRailThemeData.minWidth':
      'The least width of the rail when it is not extended.',
  'NavigationRailThemeData.minExtendedWidth':
      'The least width of the rail when it is extended, with the labels '
      'beside the icons.',
  'PopupMenuThemeData.menuPadding':
      'The padding around the items of the popup menu.',
  'PopupMenuThemeData.labelTextStyle':
      'The text style of the item labels. A value per state can style '
      'enabled and disabled items differently.',
  'ProgressIndicatorThemeData.trackGap':
      'The gap between the filled part and the track.',
  'SearchBarThemeData.constraints': 'The size limits of the search bar.',
  'SearchBarThemeData.textCapitalization':
      'How typed text is capitalized: none, words, sentences or '
      'characters.',
  'SearchViewThemeData.constraints': 'The size limits of the search view.',
  'SearchViewThemeData.padding': 'The padding inside the search view.',
  'SearchViewThemeData.barPadding':
      'The padding around the search field at the top of the search view.',
  'SearchViewThemeData.shrinkWrap':
      'Whether the view is only as tall as its suggestions.',
  'SearchViewThemeData.dividerColor':
      'The color of the line between the search field and the suggestions.',
  'SnackBarThemeData.behavior':
      'Where the snack bar appears: fixed at the bottom of the screen, or '
      'floating above it.',
  'SnackBarThemeData.showCloseIcon':
      'Whether the snack bar shows a close icon. Tapping it closes the '
      'snack bar.',
  'SnackBarThemeData.actionOverflowThreshold':
      'The share of the snack bar width the action may take before it '
      'moves to its own line, from 0 to 1.',
  'TimePickerThemeData.hourMinuteColor':
      'The background color of the hour and minute boxes in the header.',
};

// By Flutter field name, for any class.
const _anyClassOverrides = <String, String>{
  'enableFeedback':
      'Whether a tap or a long press gives a sound or a '
      'vibration.',
};

// By "FlutterClass.field": the Flutter field a key really sets, when the
// key is a shortcut and not the field's own name.
const _targetOverrides = <String, String>{
  'ButtonStyle.minHeight': 'ButtonStyle.minimumSize',
  'ButtonStyle.borderColor': 'ButtonStyle.side',
  'InputDecorationThemeData.style': 'InputDecorationThemeData.border',
  'InputDecorationThemeData.shape': 'InputDecorationThemeData.border',
  'TooltipThemeData.shape': 'TooltipThemeData.decoration',
  'TooltipThemeData.background': 'TooltipThemeData.decoration',
};

// By "component.key": the default when Flutter's docs state one in words
// the tool cannot take from them.
const _defaultOverrides = <String, String>{
  'icon.size': 'Flutter default: 24',
  'icon.fill': 'Flutter default: 0',
  'icon.weight': 'Flutter default: 400',
  'icon.grade': 'Flutter default: 0',
  'icon.optical-size': 'Flutter default: 48',
  'icon.opacity': 'Flutter default: 1',
  'primary-icon.size': 'Flutter default: 24',
  'primary-icon.fill': 'Flutter default: 0',
  'primary-icon.weight': 'Flutter default: 400',
  'primary-icon.grade': 'Flutter default: 0',
  'primary-icon.optical-size': 'Flutter default: 48',
  'primary-icon.opacity': 'Flutter default: 1',
};
