import 'package:spring_core_dart/src/core/convert/conversion_exceptions.dart';
import 'package:spring_core_dart/src/core/convert/default_conversion_service.dart';
import 'package:spring_core_dart/src/core/convert/duration_style.dart';
import 'package:spring_core_dart/src/core/convert/generic_conversion_service.dart';
import 'package:test/test.dart';

enum Color { red, darkBlue }

class Money {
  Money(this.cents);
  final int cents;
}

void main() {
  final service = DefaultConversionService();

  group('scalars from String', () {
    test('numbers', () {
      expect(service.convert<int>(' 42 '), 42);
      expect(service.convert<int>('-0x1F'), -31);
      expect(service.convert<int>('#ff'), 255);
      expect(service.convert<int>('+7'), 7);
      expect(service.convert<double>('1.5'), 1.5);
      expect(service.convert<num>('3'), 3);
      expect(
        service.convert<BigInt>('123456789012345678901234567890'),
        BigInt.parse('123456789012345678901234567890'),
      );
    });

    test('booleans like Spring', () {
      for (final value in ['true', 'ON', 'yes', '1']) {
        expect(service.convert<bool>(value), isTrue, reason: value);
      }
      for (final value in ['false', 'Off', 'NO', '0']) {
        expect(service.convert<bool>(value), isFalse, reason: value);
      }
      expect(
        () => service.convert<bool>('maybe'),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('other types', () {
      expect(service.convert<Uri>('https://a.b/c'), Uri.parse('https://a.b/c'));
      expect(
        service.convert<DateTime>('2026-10-20T10:00:00Z'),
        DateTime.utc(2026, 10, 20, 10),
      );
      expect(service.convert<Duration>('10s'), const Duration(seconds: 10));
      expect(service.convert<RegExp>('a+').hasMatch('aaa'), isTrue);
      expect(service.convert<Pattern>('b'), 'b'); // a String is a Pattern
      expect(service.convert<Duration>(250), const Duration(milliseconds: 250));
    });

    test('empty string is null for nullable targets, error otherwise', () {
      expect(service.convert<int?>('  '), isNull);
      expect(service.convert<bool?>(''), isNull);
      expect(
        () => service.convert<int>(''),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('invalid input wraps the cause', () {
      expect(
        () => service.convert<int>('abc'),
        throwsA(
          isA<ConversionFailedException>()
              .having((e) => e.targetType, 'target', int)
              .having((e) => e.cause, 'cause', isA<FormatException>())
              .having((e) => e.toString(), 'text', contains("'abc'")),
        ),
      );
    });
  });

  group('to String and between numbers', () {
    test('toString and readable forms', () {
      expect(service.convert<String>(5), '5');
      expect(service.convert<String>(const Duration(minutes: 3)), 'PT3M');
      expect(service.convert<String>(['a', 'b']), 'a,b');
      expect(service.convert<String>({1, 2}), '1,2');
      expect(
        service.convert<String>(DateTime.utc(2026)),
        '2026-01-01T00:00:00.000Z',
      );
    });

    test('num to int and double', () {
      expect(service.convert<int>(3.0), 3);
      expect(service.convert<double>(3), 3.0);
      expect(
        () => service.convert<int>(3.5),
        throwsA(isA<ConversionFailedException>()),
      );
    });
  });

  group('identity and null', () {
    test('same type is returned as is', () {
      final list = <int>[1];
      expect(service.convert<List<int>>(list), same(list));
      expect(service.convert<Object>(list), same(list));
      expect(service.convertTo(list, Object), same(list));
      expect(service.convertTo(5, int), 5);
    });

    test('null', () {
      expect(service.convert<String?>(null), isNull);
      expect(service.convertTo(null, int), isNull);
      expect(service.canConvert(null, int), isTrue);
      expect(
        () => service.convert<String>(null),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('subtype is direct when the target was registered', () {
      expect(service.convertTo(3, num), 3);
      expect(service.canConvert(3, num), isTrue);
    });
  });

  group('collections', () {
    test('from comma-separated strings', () {
      expect(service.convert<List<String>>(' a, b ,c'), ['a', 'b', 'c']);
      expect(service.convert<List<int>>('1,2,3'), [1, 2, 3]);
      expect(service.convert<Set<int>>('1,1,2'), {1, 2});
      expect(service.convert<List<Duration>>('1s,2m'), [
        const Duration(seconds: 1),
        const Duration(minutes: 2),
      ]);
      expect(service.convert<List<String>>(''), isEmpty);
    });

    test('from other iterables', () {
      expect(service.convert<List<int>>(['1', 2.0]), [1, 2]);
      expect(service.convert<Set<String>>([1, 2]), {'1', '2'});
      expect(service.convert<List<bool>>({'yes', 'no'}), [true, false]);
    });

    test('custom element types', () {
      final custom = DefaultConversionService()
        ..addEnum<Color>(Color.values)
        ..addCollectionConverters<Color>();
      expect(custom.convert<List<Color>>('red, DARKBLUE'), [
        Color.red,
        Color.darkBlue,
      ]);
    });
  });

  group('enums', () {
    final enums = DefaultConversionService()..addEnum<Color>(Color.values);

    test('by name, case-insensitive, both directions', () {
      expect(enums.convert<Color>('darkblue'), Color.darkBlue);
      expect(enums.convert<Color?>(' '), isNull);
      expect(enums.convert<String>(Color.red), 'red');
      expect(
        () => enums.convert<Color>('green'),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('lenient names like Boot (dashes, underscores, case)', () {
      for (final name in ['dark-blue', 'DARK_BLUE', 'darkBlue', 'Dark Blue']) {
        expect(enums.convert<Color>(name), Color.darkBlue, reason: name);
      }
    });
  });

  group('registry', () {
    test('missing converter', () {
      final empty = GenericConversionService();
      expect(empty.canConvert('1', int), isFalse);
      expect(
        () => empty.convert<int>('1'),
        throwsA(
          isA<ConverterNotFoundException>()
              .having((e) => e.sourceType, 'source', String)
              .having((e) => e.targetType, 'target', int),
        ),
      );
    });

    test('later converters win, also for nullable targets', () {
      final custom = GenericConversionService()
        ..addConverter<String, Money>((s) => Money(int.parse(s)))
        ..addConverter<int, Money>((s) => Money(s * 100))
        ..addConverter<String, Money>((s) => Money(int.parse(s) * 100));
      expect(custom.convert<Money>('2').cents, 200);
      expect(custom.convert<Money>(3).cents, 300);
      expect(custom.convert<Money?>('1')!.cents, 100);
      expect(custom.canConvert('1', Money), isTrue);
    });

    test('removeConvertible', () {
      final custom = GenericConversionService()
        ..addConverter<String, Money>((s) => Money(int.parse(s)));
      custom.removeConvertible<Money>();
      expect(custom.canConvert('1', Money), isFalse);
    });

    test('converter returning a wrong value fails', () {
      final custom = GenericConversionService()
        ..addConverter<String, int>((s) => null);
      expect(
        () => custom.convert<int>('x'),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('nested conversion errors are not double wrapped', () {
      expect(
        () => service.convert<List<int>>('1,x'),
        throwsA(
          isA<ConversionFailedException>().having((e) => e.value, 'value', 'x'),
        ),
      );
    });

    test('shared instance', () {
      expect(DefaultConversionService.sharedInstance.convert<int>('1'), 1);
    });
  });

  group('DurationStyle', () {
    test('simple style', () {
      expect(DurationStyle.parse('100'), const Duration(milliseconds: 100));
      expect(DurationStyle.parse('5000ns'), const Duration(microseconds: 5));
      expect(DurationStyle.parse('7us'), const Duration(microseconds: 7));
      expect(DurationStyle.parse('2ms'), const Duration(milliseconds: 2));
      expect(DurationStyle.parse('-3s'), const Duration(seconds: -3));
      expect(DurationStyle.parse('4m'), const Duration(minutes: 4));
      expect(DurationStyle.parse('5H'), const Duration(hours: 5));
      expect(DurationStyle.parse('6d'), const Duration(days: 6));
      expect(() => DurationStyle.parse('5w'), throwsFormatException);
    });

    test('ISO-8601 style', () {
      expect(DurationStyle.parse('PT10S'), const Duration(seconds: 10));
      expect(
        DurationStyle.parse('P1DT2H30M'),
        const Duration(days: 1, hours: 2, minutes: 30),
      );
      expect(DurationStyle.parse('pt0.5s'), const Duration(milliseconds: 500));
      expect(DurationStyle.parse('PT1,5S'), const Duration(milliseconds: 1500));
      expect(DurationStyle.parse('-PT1M'), const Duration(minutes: -1));
      expect(DurationStyle.parse('P2D'), const Duration(days: 2));
      expect(DurationStyle.parse('P-1D'), const Duration(days: -1));
      expect(DurationStyle.parse('-PT5S'), const Duration(seconds: -5));
      expect(DurationStyle.parse('-P-1D'), const Duration(days: 1));
      for (final bad in ['P', 'PT', 'abc', '1.5s']) {
        expect(
          () => DurationStyle.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('format picks the largest exact unit', () {
      expect(DurationStyle.format(Duration.zero), '0ms');
      expect(DurationStyle.format(const Duration(days: 2)), '2d');
      expect(DurationStyle.format(const Duration(hours: 25)), '25h');
      expect(DurationStyle.format(const Duration(minutes: 90)), '90m');
      expect(DurationStyle.format(const Duration(seconds: 61)), '61s');
      expect(
        DurationStyle.format(const Duration(milliseconds: 1500)),
        '1500ms',
      );
      expect(DurationStyle.format(const Duration(microseconds: 3)), '3us');
    });

    test('formatIso prints like java.time.Duration.toString', () {
      String iso(Duration d) => DurationStyle.formatIso(d);
      expect(iso(Duration.zero), 'PT0S');
      expect(iso(const Duration(days: 1)), 'PT24H');
      expect(iso(const Duration(minutes: 90)), 'PT1H30M');
      expect(iso(const Duration(seconds: 61)), 'PT1M1S');
      expect(iso(const Duration(milliseconds: 500)), 'PT0.5S');
      expect(iso(const Duration(microseconds: 1)), 'PT0.000001S');
      expect(iso(const Duration(seconds: -5)), 'PT-5S');
      expect(iso(const Duration(minutes: -90)), 'PT-1H-30M');
      expect(iso(const Duration(milliseconds: -1500)), 'PT-1.5S');
      for (final d in [
        const Duration(hours: 49, seconds: 3, milliseconds: 20),
        const Duration(milliseconds: -250),
      ]) {
        expect(DurationStyle.parse(iso(d)), d);
      }
    });
  });
}
