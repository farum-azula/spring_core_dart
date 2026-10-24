/// A size in bytes, like Spring's `DataSize`: parsed from `10MB`, `512KB`,
/// `1GB` or `100` (bytes unless another default unit is given), units in
/// powers of 1024 like Spring's `DataUnit`.
///
/// `DefaultConversionService` converts strings and ints to it, so
/// `@ConfigurationProperties` fields and `@Value` can be `DataSize`.
///
/// ```dart
/// final size = DataSize.parse('10MB');
/// size.toBytes(); // 10485760
/// DataSize.parse('2', unit: DataUnit.kilobytes).toBytes(); // 2048
/// ```
///
/// Spring (Java):
/// ```java
/// DataSize size = DataSize.parse("10MB");
/// size.toBytes();
/// DataSize.parse("2", DataUnit.KILOBYTES);
/// ```
final class DataSize implements Comparable<DataSize> {
  /// [bytes] bytes.
  const DataSize.ofBytes(this._bytes);

  /// [kilobytes] KB (1024 bytes each).
  DataSize.ofKilobytes(int kilobytes) : _bytes = kilobytes * 1024;

  /// [megabytes] MB.
  DataSize.ofMegabytes(int megabytes) : _bytes = megabytes * 1024 * 1024;

  /// [gigabytes] GB.
  DataSize.ofGigabytes(int gigabytes) : _bytes = gigabytes * 1024 * 1024 * 1024;

  /// [terabytes] TB.
  DataSize.ofTerabytes(int terabytes)
    : _bytes = terabytes * 1024 * 1024 * 1024 * 1024;

  /// [amount] of [unit].
  DataSize.of(int amount, DataUnit unit) : _bytes = amount * unit.byteCount;

  final int _bytes;

  static final _pattern = RegExp(r'^([+-]?\d+)([a-zA-Z]{0,2})$');

  /// Parses [text] (`10MB`, `512kb`, `100B`, `100`); a number without a
  /// unit is in [unit] (bytes by default; Boot's `@DataSizeUnit`). Throws
  /// a [FormatException] for anything else.
  static DataSize parse(String text, {DataUnit unit = DataUnit.bytes}) {
    final match = _pattern.firstMatch(text.trim());
    if (match == null) {
      throw FormatException("'$text' is not a valid data size", text);
    }
    final amount = int.parse(match[1]!);
    final suffix = match[2]!.toUpperCase();
    if (suffix.isEmpty) {
      return DataSize.of(amount, unit);
    }
    for (final candidate in DataUnit.values) {
      if (candidate.suffix == suffix) {
        return DataSize.of(amount, candidate);
      }
    }
    throw FormatException("Unknown data unit suffix '${match[2]}'", text);
  }

  /// The size in bytes.
  int toBytes() => _bytes;

  /// The size in whole kilobytes.
  int toKilobytes() => _bytes ~/ DataUnit.kilobytes.byteCount;

  /// The size in whole megabytes.
  int toMegabytes() => _bytes ~/ DataUnit.megabytes.byteCount;

  /// The size in whole gigabytes.
  int toGigabytes() => _bytes ~/ DataUnit.gigabytes.byteCount;

  /// The size in whole terabytes.
  int toTerabytes() => _bytes ~/ DataUnit.terabytes.byteCount;

  /// Whether the size is below zero.
  bool get isNegative => _bytes < 0;

  @override
  int compareTo(DataSize other) => _bytes.compareTo(other._bytes);

  @override
  bool operator ==(Object other) => other is DataSize && other._bytes == _bytes;

  @override
  int get hashCode => _bytes.hashCode;

  /// `<bytes>B`, like Spring's `DataSize.toString`.
  @override
  String toString() => '${_bytes}B';
}

/// The units of a [DataSize], like Spring's `DataUnit`.
enum DataUnit {
  /// Bytes (`B`).
  bytes('B', 1),

  /// Kilobytes (`KB`, 1024 bytes).
  kilobytes('KB', 1024),

  /// Megabytes (`MB`).
  megabytes('MB', 1024 * 1024),

  /// Gigabytes (`GB`).
  gigabytes('GB', 1024 * 1024 * 1024),

  /// Terabytes (`TB`).
  terabytes('TB', 1024 * 1024 * 1024 * 1024);

  const DataUnit(this.suffix, this.byteCount);

  /// The suffix in sizes such as `10MB`.
  final String suffix;

  /// Bytes in one unit.
  final int byteCount;
}
