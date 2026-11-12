// Writes the theme component pages and the component table:
//
//  - ../docs/flutter/theme/components/<component>.md, one per component,
//    and components/index.md;
//  - the table between `<!-- theme-components:start -->` and
//    `<!-- theme-components:end -->` in ../docs/configuration.md.
//
// Everything comes from tool/theme_metadata.json (see
// tool/theme_metadata.dart, which builds it). CI runs this and fails when
// the output differs from what is committed. From spring_boot_starter_flutter:
//
//   dart run tool/theme_docs.dart
import 'dart:convert';
import 'dart:io';

const _start = '<!-- theme-components:start -->';
const _end = '<!-- theme-components:end -->';
const _baseDefault = "Flutter's Material 3 default";

// The design starters that read what the pages describe: the core starter
// reads neither `components` nor `cupertino`.
const _materialStarter =
    'The Material starter, `spring_boot_starter_flutter_material`,';
const _cupertinoStarter =
    'The Cupertino starter, `spring_boot_starter_flutter_cupertino`,';

void main() {
  Directory.current = File.fromUri(Platform.script).parent.parent;
  final meta = jsonDecode(
    File('tool/theme_metadata.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final flutterVersion = meta['flutterVersion'] as String;
  final components = [
    for (final c in meta['components'] as List) _Component.from(c as Map),
  ];

  final dir = Directory('../docs/flutter/theme/components')
    ..createSync(recursive: true);
  final written = <String>{'index.md'};
  // Pages are numbered from 1; the index is 0. Cupertino has its own page.
  var order = 0;
  for (final c in components) {
    if (c.ownRoot) {
      continue;
    }
    order++;
    File('${dir.path}/${c.name}.md').writeAsStringSync(
      _page(c, order, flutterVersion),
    );
    written.add('${c.name}.md');
  }
  File('${dir.path}/index.md').writeAsStringSync(
    _index(components, flutterVersion),
  );
  // A page of a component that no longer exists goes away.
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('.md') && !written.contains(name)) {
      file.deleteSync();
    }
  }
  _updateConfiguration(components);
  final count = components.fold<int>(0, (n, c) => n + c.properties.length);
  stdout.writeln(
    '${written.length - 1} component pages, $count properties, '
    'docs/configuration.md table',
  );
}

// ---------------------------------------------------------------------
// The metadata
// ---------------------------------------------------------------------

final class _Property {
  _Property(Map<dynamic, dynamic> json)
    : key = json['key'] as String,
      type = json['type'] as String,
      values = (json['values'] as List).cast<String>(),
      states = json['states'] as bool,
      field = json['flutterField'] as String,
      description = json['description'] as String,
      defaultValue = json['default'] as String;

  final String key;
  final String type;
  final List<String> values;
  final bool states;
  final String field;
  final String description;
  final String defaultValue;
}

final class _Component {
  _Component.from(Map<dynamic, dynamic> json)
    : name = json['name'] as String,
      title = json['title'] as String,
      flutterClass = json['flutterClass'] as String,
      themeDataField = json['themeDataField'] as String?,
      description = json['description'] as String,
      ownRoot = json['ownRoot'] as bool,
      base = json['base'] as String?,
      properties = [
        for (final p in json['properties'] as List) _Property(p as Map),
      ];

  final String name;
  final String title;
  final String flutterClass;
  final String? themeDataField;
  final String description;
  final bool ownRoot;
  final String? base;
  final List<_Property> properties;

  String get path => ownRoot
      ? 'spring.flutter.theme.$name'
      : 'spring.flutter.theme.components.$name';
}

// ---------------------------------------------------------------------
// One page
// ---------------------------------------------------------------------

