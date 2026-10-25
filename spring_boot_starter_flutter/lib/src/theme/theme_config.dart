import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// The theme properties (`spring.flutter.theme.*`) as named themes:
/// the shared part at the root, each theme of `themes.<name>` on top of
/// it (and of the theme it `extends`), and which one is active.
///
/// Keys are kept relative to `spring.flutter.theme` and canonical
/// (`seed-color`, `seedColor` → `seedcolor`); list entries are indexed
/// (`typography.fontfamilyfallback.0`) or one comma-separated value.
final class ThemeConfig {
  /// The config of [properties] (relative keys in any form, as a `Binder`
  /// gives them).
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

  /// The theme shown now: `system` or a theme name.
  String active = 'system';

  /// The theme `system` shows when the device is in light mode.
  String systemLight = 'light';

  /// The theme `system` shows when the device is in dark mode.
  String systemDark = 'dark';

  final _base = <String, String>{};
  final _own = <String, Map<String, String>>{};
  final _displayNames = <String, String>{'light': 'light', 'dark': 'dark'};

  /// Every theme: `light` and `dark`, then the others by name (property
  /// sources, imported files included, have no meaningful order).
  late final List<String> names = List.unmodifiable([
    'light',
    'dark',
    ...[
      for (final name in _own.keys)
        if (name != 'light' && name != 'dark') name,
    ]..sort(),
  ]);

  /// The name of the theme [name] stands for (ignoring case and `-`), or
  /// `null`.
  String? nameOf(String name) => _displayNames[ThemeValues.canonical(name)];

  /// The properties of theme [name]: Material's brightness for `light` /
  /// `dark`, the shared part, the theme it extends, its own.
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

/// Reads a resolved theme's properties: values by path, lists, and the
/// full property name for messages.
final class ThemeProperties {
  /// The properties [values] of theme [name].
  ThemeProperties(this.name, this.values);

  /// The theme's name.
  final String name;

  /// Canonical relative path → value.
  final Map<String, String> values;

  /// The value at [path] (canonical), or `null`.
  String? operator [](String path) {
    final value = values[path]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// The list at [path]: indexed entries, else one comma-separated value.
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

  /// The direct children of [path] (`components` → `card`, `appbar`, ...).
  Set<String> children(String path) => {
    for (final key in values.keys)
      if (key.startsWith('$path.'))
        key.substring(path.length + 1).split('.').first,
  };

  /// Reads [path] with [parse]; throws a [ThemePropertyException] naming
  /// the property when the value cannot be read.
  T? read<T>(String path, T? Function(String value) parse, String expected) {
    final value = this[path];
    if (value == null) {
      return null;
    }
    return parse(value) ??
        (throw ThemePropertyException(propertyName(path), value, expected));
  }

  /// The property's name as written in files, for messages.
  String propertyName(String path) => name == 'light' || name == 'dark'
      ? 'spring.flutter.theme.$path (theme $name)'
      : 'spring.flutter.theme.themes.$name.$path';
}
