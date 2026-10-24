import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

// Spring's conversion behaviour: canConvert by type, number truncation,
// DataSize and duration units.
void main() {
  final service = DefaultConversionService();

  test('canConvertType checks source and target types', () {
    expect(service.canConvertType<String>(Duration), isTrue);
    expect(service.canConvertType<String>(int), isTrue);
    expect(service.canConvertType<int>(int), isTrue);
    expect(service.canConvertType<int>(double), isTrue); // via num
    expect(service.canConvertType<Uri>(Duration), isFalse);
    expect(service.canConvertType<Uri>(Object), isTrue);
    expect(service.canConvertType<String>(DataSize), isTrue);
  });

  test('a double converts to int truncated, like Spring\'s NumberUtils', () {
    expect(service.convert<int>(1.9), 1);
    expect(service.convert<int>(-1.9), -1);
    expect(
      () => service.convert<int>(double.nan),
      throwsA(isA<ConversionFailedException>()),
    );
  });

  test('DataSize parses Spring\'s units (powers of 1024)', () {
    expect(DataSize.parse('10MB').toBytes(), 10 * 1024 * 1024);
    expect(DataSize.parse('512kb').toKilobytes(), 512);
    expect(DataSize.parse('100').toBytes(), 100);
    expect(DataSize.parse('3', unit: DataUnit.gigabytes).toGigabytes(), 3);
    expect(DataSize.parse('1TB'), DataSize.ofTerabytes(1));
    expect(DataSize.ofKilobytes(2).toString(), '2048B');
    expect(() => DataSize.parse('10XB'), throwsFormatException);
    expect(service.convert<DataSize>('2MB'), DataSize.ofMegabytes(2));
    expect(service.convert<List<DataSize>>('1KB,2KB'), [
      DataSize.ofKilobytes(1),
      DataSize.ofKilobytes(2),
    ]);
  });

  test('a duration without a unit takes the given ChronoUnit', () {
    expect(DurationStyle.parse('30'), const Duration(milliseconds: 30));
    expect(
      DurationStyle.parse('30', unit: ChronoUnit.seconds),
      const Duration(seconds: 30),
    );
    expect(
      DurationStyle.parse('2h', unit: ChronoUnit.seconds),
      const Duration(hours: 2),
    );
    expect(ChronoUnit.days.of(1), const Duration(days: 1));
  });
}
