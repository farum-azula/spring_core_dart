import 'dart:ui' show Color;

import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_references.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show RemoteAddresses;

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
  ThemeConfig(
    Map<String, String> properties, {
    this.addresses = const RemoteAddresses(),
  }) {
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
        case 'source' || 'sourcesha256' || 'refresh':
          break;
        default:
          _base[path] = value;
      }
    }
  }

  /// Reads the addresses of the themes (sources, images): the
  /// application's resolvers, then the built-in ones.
  final RemoteAddresses addresses;

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
  /// replaces the whole list. Then the references (`$colors.primary`) are
  /// replaced by the values they name, so an extending theme that changes
  /// `colors.primary` changes what refers to it. Throws an `ArgumentError`
  /// for an unknown name, a `StateError` for an `extends` cycle or unknown
  /// parent, and a `ThemePropertyException` for a reference cycle or an
  /// unknown reference.
  Map<String, String> resolve(String name) {
    final resolved =
        nameOf(name) ??
        (throw ArgumentError.value(
          name,
          'name',
          'no such theme; one of ${names.join(', ')}',
        ));
    return ThemeReferences.resolve(resolved, _resolve(resolved, []));
  }

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
        if (!_notThemeKeys.contains(key)) key: value,
    });
    return result;
  }

  // Keys of a theme that are about where it comes from, not its look.
  static const _notThemeKeys = {
    'extends',
    'source',
    'sourcesha256',
    'refresh',
  };

  // The canonical path; the name right under a `headers` is kept as
  // written, as `X-Api-Key` must keep its dashes.
  static String _canonicalPath(Iterable<String> segments) {
    final out = <String>[];
    var afterHeaders = false;
    for (final segment in segments) {
      out.add(afterHeaders ? segment : ThemeValues.canonical(segment));
      afterHeaders = !afterHeaders && out.last == 'headers';
    }
    return out.join('.');
  }

  static final _indexed = RegExp(r'^(.*)\.(\d+)$');

  // In a style property (`styles.chip.fill`) a later layer's plain value,
  // list or map of states replaces one of another shape of an earlier
  // layer; maps of states merge state by state.
  static void _dropOtherShape(Map<String, String> target, String key) {
    final segments = key.split('.');
    if (segments.length < 3 || segments.first != 'styles') {
      return;
    }
    final property = segments.take(3).join('.');
    if (segments.length == 3) {
      target.removeWhere((existing, _) => existing.startsWith('$property.'));
      return;
    }
    final isItem = int.tryParse(segments[3]) != null;
    target.removeWhere((existing, _) {
      if (existing == property) {
        return true;
      }
      final other = existing.split('.');
      return other.length > 3 &&
          existing.startsWith('$property.') &&
          (int.tryParse(other[3]) != null) != isItem;
    });
  }

  // The tails of the keys of a color object.
  static const _objectTails = {'color', 'alpha', 'mix.with', 'mix.amount'};

  // A color object of [source] (a `color` with an `alpha` or a `mix`)
  // replaces the color of [target] whole, whatever its shape; so does a
  // plain color over an object.
  static void _dropOtherColor(
    Map<String, String> target,
    Map<String, String> source,
  ) {
    final roots = <String>{};
    for (final key in source.keys) {
      for (final tail in const ['alpha', 'mix.with', 'mix.amount']) {
        if (key.endsWith('.$tail')) {
          final root = key.substring(0, key.length - tail.length - 1);
          if (source.containsKey('$root.color') ||
              source.keys.any((k) => k.startsWith('$root.color.'))) {
            roots.add(root);
          }
        }
      }
      // A plain value over an object of the target.
      final prefix = '$key.';
      final below = [
        for (final existing in target.keys)
          if (existing.startsWith(prefix)) existing.substring(prefix.length),
      ];
      if (below.isNotEmpty && below.every(_objectTails.contains)) {
        roots.add(key);
      }
    }
    for (final root in roots) {
      target.removeWhere(
        (existing, _) => existing == root || existing.startsWith('$root.'),
      );
    }
  }

  // Puts [source] over [target]; a list in [source] (indexed entries or one
  // comma-separated value) replaces the whole list of [target].
  static void _merge(Map<String, String> target, Map<String, String> source) {
    _dropOtherColor(target, source);
    final replaced = <String>{};
    for (final key in source.keys) {
      _dropOtherShape(target, key);
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
  /// The resolved [values] of theme [name]; [addresses] reads its
  /// addresses (images).
  ThemeProperties(
    this.name,
    this.values, {
    this.addresses = const RemoteAddresses(),
  });

  /// Reads the addresses of the theme (an image's `source`).
  final RemoteAddresses addresses;

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

  /// What a color may be written as, for error messages.
  static const colorFormats =
      "a color: a Colors name like 'deepPurple.shade200', #RGB, #RRGGBB or "
      '#AARRGGBB, a \$ reference, or an object '
      '{ color, mix: { with, amount }, alpha }';

  static const _colorKeys = ['color', 'mix', 'alpha'];
  static const _mixKeys = ['with', 'amount'];

  /// The color at [path]: a plain value (a name, `#RRGGBB`, ...) or an
  /// object `{ color, mix: { with, amount }, alpha }`, where `mix` moves
  /// the color towards `with` by `amount` and then `alpha` sets the
  /// opacity. `null` when there is neither. Throws a
  /// [ThemePropertyException] for anything else, an unknown key included.
  Color? color(String path) {
    final raw = this[path];
    if (raw != null) {
      return ThemeValues.color(raw) ??
          (throw ThemePropertyException(propertyName(path), raw, colorFormats));
    }
    return children(path).isEmpty ? null : colorObject(path);
  }

  /// The colors of the list at [path]: indexed entries (each a color or an
  /// object) or one comma-separated value; `null` when there is neither.
  List<Color>? colorList(String path) {
    final indexes = <int>{
      for (final child in children(path)) ?int.tryParse(child),
    };
    if (indexes.isNotEmpty) {
      return [
        for (final index in indexes.toList()..sort()) color('$path.$index')!,
      ];
    }
    final items = list(path);
    return items == null
        ? null
        : [
            for (final item in items)
              ThemeValues.color(item) ??
                  (throw ThemePropertyException(
                    propertyName(path),
                    item,
                    colorFormats,
                  )),
          ];
  }

  /// The color object at [path], whose children are `color` (required),
  /// `mix` and `alpha`.
  Color colorObject(String path) {
    final kids = children(path);
    for (final kid in kids) {
      if (!_colorKeys.contains(kid)) {
        throw ThemePropertyException(
          propertyName('$path.$kid'),
          this['$path.$kid'] ?? '',
          'a key of a color object: ${_colorKeys.join(', ')}'
          '${didYouMean(kid, _colorKeys)}',
        );
      }
    }
    if (!kids.contains('color')) {
      throw ThemePropertyException(
        propertyName(path),
        '',
        "a color object with a 'color' (and optionally 'mix' and 'alpha')",
      );
    }
    var result = _need('$path.color', color);
    if (kids.contains('mix')) {
      final mix = '$path.mix';
      final mixKids = children(mix);
      for (final kid in mixKids) {
        if (!_mixKeys.contains(kid)) {
          throw ThemePropertyException(
            propertyName('$mix.$kid'),
            this['$mix.$kid'] ?? '',
            'a key of mix: ${_mixKeys.join(', ')}'
            '${didYouMean(kid, _mixKeys)}',
          );
        }
      }
      if (mixKids.length != 2) {
        throw ThemePropertyException(
          propertyName(mix),
          this[mix] ?? '',
          "mix as an object with 'with' (a color) and 'amount' (a percent)",
        );
      }
      final other = _need('$mix.with', color);
      final amount = _need('$mix.amount', percent);
      result = Color.lerp(result, other, amount)!;
    }
    if (kids.contains('alpha')) {
      result = result.withValues(alpha: _need('$path.alpha', percent));
    }
    return result;
  }

  // The value at [path], which must be there.
  T _need<T>(String path, T? Function(String path) at) =>
      at(path) ??
      (throw ThemePropertyException(propertyName(path), '', 'a value'));

  /// The share (0 to 1) at [path], written `12%` or `0.12`.
  double? percent(String path) => read(
    path,
    ThemeValues.percent,
    'a percent: 0% to 100%, or 0 to 1',
  );

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
