import 'package:spring_boot_starter_flutter/theme_design.dart'
    show ThemeProperty;

import 'theme_catalog.dart';

/// The component reference of `docs/configuration.md`, as Markdown made
/// from the mapping itself: a row per component, its properties grouped
/// by the type of their value, `*` after those that take a value per
/// state, the options of enums in parentheses, the name linking to the
/// component's page (tool/theme_docs.dart writes the same table).
String themeReference() {
  final lines = [
    '| Component | Properties, by the type of their value |',
    '|---|---|',
  ];
  for (final MapEntry(:key, :value) in themeCatalog().entries) {
    final groups = <String, List<ThemeProperty>>{};
    for (final property in value) {
      final kind = property.kind.startsWith('one of: ')
          ? 'choice'
          : property.kind;
      (groups[kind] ??= []).add(property);
    }
    final cells = [
      for (final MapEntry(key: kind, value: properties) in groups.entries)
        '**$kind** ${properties.map(_describe).join(', ')}',
    ];
    final name = key == 'cupertino'
        ? '[`cupertino`](flutter/theme/cupertino.md) (own root)'
        : '[`$key`](flutter/theme/components/$key.md)';
    lines.add('| $name | ${cells.join('<br>')} |');
  }
  return lines.join('\n');
}

String _describe(ThemeProperty p) {
  final options = p.kind.startsWith('one of: ')
      ? ' (${p.kind.substring(8).replaceAll(' | ', ' / ')})'
      : '';
  return '`${p.name}`${p.states ? '*' : ''}$options';
}