String _page(_Component c, int order, String flutterVersion) {
  final b = StringBuffer();
  final example = _example(c);
  final titleWord = c.title;
  final description = _pageDescription(c);
  final words = c.name.split('-');
  b
    ..writeln('---')
    ..writeln('title: "$titleWord theme in YAML — Spring for Dart"')
    ..writeln('description: "$description"')
    ..writeln('slug: /docs/flutter/theme/components/${c.name}')
    ..writeln('section: Flutter / Theme / Components')
    ..writeln('order: $order')
    ..writeln(
      'keywords: [flutter, theme, yaml, ${words.join(' ')}, '
      '${c.flutterClass}]',
    )
    ..writeln('---')
    ..writeln()
    ..writeln('# $titleWord theme in YAML')
    ..writeln()
    ..writeln(_intro(c))
    ..writeln()
    ..writeln('## Example')
    ..writeln()
    ..writeln('```yaml')
    ..write(example)
    ..writeln('```')
    ..writeln()
    ..writeln('## Properties')
    ..writeln()
    ..writeln(
      'Every property is optional. One you leave out keeps '
      "Flutter's value.",
    )
    ..writeln();
  if (c.properties.any((p) => p.key.contains('.'))) {
    b
      ..writeln(
        'A key with a dot, such as `${c.properties.firstWhere((p) => p.key.contains('.')).key}`, '
        'is inside a group: write it as a map under the first part.',
      )
      ..writeln();
  }
  b
    ..writeln(_table(c))
    ..writeln();
  if (c.properties.any((p) => p.states)) {
    b
      ..writeln('### Values per state')
      ..writeln()
      ..writeln(
        'A property with **yes** in the States column takes one value, or a '
        'map with a value for each state the widget can be in: `default`, '
        '`hovered`, `focused`, `pressed`, `disabled`, `selected`, `error`, '
        '`dragged` and `scrolled-under`. The widget uses the value of the '
        'strongest state it is in, in that order (`disabled` first), and '
        'then `default`. A state you leave out keeps '
        "Flutter's value. See [Styles and states](../styles-and-states.md).",
      )
      ..writeln();
  }
  final dart = _dartNote(c);
  if (dart != null) {
    b
      ..writeln('## Read it in Dart')
      ..writeln()
      ..writeln(dart)
      ..writeln();
  }
  b
    ..writeln('## See also')
    ..writeln()
    ..writeln('- [All component themes](index.md)')
    ..writeln('- [Theme overview](../index.md)')
    ..writeln('- [Colors](../colors.md)');
  final types = c.properties.map((p) => p.type).toSet();
  if (types.contains('text style')) {
    b.writeln('- [Typography](../typography.md)');
  }
  if (types.any(
    (t) => const {'shape', 'elevation', 'insets', 'corner radius'}.contains(t),
  )) {
    b.writeln(
      '- [Shape, spacing and elevation](../shape-spacing-elevation.md)',
    );
  }
  b
    ..writeln('- [Styles and states](../styles-and-states.md)')
    ..writeln('- [Tokens and references](../tokens-and-references.md)')
    ..writeln('- [Root theme properties](../properties.md)');
  if (c.name == 'cupertino') {
    b.writeln('- [Cupertino](../cupertino.md)');
  }
  b
    ..writeln(
      '- [Configuration reference](../../../configuration.md) '
      '(all properties of the framework)',
    )
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln(_footer(flutterVersion));
  return b.toString();
}

String _footer(String flutterVersion) =>
    '*Property descriptions are adapted from the documentation of the '
    'Flutter SDK ($flutterVersion), copyright The Flutter Authors, '
    'BSD 3-Clause license.*';

String _pageDescription(_Component c) {
  final plain = c.properties.where((p) => !p.key.contains('.')).toList();
  for (var n = 3; n >= 1; n--) {
    final keys = [for (final p in plain.take(n)) p.key];
    final list = keys.length == 1
        ? keys.first
        : '${keys.take(keys.length - 1).join(', ')} and ${keys.last}';
    final text =
        'Style the ${c.title.toLowerCase()} in YAML: ${c.properties.length} '
        'properties such as $list, set under ${c.name}.';
    if (text.length <= 160) {
      return text;
    }
  }
  return 'Style the ${c.title.toLowerCase()} in YAML with '
      '${c.properties.length} properties.';
}

