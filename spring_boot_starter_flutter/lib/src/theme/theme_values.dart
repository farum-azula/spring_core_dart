import 'dart:ui' show Color, FontWeight;

import 'package:flutter/animation.dart' show Cubic;
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
  /// A color from a `Colors` name (`deepPurple`, `deepPurple.shade200`,
  /// `black54`) or from `#RGB`, `#RRGGBB`, `#AARRGGBB` (also
  /// `0xAARRGGBB`); `null` otherwise.
  static Color? color(String value) {
    final text = value.trim();
    final hex = text.startsWith('#')
        ? text.substring(1)
        : text.toLowerCase().startsWith('0x')
        ? text.substring(2)
        : null;
    if (hex != null) {
      final argb = switch (hex.length) {
        3 => 'FF${hex.split('').map((c) => '$c$c').join()}',
        6 => 'FF$hex',
        8 => hex,
        _ => null,
      };
      final parsed = argb == null ? null : int.tryParse(argb, radix: 16);
      return parsed == null ? null : Color(parsed);
    }
    return materialColors[text] ?? materialColors[_camel(text)];
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

  /// A number (`12`, `1.5`); `null` otherwise.
  static double? number(String value) => double.tryParse(value.trim());

  /// A duration from `250ms`, `1s`, `1.5s`, or plain milliseconds; `null`
  /// otherwise.
  static Duration? duration(String value) {
    final text = value.trim().toLowerCase();
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(ms|s)?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final amount = double.parse(match[1]!);
    final ms = match[2] == 's' ? amount * 1000 : amount;
    return Duration(microseconds: (ms * 1000).round());
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
