import 'package:spring_core_dart_generator/src/material_color_names.dart';

/// How the text of a theme value is read, the same as the starter's
/// `ThemeValues` (its test fixture `theme_value_kinds.yaml` is the truth,
/// and a generator test checks every row of it).
abstract final class ThemeValueSyntax {
  /// The keys that start a theme: `$<root>.x` is a path from the root when
  /// the first segment is one of these (canonical form), else a token.
  static const rootSections = {
    'brightness', 'seedcolor', 'schemevariant', 'contrast', 'colors', //
    'typography', 'shape', 'elevation', 'spacing', 'visualdensity', //
    'taptargetsize', 'splash', 'motion', 'components', 'tokens', //
    'cupertino', 'styles', 'animations', 'background',
  };

  /// The keys of an image token, canonical: a token map with `source` and
  /// only these is an image.
  static const imageKeys = {
    'source', 'refresh', 'sourcesha256', 'headers', 'timeout', 'fallback', //
    'allowhttp',
  };

  static const _number = r'(?:\d+\.?\d*|\.\d+)';
  static final _numberPattern = RegExp(
    '^[+-]?$_number(?:[eE][+-]?\\d+)?\$|^infinity\$',
    caseSensitive: false,
  );
  static final _durationPattern = RegExp(
    '^$_number\\s*(?:ms|s|m|h|d)\$',
    caseSensitive: false,
  );
  static final _insetsPattern = RegExp(
    '^[+-]?$_number(?:\\s*,\\s*[+-]?$_number){1,3}\$',
  );

  /// Whether [value] (trimmed) is a number.
  static bool isNumber(String value) => _numberPattern.hasMatch(value);

  /// Whether [value] (trimmed) is a duration: `250ms`, `250 ms`, `1.5s`,
  /// `0.5d` (units ms, s, m, h, d).
  static bool isDuration(String value) => _durationPattern.hasMatch(value);

  /// Whether [value] (trimmed) is two or four numbers with commas.
  static bool isInsets(String value) =>
      _insetsPattern.hasMatch(value) &&
      const {2, 4}.contains(value.split(',').length);

  /// Whether [word] is a plain color: `#RGB`, `#RRGGBB`, `#AARRGGBB` or a
  /// `Colors` name. A color with changes is an object, not text.
  static bool isPlainColor(String word) {
    if (word.startsWith('#')) {
      final hex = word.substring(1);
      return const {3, 6, 8}.contains(hex.length) &&
          RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex);
    }
    final camel = word.replaceAllMapped(
      RegExp('[-_]([a-z])'),
      (m) => m[1]!.toUpperCase(),
    );
    return materialColorNames.contains(word) ||
        materialColorNames.contains(camel);
  }

  /// Whether [value] (trimmed) is a percent: `0%` to `100%` or `0` to `1`.
  static bool isPercent(String value) {
    final percent = value.endsWith('%');
    final text = percent ? value.substring(0, value.length - 1) : value;
    if (!_numberPattern.hasMatch(text) || text.toLowerCase() == 'infinity') {
      return false;
    }
    final number = double.tryParse(text);
    if (number == null || number.isNaN) {
      return false;
    }
    final share = percent ? number / 100 : number;
    return share >= 0 && share <= 1;
  }
}