String _intro(_Component c) {
  final b = StringBuffer(c.description)..write(' ');
  if (c.ownRoot) {
    b.write(
      "It configures Flutter's `${c.flutterClass}`. Unlike the other "
      'themes it is not below `components`: it has a root of its own, '
      '`${c.path}`.',
    );
  } else if (c.name == 'button') {
    b.write(
      "It configures Flutter's `ButtonStyle`. The properties below are "
      'shared: [elevated-button](elevated-button.md), '
      '[filled-button](filled-button.md), '
      '[outlined-button](outlined-button.md) and '
      '[text-button](text-button.md) start from them, and a value a button '
      'sets itself wins. Set them under `${c.path}`.',
    );
  } else if (c.base != null) {
    b.write(
      "It configures Flutter's `${c.flutterClass}`, whose `style` is a "
      '`ButtonStyle`. It starts from [button](button.md): a value set here '
      'wins over the one of `button`. Set it under `${c.path}`.',
    );
  } else if (c.flutterClass == 'ButtonStyle' || c.flutterClass == 'MenuStyle') {
    b.write(
      "It configures Flutter's `${c.flutterClass}`, with the same "
      'properties as a button style. Set it under `${c.path}`.',
    );
  } else {
    b.write(
      "It configures Flutter's `${c.flutterClass}`. Set it under "
      '`${c.path}`.',
    );
  }
  b
    ..write(
      ' You can also set it inside a named theme, under '
      '`spring.flutter.theme.themes.<name>.${c.ownRoot ? c.name : 'components.${c.name}'}`.',
    )
    ..write(
      ' ${c.ownRoot ? _cupertinoStarter : _materialStarter} reads it: an '
      'app without that package in its dependencies shows nothing of it.',
    );
  return b.toString();
}

String? _dartNote(_Component c) {
  if (c.ownRoot) {
    return 'The Cupertino starter builds a `CupertinoThemeData` from these '
        'properties. In a widget:\n\n'
        '```dart\nfinal cupertino = CupertinoTheme.of(context);\n```';
  }
  final field = c.themeDataField;
  if (field == null) {
    return null;
  }
  final access = c.flutterClass == 'ButtonStyle' || c.base != null
      ? 'Theme.of(context).$field.style'
      : 'Theme.of(context).$field';
  return 'The Material starter sets `ThemeData.$field` from these '
      'properties. In a widget, read the result with:\n\n'
      '```dart\nfinal theme = $access;\n```';
}

// ---------------------------------------------------------------------
// The example
// ---------------------------------------------------------------------

const _samples = <String, String>{
  'color': r'$colors.primary',
  'elevation': 'level2',
  'number': '16',
  'whole number': '2',
  'true / false': 'true',
  'insets': '{ horizontal: 16, vertical: 8 }',
  'shape': 'large',
  'corner radius': 'medium',
  'text style': '{ style: title-large, weight: bold }',
  'icon theme': r'{ color: $colors.primary, size: 24 }',
  'size': '{ width: 48, height: 48 }',
  'constraints': '{ max-width: 640 }',
  'border side': r'{ color: $colors.outline, width: 1 }',
  'mouse cursor': 'click',
  'alignment': 'center',
  'offset': "'4, -4'",
  'visual density': 'compact',
  'duration': '200ms',
  'decoration': r'{ color: $colors.surface-container, radius: medium }',
  'input border': 'outline',
  'animation': '{ duration: 250ms }',
};

const _byKey = <String, String>{'min-height': '40', 'height': '56'};

String _sample(_Property p, {int pick = 0}) {
  if (p.type == 'choice') {
    return p.values[pick % p.values.length];
  }
  if (p.type == 'color' && pick > 0) {
    return const [
      r'$colors.on-primary',
      r'$colors.surface',
      r'$colors.secondary',
      r'$colors.outline',
    ][(pick - 1) % 4];
  }
  return _byKey[p.key] ?? _samples[p.type] ?? '16';
}

