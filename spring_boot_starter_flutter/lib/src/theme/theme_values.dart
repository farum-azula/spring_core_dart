import 'dart:ui' show Color, FontWeight;

import 'package:flutter/animation.dart' show Cubic;
import 'package:spring_boot_starter_flutter/src/theme/material_colors.dart';

/// A theme property whose value cannot be read; the message names the
/// property, the value and what is expected.
final class ThemePropertyException implements Exception {
  /// The error for [key] (`spring.flutter.theme....`) with [value].
  ThemePropertyException(this.key, this.value, this.expected);

  /// The full property name.
  final String key;

  /// The value found.
  final String value;

  /// What the value may be.
  final String expected;

  @override
  String toString() =>
      "Invalid theme property $key: '$value'; expected $expected.";
}

/// Reads the values of theme properties.
abstract final class ThemeValues {
  /// A `Colors` name (`deepPurple`, `deepPurple.shade200`, `black54`) or
  /// `#RGB`, `#RRGGBB`, `#AARRGGBB` (also `0xAARRGGBB`).
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

  /// `100`…`900`, or `thin`, `extra-light`, `light`, `normal` / `regular`,
  /// `medium`, `semibold`, `bold`, `extra-bold`, `black`.
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

  /// A number (`12`, `1.5`).
  static double? number(String value) => double.tryParse(value.trim());

  /// `250ms`, `1s`, `1.5s`, or plain milliseconds.
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

  /// `0.2, 0, 0, 1` (a cubic Bézier curve, like CSS `cubic-bezier`).
  static Cubic? curve(String value) {
    final parts = [
      for (final part in value.split(',')) double.tryParse(part.trim()),
    ];
    if (parts.length != 4 || parts.contains(null)) {
      return null;
    }
    return Cubic(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }

  /// `true` / `false`.
  static bool? boolean(String value) => switch (value.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  /// One of [values] by name, ignoring case, `-` and `_`
  /// (`tonal-spot` → `tonalSpot`).
  static T? enumValue<T extends Enum>(List<T> values, String value) {
    final wanted = canonical(value);
    for (final candidate in values) {
      if (canonical(candidate.name) == wanted) {
        return candidate;
      }
    }
    return null;
  }

  /// A key or name in its canonical form: lower case, without `-` and `_`
  /// (`seed-color`, `seedColor` and `SEED_COLOR` are the same).
  static String canonical(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '');

  static String _camel(String name) =>
      name.replaceAllMapped(RegExp('[-_]([a-z])'), (m) => m[1]!.toUpperCase());
}
