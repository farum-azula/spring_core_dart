// Reading theme property values: colors, weights, numbers, durations,
// curves, booleans, enums, canonical names.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';

void main() {
  group('color', () {
    test('hex: #RGB, #RRGGBB, #AARRGGBB, 0xAARRGGBB', () {
      expect(ThemeValues.color('#F0A'), const Color(0xFFFF00AA));
      expect(ThemeValues.color('#673AB7'), const Color(0xFF673AB7));
      expect(ThemeValues.color('#80673AB7'), const Color(0x80673AB7));
      expect(ThemeValues.color('0x80673AB7'), const Color(0x80673AB7));
      expect(ThemeValues.color(' #673ab7 '), const Color(0xFF673AB7));
    });

    test('Colors names: swatches, shades, accents, plain, kebab-case', () {
      expect(
        ThemeValues.color('deepPurple')!.toARGB32(),
        Colors.deepPurple.toARGB32(),
      );
      expect(
        ThemeValues.color('deepPurple.shade200'),
        Colors.deepPurple.shade200,
      );
      expect(
        ThemeValues.color('deep-purple')!.toARGB32(),
        Colors.deepPurple.toARGB32(),
      );
      expect(
        ThemeValues.color('redAccent.shade100'),
        Colors.redAccent.shade100,
      );
      expect(ThemeValues.color('black54'), Colors.black54);
      expect(ThemeValues.color('transparent'), Colors.transparent);
    });

    test('anything else is no color', () {
      for (final value in [
        '#12',
        '#12345',
        '#GGGGGG',
        '0xZZ',
        'purpel',
        'deepPurple.shade250',
        '',
      ]) {
        expect(ThemeValues.color(value), isNull, reason: value);
      }
    });
  });

  test('weight: numbers and names', () {
    expect(ThemeValues.weight('100'), FontWeight.w100);
    expect(ThemeValues.weight('900'), FontWeight.w900);
    const names = {
      'thin': FontWeight.w100,
      'extra-light': FontWeight.w200,
      'light': FontWeight.w300,
      'normal': FontWeight.w400,
      'regular': FontWeight.w400,
      'medium': FontWeight.w500,
      'semibold': FontWeight.w600,
      'Semi_Bold': FontWeight.w600,
      'bold': FontWeight.w700,
      'extra-bold': FontWeight.w800,
      'black': FontWeight.w900,
    };
    names.forEach(
      (name, weight) => expect(ThemeValues.weight(name), weight, reason: name),
    );
    for (final value in ['0', '50', '450', '1000', 'heavy']) {
      expect(ThemeValues.weight(value), isNull, reason: value);
    }
  });

  test('number', () {
    expect(ThemeValues.number('12'), 12);
    expect(ThemeValues.number(' 1.5 '), 1.5);
    expect(ThemeValues.number('-0.25'), -0.25);
    expect(ThemeValues.number('twelve'), isNull);
  });

  test('duration: ms, s, plain milliseconds', () {
    expect(ThemeValues.duration('250ms'), const Duration(milliseconds: 250));
    expect(ThemeValues.duration('1s'), const Duration(seconds: 1));
    expect(ThemeValues.duration('1.5s'), const Duration(milliseconds: 1500));
    expect(ThemeValues.duration('100'), const Duration(milliseconds: 100));
    expect(ThemeValues.duration('0.5 ms'), const Duration(microseconds: 500));
    expect(ThemeValues.duration('2m'), isNull);
    expect(ThemeValues.duration('fast'), isNull);
  });

  test('curve: four numbers', () {
    final curve = ThemeValues.curve('0.2, 0, 0, 1')!;
    expect([curve.a, curve.b, curve.c, curve.d], [0.2, 0, 0, 1]);
    expect(ThemeValues.curve('0.2,0,0'), isNull);
    expect(ThemeValues.curve('0.2, 0, x, 1'), isNull);
  });

  test('boolean', () {
    expect(ThemeValues.boolean('true'), isTrue);
    expect(ThemeValues.boolean(' FALSE '), isFalse);
    expect(ThemeValues.boolean('yes'), isNull);
  });

  test('enum: case, - and _ ignored', () {
    expect(
      ThemeValues.enumValue(DynamicSchemeVariant.values, 'tonal-spot'),
      DynamicSchemeVariant.tonalSpot,
    );
    expect(
      ThemeValues.enumValue(DynamicSchemeVariant.values, 'FRUIT_SALAD'),
      DynamicSchemeVariant.fruitSalad,
    );
    expect(ThemeValues.enumValue(Brightness.values, 'grey'), isNull);
  });

  test('canonical names', () {
    expect(ThemeValues.canonical('seed-color'), 'seedcolor');
    expect(ThemeValues.canonical('seedColor'), 'seedcolor');
    expect(ThemeValues.canonical('SEED_COLOR'), 'seedcolor');
  });

  test('ThemePropertyException names key, value and what is expected', () {
    expect(
      ThemePropertyException(
        'spring.flutter.theme.seedcolor',
        'purpel',
        'a color',
      ).toString(),
      "Invalid theme property spring.flutter.theme.seedcolor: 'purpel'; expected a color.",
    );
  });
}