String _example(_Component c) {
  final plain = [
    for (final p in c.properties)
      if (!p.key.contains('.')) p,
  ];
  final chosen = <_Property>[];
  // One state property first (a color when there is one), then other
  // types, so the example shows several kinds of value.
  final stateful =
      plain.where((p) => p.states && p.type == 'color').firstOrNull ??
      plain.where((p) => p.states).firstOrNull;
  if (stateful != null) {
    chosen.add(stateful);
  }
  final seenTypes = {if (stateful != null) stateful.type};
  for (final p in plain) {
    if (chosen.length >= 6) {
      break;
    }
    if (!chosen.contains(p) && seenTypes.add(p.type)) {
      chosen.add(p);
    }
  }
  for (final p in plain) {
    if (chosen.length >= 5) {
      break;
    }
    if (!chosen.contains(p)) {
      chosen.add(p);
    }
  }
  // Keep the order of the reference.
  chosen.sort((a, b) => plain.indexOf(a).compareTo(plain.indexOf(b)));

  var colorIndex = 0;
  final lines = <String>[];
  for (final p in chosen) {
    if (p == stateful) {
      final value = _sample(p, pick: p.type == 'color' ? colorIndex++ : 0);
      lines
        ..add('${p.key}:')
        ..add('  default: $value');
      if (p.type == 'color') {
        lines
          ..add('  hovered:')
          ..add(r'    color: $colors.primary')
          ..add('    alpha: 90%')
          ..add('  disabled:')
          ..add(r'    color: $colors.on-surface')
          ..add('    alpha: 12%');
      } else {
        lines
          ..add('  hovered: $value')
          ..add('  disabled: $value');
      }
    } else {
      final value = _sample(p, pick: p.type == 'color' ? colorIndex++ : 0);
      lines.add('${p.key}: $value');
    }
  }
  final parts = c.path.split('.');
  final b = StringBuffer();
  var indent = 0;
  for (final part in parts) {
    b.writeln('${'  ' * indent}$part:');
    indent++;
  }
  for (final line in lines) {
    b.writeln('${'  ' * indent}$line');
  }
  return b.toString();
}

// ---------------------------------------------------------------------
// The properties table
// ---------------------------------------------------------------------

const _valueHints = <String, String>{
  'color':
      r'`#RRGGBB`, a color name, `$colors.primary`, or an object `{ color, '
      'mix, alpha }`',
  'elevation': '`level0` to `level5`, or a number',
  'number': 'a number',
  'whole number': 'a whole number',
  'true / false': '`true`, `false`',
  'insets': '`16`, `h, v`, `l, t, r, b`, or a map',
  'shape': 'a token (`small`), a radius, or a map',
  'corner radius': 'a token (`medium`) or a number',
  'text style': 'a style name (`title-large`) or a map',
  'icon theme': 'a color, or a map of `color`, `size`, ...',
  'size': '`width, height`, one number, or a map',
  'constraints':
      'a map of `min-width`, `max-width`, `min-height`, '
      '`max-height`',
  'border side': '`none`, or a map of `color`, `width`, `style`',
  'mouse cursor': '`click`, `basic`, `forbidden`, `text`, ...',
  'alignment': '`center`, `top-left`, ..., or `x, y`',
  'offset': '`x, y`',
  'visual density':
      '`standard`, `compact`, `comfortable`, `adaptive`, or '
      '`h, v`',
  'duration': '`250ms`, `1s`',
  'decoration': 'a color, or a map of `color`, `radius`, `border`, `shape`',
  'input border': '`outline`, `underline`, or a map',
  'animation': 'a map of `duration`, `reverse-duration`',
};

String _values(_Property p) => p.type == 'choice'
    ? p.values.map((v) => '`$v`').join(', ')
    : _valueHints[p.type] ?? '';

String _cell(String text) => text.replaceAll('|', r'\|').replaceAll('\n', ' ');

