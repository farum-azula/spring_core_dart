import 'dart:ui' show Color;

import 'package:flutter/material.dart'
    show Brightness, ColorScheme, DynamicSchemeVariant;
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart'
    show didYouMean;
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

/// Resolves the references of a theme's values: `$colors.primary` becomes
/// the value declared at `colors.primary`. Internal to the starter.
///
/// - A path starts at the theme's root (`$spacing.m`,
///   `$motion.durations.fast`, `$tokens.neon.yellow`); a token path may
///   drop `tokens.` when its first segment is no root section
///   (`$neon.yellow`).
/// - A reference stands for the declared text of that value. A list is
///   referenced as its items joined by commas, a color object
///   (`{ color, mix, alpha }`) as the color it makes (`#AARRGGBB`).
/// - A Material color role or a shape the theme does not declare can be
///   referenced too: `$colors.outline` is the role of the palette the
///   theme's seed-color, brightness, scheme-variant and contrast make
///   (the declared `colors.*` do not change the other roles), and
///   `$shape.extra-small` is Material 3's corner radius. A declared value
///   wins.
/// - Values under `headers` and `syntax` (regular expressions), the
///   image keys `source`, `fallback` and `source-sha256` and the `glyphs`
///   of a text change are left as they are: no reference, and `$$` stays `$$` (a secret from a placeholder
///   may hold a `$`).
/// - `$$` is a literal `$`. `${...}` is Spring's placeholder and is left
///   to the `Environment`; `$` followed by anything but a letter is text.
/// - A cycle or an unknown path throws a [ThemePropertyException] with the
///   chain or a "did you mean".
abstract final class ThemeReferences {
  static final _reference = RegExp(
    r'\$\$|\$([A-Za-z][A-Za-z0-9_.\-]*)',
  );

  /// The [values] of theme [name] with every reference replaced.
  static Map<String, String> resolve(String name, Map<String, String> values) {
    if (!values.values.any((value) => value.contains(r'$'))) {
      return values;
    }
    final context = _Context(name, values);
    return {
      for (final MapEntry(:key, :value) in values.entries)
        key: context.value(key, value, const []),
    };
  }
}

final class _Context {
  _Context(this.name, this.values)
    : properties = ThemeProperties(name, values),
      roots = {
        for (final key in SpringThemeData.themeProperties)
          ThemeValues.canonical(key),
      };

  final String name;
  final Map<String, String> values;
  final ThemeProperties properties;
  final Set<String> roots;
  final _done = <String, String>{};

  // The resolved text of the value at [key], written as [raw]; [chain] is
  // the keys being resolved, for a cycle.
  String value(String key, String raw, List<String> chain) {
    final done = _done[key];
    if (done != null) {
      return done;
    }
    if (!raw.contains(r'$') || _literal(key)) {
      return raw;
    }
    if (chain.contains(key)) {
      throw ThemePropertyException(
        properties.propertyName(chain.first),
        values[chain.first] ?? '',
        'no reference cycle: ${[...chain.skip(chain.indexOf(key)), key].join(' → ')}',
      );
    }
    final next = [...chain, key];
    final text = raw.replaceAllMapped(ThemeReferences._reference, (match) {
      final path = match[1];
      if (path == null) {
        return r'$';
      }
      // A `$` closing a sentence or a name is not part of the path.
      final trimmed = path.replaceAll(RegExp(r'[.\-]+$'), '');
      final tail = path.substring(trimmed.length);
      return '${_target(key, trimmed, next)}$tail';
    });
    return _done[key] = text;
  }

  // Request headers and the image sources are not theme text: a `$` in a
  // secret that came from a placeholder must stay as it is (`$$` too).
  static const _literalLast = {
    'source',
    'fallback',
    'sourcesha256',
    'glyphs',
  };

  static bool _literal(String key) {
    final segments = key.split('.');
    return segments.first == 'syntax' ||
        segments.contains('headers') ||
        _literalLast.contains(segments.last);
  }

  String _target(String key, String path, List<String> chain) {
    final canonical = path.split('.').map(ThemeValues.canonical).join('.');
    final found =
        _find(canonical) ??
        _computed(canonical) ??
        _find(_tokenPath(canonical));
    if (found == null) {
      throw ThemePropertyException(
        properties.propertyName(key),
        values[key] ?? '',
        _unknown(canonical),
      );
    }
    return found(chain);
  }

