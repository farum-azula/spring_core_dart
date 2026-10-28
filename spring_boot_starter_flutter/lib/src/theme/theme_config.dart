import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The theme properties (`spring.flutter.theme.*`) sorted into named
/// themes: the shared part at the root, each theme of `themes.<name>` on
/// top of it (or of the theme it `extends`), and which theme is active.
///
/// `SpringThemes` builds one from the properties and makes each theme from
/// it; apps do not use it. Keys are kept relative to
/// `spring.flutter.theme` and canonical (`seed-color` and `seedColor` both
/// become `seedcolor`); list entries are indexed
/// (`typography.fontfamilyfallback.0`) or one comma-separated value.
final class ThemeConfig {
  /// Sorts [properties], whose keys are relative to `spring.flutter.theme`
  /// in any form (as a `Binder` gives them).
  ThemeConfig(Map<String, String> properties) {
    for (final MapEntry(:key, :value) in properties.entries) {
      final segments = key.split('.');
      if (segments.length >= 3 &&
          ThemeValues.canonical(segments[0]) == 'themes') {
        final name = segments[1];
        final canonicalName = ThemeValues.canonical(name);
        final display = _displayNames.putIfAbsent(canonicalName, () => name);
        _own.putIfAbsent(display, () => {})[_canonicalPath(segments.skip(2))] =
            value;
        continue;
      }
      final path = _canonicalPath(segments);
      switch (path) {
        case 'active':
          active = value.trim();
        case 'systemlight':
          systemLight = value.trim();
        case 'systemdark':
          systemDark = value.trim();
        default:
          _base[path] = value;
      }
    }
  }

  /// The theme to show at the start, from `active`: `system` (the default)
  /// or a theme name.
  String active = 'system';

  /// The theme `system` shows when the device is in light mode, from
  /// `system-light`; `light` by default.
  String systemLight = 'light';

  /// The theme `system` shows when the device is in dark mode, from
  /// `system-dark`; `dark` by default.
  String systemDark = 'dark';

  final _base = <String, String>{};
  final _own = <String, Map<String, String>>{};
  final _displayNames = <String, String>{'light': 'light', 'dark': 'dark'};

  /// The names of every theme: `light` and `dark`, then the others in
  /// alphabetical order (property sources, imported files included, have
  /// no meaningful order).
  late final List<String> names = List.unmodifiable([
    'light',
    'dark',
    ...[
      for (final name in _own.keys)
        if (name != 'light' && name != 'dark') name,
    ]..sort(),
  ]);

  /// The theme's name as first declared, for [name] in any case or with
  /// `-` and `_`; `null` when there is no such theme.
  String? nameOf(String name) => _displayNames[ThemeValues.canonical(name)];

  /// The properties of theme [name], each layer over the previous one: the
  /// brightness (`dark` for the `dark` theme, else `light`), the shared
  /// part or the theme it extends, then its own. A list in a later layer
  /// replaces the whole list. Throws an `ArgumentError` for an unknown
  /// name, and a `StateError` for an `extends` cycle or unknown parent.
  Map<String, String> resolve(String name) => _resolve(
    nameOf(name) ??
        (throw ArgumentError.value(
          name,
          'name',
          'no such theme; one of ${names.join(', ')}',
        )),
    [],
  );

  Map<String, String> _resolve(String name, List<String> chain) {
    if (chain.contains(name)) {
      throw StateError(
        'The themes extend each other in a cycle: '
        '${[...chain, name].join(' → ')} (spring.flutter.theme.themes.*.extends).',
      );
    }
    final own = _own[name] ?? const {};
    final parentName = own['extends']?.trim();
    final result = <String, String>{
      'brightness': name == 'dark' ? 'dark' : 'light',
    };
    if (parentName != null && parentName.isNotEmpty) {
      final parent = nameOf(parentName);
      if (parent == null) {
        throw StateError(
          "Theme '$name' extends '$parentName', which is no theme; one of "
          '${names.where((n) => n != name).join(', ')}.',
        );
      }
      _merge(result, _resolve(parent, [...chain, name]));
    } else {
      _merge(result, _base);
    }
    _merge(result, {
      for (final MapEntry(:key, :value) in own.entries)
        if (key != 'extends') key: value,
    });
    return result;
  }

  static String _canonicalPath(Iterable<String> segments) =>
      segments.map(ThemeValues.canonical).join('.');

  static final _indexed = RegExp(r'^(.*)\.(\d+)$');

  // Puts [source] over [target]; a list in [source] (indexed entries or one
  // comma-separated value) replaces the whole list of [target].
  static void _merge(Map<String, String> target, Map<String, String> source) {
    final replaced = <String>{};
    for (final key in source.keys) {
      final list = _indexed.firstMatch(key)?.group(1) ?? key;
      if (replaced.add(list)) {
        target.removeWhere(
          (existing, _) =>
              existing == list ||
              _indexed.firstMatch(existing)?.group(1) == list,
        );
      }
    }
    target.addAll(source);
  }
}

/// The resolved properties of one theme, with the helpers that read them:
/// values by path, lists, child keys, parsed values, and the full property
/// name for error messages. Internal to the starter.
final class ThemeProperties {
  /// The resolved [values] of theme [name].
  ThemeProperties(this.name, this.values);

  /// The theme's name, used in error messages.
  final String name;

  /// The values by canonical path relative to the theme
  /// (`components.card.shape`).
  final Map<String, String> values;

  /// The trimmed value at the canonical [path]; `null` when missing or
  /// empty.
  String? operator [](String path) {
    final value = values[path]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// The list at [path]: the indexed entries in order, else one
  /// comma-separated value split; empty items are dropped, and `null` when
  /// there is neither.
  List<String>? list(String path) {
    final indexed = <int, String>{};
    for (final MapEntry(:key, :value) in values.entries) {
      if (key.startsWith('$path.')) {
        final index = int.tryParse(key.substring(path.length + 1));
        if (index != null) {
          indexed[index] = value.trim();
        }
      }
    }
    if (indexed.isNotEmpty) {
      return [
        for (final index in indexed.keys.toList()..sort())
          if (indexed[index]!.isNotEmpty) indexed[index]!,
      ];
    }
    final value = this[path];
    return value == null
        ? null
        : [
            for (final part in value.split(','))
              if (part.trim().isNotEmpty) part.trim(),
          ];
  }

  /// The names directly below [path]; for `components`, `card`, `appbar`
  /// and so on.
  Set<String> children(String path) => {
    for (final key in values.keys)
      if (key.startsWith('$path.'))
        key.substring(path.length + 1).split('.').first,
  };

  /// The value at [path] parsed with [parse]; `null` when there is none.
  /// Throws a [ThemePropertyException] naming the property and [expected]
  /// when [parse] cannot read it.
  T? read<T>(String path, T? Function(String value) parse, String expected) {
    final value = this[path];
    if (value == null) {
      return null;
    }
    return parse(value) ??
        (throw ThemePropertyException(propertyName(path), value, expected));
  }

  /// The full name of the property at [path] as written in files, for
  /// error messages; the shared part's properties also name the theme.
  String propertyName(String path) => name == 'light' || name == 'dark'
      ? 'spring.flutter.theme.$path (theme $name)'
      : 'spring.flutter.theme.themes.$name.$path';
}
