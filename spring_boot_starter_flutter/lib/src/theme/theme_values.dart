import 'dart:ui' show Color, FontWeight;

import 'package:flutter/animation.dart' show Cubic, Curve, Curves;
import 'package:flutter/material.dart' show Easing;
import 'package:spring_boot_starter_flutter/src/theme/material_colors.dart';

/// The error thrown when a theme property has a value (or a key) that
/// cannot be read, such as `seed-color: purpel` or `seed-colour`.
///
/// The themes are read when the application starts, so this error fails
/// the start, and `SpringApplicationWidget` shows it on the failure
/// screen. Its message names the property, the value and what the value
/// may be, for example: `Invalid theme property
/// spring.flutter.theme.seed-color: 'purpel'; expected a Colors name ...`.
/// `SpringThemes.load` throws it too, for themes loaded at run time; catch
/// it there to keep the app's current themes.
final class ThemePropertyException implements Exception {
  /// The error for property [key] with [value], which is not [expected].
  ThemePropertyException(this.key, this.value, this.expected);

  /// The full property name, such as
  /// `spring.flutter.theme.themes.ocean.seed-color`.
  final String key;

  /// The value found in the properties.
  final String value;

  /// What the value may be, in words.
  final String expected;

  @override
  String toString() =>
      "Invalid theme property $key: '$value'; expected $expected.";
}