String _table(_Component c) {
  final withDefault = c.properties.any((p) => p.defaultValue != _baseDefault);
  final head = [
    'Property',
    'Type',
    'Values',
    'States',
    'What it does',
    'Flutter field',
    if (withDefault) 'Default',
  ];
  final lines = [
    '| ${head.join(' | ')} |',
    '|${List.filled(head.length, '---').join('|')}|',
  ];
  for (final p in c.properties) {
    final cells = [
      '`${p.key}`',
      p.type,
      _values(p),
      p.states ? 'yes' : 'no',
      p.description,
      '`${p.field}`',
      if (withDefault) p.defaultValue,
    ];
    lines.add('| ${cells.map(_cell).join(' | ')} |');
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------------
// The index
// ---------------------------------------------------------------------

String _index(List<_Component> components, String flutterVersion) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('title: "Component themes in YAML — Spring for Dart"')
    ..writeln(
      'description: "Every Flutter Material component you can style from '
      'YAML: app bar, buttons, cards, dialogs, inputs and more, with all '
      'their properties."',
    )
    ..writeln('slug: /docs/flutter/theme/components')
    ..writeln('section: Flutter / Theme / Components')
    ..writeln('order: 0')
    ..writeln(
      'keywords: [flutter, theme, yaml, components, material, widgets]',
    )
    ..writeln('---')
    ..writeln()
    ..writeln('# Component themes in YAML')
    ..writeln()
    ..writeln(
      'Each Material component has a theme in Flutter: the look every '
      'widget of that kind starts from. $_materialStarter reads them from '
      '`spring.flutter.theme.components.<name>`, with the same names and '
      'values as Flutter, in kebab case (`background-color` for '
      '`backgroundColor`). Pick a component below to see all its '
      'properties, what they do and an example.',
    )
    ..writeln()
    ..writeln(
      'An app needs the Material starter in its dependencies to show them: '
      'without it the `components` of a theme are accepted, not checked and '
      'not shown, and a line of the log names the package. The last row is '
      'not a Material component: '
      '${_cupertinoStarter.replaceFirst('The', 'the')} reads '
      '`spring.flutter.theme.cupertino` in the same way.',
    )
    ..writeln()
    ..writeln('| Component | Flutter class | What it styles | Properties |')
    ..writeln('|---|---|---|---|');
  for (final c in components) {
    final link = c.ownRoot
        ? '[${c.title}](../cupertino.md)'
        : '[${c.title}](${c.name}.md)';
    b.writeln(
      '| $link | `${c.flutterClass}` | ${_cell(c.description)} | '
      '${c.properties.length} |',
    );
  }
  b
    ..writeln()
    ..writeln('## See also')
    ..writeln()
    ..writeln('- [Theme overview](../index.md)')
    ..writeln('- [Root theme properties](../properties.md)')
    ..writeln('- [Styles and states](../styles-and-states.md)')
    ..writeln('- [Colors](../colors.md)')
    ..writeln('- [Cupertino](../cupertino.md)')
    ..writeln()
    ..writeln('---')
    ..writeln()
    ..writeln(_footer(flutterVersion));
  return b.toString();
}

// ---------------------------------------------------------------------
// The table of docs/configuration.md
// ---------------------------------------------------------------------

/// The reference table: a row per component, its properties grouped by
/// the type of their value, `*` after those that take a value per state,
/// the options of choices in parentheses. The test of the starter
/// (test/theme_reference_test.dart) builds the same text from the reader.
String _reference(List<_Component> components) {
  final lines = [
    '| Component | Properties, by the type of their value |',
    '|---|---|',
  ];
  for (final c in components) {
    final groups = <String, List<_Property>>{};
    for (final p in c.properties) {
      (groups[p.type] ??= []).add(p);
    }
    final cells = [
      for (final MapEntry(key: type, value: list) in groups.entries)
        '**$type** ${list.map(_describe).join(', ')}',
    ];
    final name = c.ownRoot
        ? '[`${c.name}`](flutter/theme/cupertino.md) (own root)'
        : '[`${c.name}`](flutter/theme/components/${c.name}.md)';
    lines.add('| $name | ${cells.join('<br>')} |');
  }
  return lines.join('\n');
}

String _describe(_Property p) {
  final options = p.type == 'choice' ? ' (${p.values.join(' / ')})' : '';
  return '`${p.key}`${p.states ? '*' : ''}$options';
}

void _updateConfiguration(List<_Component> components) {
  final file = File('../docs/configuration.md');
  final text = file.readAsStringSync();
  final from = text.indexOf(_start);
  final to = text.indexOf(_end);
  if (from < 0 || to < from) {
    stderr.writeln('docs/configuration.md lacks the theme-components markers');
    exit(1);
  }
  final next = text.replaceRange(
    from,
    to,
    '$_start\n\n${_reference(components)}\n\n',
  );
  if (next != text) {
    file.writeAsStringSync(next);
  }
}