  String _tokenPath(String path) =>
      roots.contains(path.split('.').first) ? path : 'tokens.$path';

  // A way to the resolved text of [path], or `null` when it declares
  // nothing.
  String Function(List<String> chain)? _find(String path) {
    if (values.containsKey(path)) {
      return (chain) => value(path, values[path]!, chain);
    }
    if (_isColorObject(path)) {
      return (chain) => _object(path, chain);
    }
    final items = <int, String>{};
    for (final key in values.keys) {
      if (key.startsWith('$path.')) {
        final index = int.tryParse(key.substring(path.length + 1));
        if (index != null) {
          items[index] = key;
        }
      }
    }
    if (items.isEmpty) {
      return null;
    }
    return (chain) => [
      for (final index in items.keys.toList()..sort())
        value(items[index]!, values[items[index]]!, chain).trim(),
    ].join(', ');
  }

  // Whether [path] is a color object: a `color` with only `mix` and
  // `alpha` next to it.
  bool _isColorObject(String path) {
    final kids = {
      for (final key in values.keys)
        if (key.startsWith('$path.'))
          key.substring(path.length + 1).split('.').first,
    };
    return kids.contains('color') &&
        kids.every(const {'color', 'mix', 'alpha'}.contains);
  }

  // The color the object at [path] makes, as `#AARRGGBB`; its own
  // references are resolved first.
  String _object(String path, List<String> chain) {
    final resolved = {
      for (final MapEntry(:key, :value) in values.entries)
        if (key.startsWith('$path.')) key: this.value(key, value, chain),
    };
    return _hex(ThemeProperties(name, resolved).colorObject(path));
  }

  static String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

  // The palette without the declared roles, built once from the theme's
  // own seed, brightness, variant and contrast.
  ColorScheme? _base;
  bool _building = false;

  String Function(List<String> chain)? _computed(String path) {
    final dot = path.indexOf('.');
    if (dot < 0) {
      return null;
    }
    final name = path.substring(dot + 1);
    switch (path.substring(0, dot)) {
      case 'colors' when colorRoles.contains(name) && !_building:
        return (chain) {
          return _hex(SpringThemeData.roleIn(_scheme(chain), name)!);
        };
      case 'shape' when m3ShapeScale.containsKey(name):
        return (_) {
          final radius = m3ShapeScale[name]!;
          return radius.isFinite && radius == radius.roundToDouble()
              ? '${radius.toInt()}'
              : '$radius';
        };
    }
    return null;
  }

  ColorScheme _scheme(List<String> chain) {
    if (_base case final base?) {
      return base;
    }
    // A seed that refers to an undeclared role would loop; the flag makes
    // that an unknown reference instead.
    _building = true;
    try {
      String? read(String key) =>
          values.containsKey(key) ? value(key, values[key]!, chain) : null;
      final seed =
          read('seedcolor') ??
          (_isColorObject('seedcolor') ? _object('seedcolor', chain) : null);
      final variant = read('schemevariant');
      final contrast = read('contrast');
      return _base = SpringThemeData.baseScheme(
        brightness:
            ThemeValues.enumValue(
              Brightness.values,
              read('brightness') ?? '',
            ) ??
            Brightness.light,
        seedColor: seed == null ? null : ThemeValues.color(seed),
        schemeVariant: variant == null
            ? null
            : ThemeValues.enumValue(DynamicSchemeVariant.values, variant),
        contrast: contrast == null ? null : ThemeValues.number(contrast),
      );
    } finally {
      _building = false;
    }
  }

  String _unknown(String path) {
    final tokenPath = _tokenPath(path);
    final paths = [
      for (final key in values.keys) key.replaceFirst(RegExp(r'\.\d+$'), ''),
      for (final role in colorRoles) 'colors.$role',
      for (final token in m3ShapeScale.keys) 'shape.$token',
    ];
    return "a declared value or a Material role or shape; '$path' is not "
        'one${didYouMean(tokenPath, paths)}';
  }
}
