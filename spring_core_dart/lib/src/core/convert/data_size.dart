/// An amount of data, such as an upload limit or a cache size, stored as
/// a whole number of bytes.
///
/// It exists so configuration can say `10MB` instead of `10485760`. The
/// default conversion service turns strings such as `10MB`, `512KB` or
/// `100` (bytes) and plain `int`s (bytes) into a `DataSize`, so an
/// application declares a `@ConfigurationProperties` field or a `@Value`
/// parameter of this type and reads the result. Units are powers of 1024.
///
/// ```dart
/// @ConfigurationProperties('shop.upload')
/// class UploadProperties {
///   // `shop.upload.max-size=10MB`; a plain number would be bytes.
///   DataSize maxSize = DataSize.ofMegabytes(5);
/// }
///
/// // Later, in the upload handler:
/// if (body.length > properties.maxSize.toBytes()) { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @ConfigurationProperties("shop.upload")
/// class UploadProperties {
///   private DataSize maxSize = DataSize.ofMegabytes(5);
///   // getter and setter
/// }
/// ```
final class DataSize implements Comparable<DataSize> {
  /// A size of exactly the given number of bytes.
  const DataSize.ofBytes(this._bytes);

  /// A size of [kilobytes] kilobytes of 1024 bytes each.
  DataSize.ofKilobytes(int kilobytes) : _bytes = kilobytes * 1024;

  /// A size of [megabytes] megabytes (1024 KB each).
  DataSize.ofMegabytes(int megabytes) : _bytes = megabytes * 1024 * 1024;

  /// A size of [gigabytes] gigabytes (1024 MB each).
  DataSize.ofGigabytes(int gigabytes) : _bytes = gigabytes * 1024 * 1024 * 1024;

  /// A size of [terabytes] terabytes (1024 GB each).
  DataSize.ofTerabytes(int terabytes)
    : _bytes = terabytes * 1024 * 1024 * 1024 * 1024;

  /// A size of [amount] times [unit], for a unit chosen at run time.
  DataSize.of(int amount, DataUnit unit) : _bytes = amount * unit.byteCount;

  final int _bytes;

  static final _pattern = RegExp(r'^([+-]?\d+)([a-zA-Z]{0,2})$');

  /// Reads a size written as a whole number with an optional unit: `10MB`,
  /// `512kb`, `100B`, `100`.
  ///
  /// The unit is `B`, `KB`, `MB`, `GB` or `TB` in any case; a number
  /// without one is in [unit] (bytes unless given, which is how Spring
  /// Boot's `@DataSizeUnit` works). Surrounding spaces are ignored.
  /// Throws a [FormatException] for anything else, including fractions
  /// such as `1.5GB`.
  ///
  /// ```dart
  /// DataSize.parse('10MB').toBytes(); // 10485760
  /// DataSize.parse('2', unit: DataUnit.kilobytes).toBytes(); // 2048
  /// ```
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

  /// The size in whole kilobytes, rounded toward zero.
  int toKilobytes() => _bytes ~/ DataUnit.kilobytes.byteCount;

  /// The size in whole megabytes, rounded toward zero.
  int toMegabytes() => _bytes ~/ DataUnit.megabytes.byteCount;

  /// The size in whole gigabytes, rounded toward zero.
  int toGigabytes() => _bytes ~/ DataUnit.gigabytes.byteCount;

  /// The size in whole terabytes, rounded toward zero.
  int toTerabytes() => _bytes ~/ DataUnit.terabytes.byteCount;

  /// Whether the size is below zero.
  bool get isNegative => _bytes < 0;

  @override
  int compareTo(DataSize other) => _bytes.compareTo(other._bytes);

  @override
  bool operator ==(Object other) => other is DataSize && other._bytes == _bytes;

  @override
  int get hashCode => _bytes.hashCode;

  /// The size in bytes with a `B` suffix (`10485760B`), like Spring's
  /// `DataSize.toString`; [parse] reads it back.
  @override
  String toString() => '${_bytes}B';
}

/// A unit a [DataSize] can be written in, each 1024 times the one before.
///
/// An application meets it in `@DataSizeUnit(DataUnit.megabytes)`, which
/// says in which unit a plain number of a field is read, and in
/// [DataSize.of] and [DataSize.parse].
///
/// Spring (Java): `DataUnit`.
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

  DataUnit(this.suffix, this.byteCount);

  /// The suffix that names this unit in text such as `10MB`.
  final String suffix;

  /// How many bytes one of this unit holds.
  final int byteCount;
}