/// Parses the text values of theme properties: colors, weights, numbers,
/// durations, curves, booleans and enum names. Each parser returns `null`
/// for a value it cannot read, and the caller reports it as a
/// `ThemePropertyException`. Internal to the starter.
abstract final class ThemeValues {
  /// A plain color from a `Colors` name (`deepPurple`, `deepPurple.shade200`,
  /// `black54`, `white`, `black`, `transparent`) or from `#RGB`, `#RRGGBB`,
  /// `#AARRGGBB`; `null` otherwise. A color changed by `mix` or `alpha` is
  /// an object, read by `ThemeProperties.color`.
  static Color? color(String value) {
    final text = value.trim();
    if (text.startsWith('#')) {
      final hex = text.substring(1);
      final argb = switch (hex.length) {
        3 => 'FF${hex.split('').map((c) => '$c$c').join()}',
        6 => 'FF$hex',
        8 => hex,
        _ => null,
      };
      final parsed = argb != null && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)
          ? int.tryParse(argb, radix: 16)
          : null;
      return parsed == null ? null : Color(parsed);
    }
    return materialColors[text] ?? materialColors[_camel(text)];
  }

  /// A share from `0%` to `100%` or from `0` to `1`, as a number from 0
  /// to 1 (`12%` and `0.12` are the same); `null` otherwise.
  static double? percent(String value) {
    final text = value.trim();
    final isPercent = text.endsWith('%');
    final number = ThemeValues.number(
      isPercent ? text.substring(0, text.length - 1) : text,
    );
    if (number == null || number.isNaN || number.isInfinite) {
      return null;
    }
    final share = isPercent ? number / 100 : number;
    return share < 0 || share > 1 ? null : share;
  }

  /// A font weight from `100` … `900`, or `thin`, `extra-light`, `light`,
  /// `normal` / `regular`, `medium`, `semibold`, `bold`, `extra-bold`,
  /// `black`; `null` otherwise.
  static FontWeight? weight(String value) {
    final text = value.trim().toLowerCase().replaceAll(RegExp('[-_ ]'), '');
    final number = int.tryParse(text);
    if (number != null) {
      return number % 100 == 0 && number >= 100 && number <= 900
          ? FontWeight.values[number ~/ 100 - 1]
          : null;
    }
    return switch (text) {
      'thin' => FontWeight.w100,
      'extralight' => FontWeight.w200,
      'light' => FontWeight.w300,
      'normal' || 'regular' => FontWeight.w400,
      'medium' => FontWeight.w500,
      'semibold' => FontWeight.w600,
      'bold' => FontWeight.w700,
      'extrabold' => FontWeight.w800,
      'black' => FontWeight.w900,
      _ => null,
    };
  }

  static final _numberPattern = RegExp(
    r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$',
  );
  static final _durationPattern = RegExp(
    r'^(\d+(?:\.\d+)?|\.\d+)\s*(ms|s|m|h|d)$',
    caseSensitive: false,
  );

  /// A number (`12`, `-3`, `+5`, `.5`, `1.5`, `1e3`, `Infinity`); `null`
  /// otherwise. Hex (`0x10`) and `NaN` are no numbers.
  static double? number(String value) {
    final text = value.trim();
    if (text.toLowerCase() == 'infinity') {
      return double.infinity;
    }
    return _numberPattern.hasMatch(text) ? double.tryParse(text) : null;
  }

  /// A duration from `250ms`, `250 ms`, `4s`, `1.5s`, `2m`, `1h`, `0.5d`
  /// (units `ms`, `s`, `m`, `h`, `d`, in any case; decimals allowed), or
  /// plain milliseconds; `null` otherwise. The one duration syntax of the
  /// theme: motion, animations, styles, tokens, `transition`, `refresh`
  /// and `timeout`.
  static Duration? duration(String value) {
    final text = value.trim();
    final match = _durationPattern.firstMatch(text);
    if (match == null) {
      final plain = RegExp(r'^(\d+(?:\.\d+)?|\.\d+)$').hasMatch(text);
      final ms = plain ? double.tryParse(text) : null;
      return ms == null ? null : Duration(microseconds: (ms * 1000).round());
    }
    final amount = double.parse(match[1]!);
    final unit = match[2]!.toLowerCase();
    final ms = switch (unit) {
      's' => amount * 1000,
      'm' => amount * 60000,
      'h' => amount * 3600000,
      'd' => amount * 86400000,
      _ => amount,
    };
    return Duration(microseconds: (ms * 1000).round());
  }

  /// The numbers of insets written as a comma separated list (`12, 6`,
  /// two or four of them are valid insets); `null` when [value] is no list
  /// of at least two numbers.
  static List<double>? numberList(String value) {
    if (!value.contains(',')) {
      return null;
    }
    final numbers = [
      for (final part in value.split(',')) number(part),
    ];
    return numbers.contains(null) ? null : [for (final n in numbers) n!];
  }

  /// How a theme value reads, by what it looks like: `number`, `duration`
  /// (a number with a unit), `insets` (a comma separated list of numbers),
  /// `color`, else `text`. The fixture `test/fixtures/theme_value_kinds.yaml`
  /// is the truth of it; the generator mirrors the same rules.
  static String kindOf(String value) {
    if (number(value) != null) {
      return 'number';
    }
    if (_durationPattern.hasMatch(value.trim())) {
      return 'duration';
    }
    if (numberList(value) != null) {
      return 'insets';
    }
    return color(value) != null ? 'color' : 'text';
  }

  /// A curve from four numbers, `0.2, 0, 0, 1`: a cubic Bézier curve, like
  /// CSS `cubic-bezier`; `null` otherwise.
  static Cubic? curve(String value) {
    final parts = [
      for (final part in value.split(',')) double.tryParse(part.trim()),
    ];
    if (parts.length != 4 || parts.contains(null)) {
      return null;
    }
    return Cubic(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }

  /// A curve: a name (`linear`, `ease`, `ease-in`, `ease-out`,
  /// `ease-in-out`, `fast-out-slow-in`, `decelerate`, `standard`,
  /// `emphasized`, `bounce-out`, ... see [curveNames]) or four numbers
  /// ([curve]); `null` otherwise.
  static Curve? anyCurve(String value) =>
      _namedCurves[canonical(value)] ?? curve(value);

  /// The names [anyCurve] knows, in kebab case.
  static List<String> get curveNames => List.unmodifiable(_curveNames.keys);

  static final _curveNames = <String, Curve>{
    'linear': Curves.linear,
    'ease': Curves.ease,
    'ease-in': Curves.easeIn,
    'ease-out': Curves.easeOut,
    'ease-in-out': Curves.easeInOut,
    'fast-out-slow-in': Curves.fastOutSlowIn,
    'decelerate': Curves.decelerate,
    'standard': Easing.standard,
    'standard-accelerate': Easing.standardAccelerate,
    'standard-decelerate': Easing.standardDecelerate,
    'emphasized': const Cubic(0.2, 0, 0, 1),
    'emphasized-accelerate': Easing.emphasizedAccelerate,
    'emphasized-decelerate': Easing.emphasizedDecelerate,
    'ease-in-sine': Curves.easeInSine,
    'ease-out-sine': Curves.easeOutSine,
    'ease-in-out-sine': Curves.easeInOutSine,
    'ease-in-cubic': Curves.easeInCubic,
    'ease-out-cubic': Curves.easeOutCubic,
    'ease-in-out-cubic': Curves.easeInOutCubic,
    'ease-in-back': Curves.easeInBack,
    'ease-out-back': Curves.easeOutBack,
    'ease-in-out-back': Curves.easeInOutBack,
    'bounce-in': Curves.bounceIn,
    'bounce-out': Curves.bounceOut,
    'bounce-in-out': Curves.bounceInOut,
    'elastic-in': Curves.elasticIn,
    'elastic-out': Curves.elasticOut,
    'elastic-in-out': Curves.elasticInOut,
  };

  static final _namedCurves = {
    for (final entry in _curveNames.entries) canonical(entry.key): entry.value,
  };

  /// `true` or `false`, in any case; `null` otherwise.
  static bool? boolean(String value) => switch (value.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  /// The one of [values] whose name matches [value], ignoring case, `-`
  /// and `_` (`tonal-spot` gives `tonalSpot`); `null` when none does.
  static T? enumValue<T extends Enum>(List<T> values, String value) {
    final wanted = canonical(value);
    for (final candidate in values) {
      if (canonical(candidate.name) == wanted) {
        return candidate;
      }
    }
    return null;
  }

  /// A key or name in its canonical form: lower case, without `-` and `_`,
  /// so `seed-color`, `seedColor` and `SEED_COLOR` are the same key.
  static String canonical(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  static String _camel(String name) =>
      name.replaceAllMapped(RegExp('[-_]([a-z])'), (m) => m[1]!.toUpperCase());
}
