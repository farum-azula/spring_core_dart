/// Parses and formats durations like Spring Boot's `DurationStyle`.
///
/// Simple style: an integer with an optional unit `ns`, `us`, `ms`, `s`,
/// `m`, `h`, `d` (no unit = milliseconds), e.g. `500ms`, `10s`, `-2h`.
/// ISO-8601 style: `PT10S`, `P1DT2H30M`, `PT0.5S`.
///
/// Used by `DefaultConversionService` for `String` ⇄ `Duration`.
///
/// ```dart
/// DurationStyle.parse('500ms'); // Duration(milliseconds: 500)
/// DurationStyle.parse('P1DT2H'); // Duration(days: 1, hours: 2)
/// DurationStyle.format(const Duration(minutes: 90)); // '90m'
/// ```
///
/// Spring (Java):
/// ```java
/// Duration d = DurationStyle.detectAndParse("500ms");
/// Duration iso = DurationStyle.detectAndParse("P1DT2H");
/// String text = DurationStyle.SIMPLE.print(Duration.ofMinutes(90));
/// ```
///
/// Differences: Dart's `Duration` has microsecond precision, so `ns` values
/// are truncated to microseconds; ISO-8601 years and months are not
/// supported (as in `java.time.Duration`).
abstract final class DurationStyle {
  // Simple style: signed integer plus an optional unit of up to two letters
  // (the unit is validated separately to give a precise error message).
  static final _simple = RegExp(r'^([+-]?\d+)([a-zA-Z]{0,2})$');
  // ISO-8601 duration: optional sign, days, then a `T` part with hours,
  // minutes and (fractional, `.` or `,`) seconds. Every component is
  // optional, so degenerate inputs are rejected in [parse].
  static final _iso = RegExp(
    r'^([+-])?P(?:(\d+)D)?(?:T(?:([+-]?\d+)H)?(?:([+-]?\d+)M)?'
    r'(?:([+-]?\d+(?:[.,]\d{0,9})?)S)?)?$',
    caseSensitive: false,
  );

  /// Parses [value] in either style; throws [FormatException] otherwise.
  ///
  /// Leading and trailing whitespace is ignored; units are
  /// case-insensitive.
  ///
  /// ```dart
  /// DurationStyle.parse('-2h'); // -Duration(hours: 2)
  /// DurationStyle.parse('PT0.5S'); // Duration(milliseconds: 500)
  /// ```
  static Duration parse(String value) {
    final text = value.trim();
    final simple = _simple.firstMatch(text);
    if (simple != null) {
      final amount = int.parse(simple[1]!);
      return switch (simple[2]!.toLowerCase()) {
        'ns' => Duration(microseconds: amount ~/ 1000),
        'us' => Duration(microseconds: amount),
        '' || 'ms' => Duration(milliseconds: amount),
        's' => Duration(seconds: amount),
        'm' => Duration(minutes: amount),
        'h' => Duration(hours: amount),
        'd' => Duration(days: amount),
        final unit => throw FormatException(
          "Unknown duration unit '$unit'",
          value,
        ),
      };
    }
    final iso = _iso.firstMatch(text);
    // The regex also matches bare `P` and `PT` (all parts optional); like
    // java.time, those are not valid durations.
    if (iso != null && text.length > 1 && !text.toUpperCase().endsWith('T')) {
      final sign = iso[1] == '-' ? -1 : 1;
      final seconds = iso[5]?.replaceAll(',', '.');
      final micros = seconds == null
          ? 0
          : (double.parse(seconds) * Duration.microsecondsPerSecond).round();
      final result = Duration(
        days: int.parse(iso[2] ?? '0'),
        hours: int.parse(iso[3] ?? '0'),
        minutes: int.parse(iso[4] ?? '0'),
        microseconds: micros,
      );
      return sign < 0 ? -result : result;
    }
    throw FormatException("'$value' is not a valid duration", value);
  }

  /// Formats [value] in the simple style with the largest exact unit.
  ///
  /// The result can be parsed back with [parse]; zero is `0ms`.
  ///
  /// ```dart
  /// DurationStyle.format(const Duration(seconds: 120)); // '2m'
  /// DurationStyle.format(const Duration(microseconds: 1500)); // '1500us'
  /// ```
  static String format(Duration value) {
    final micros = value.inMicroseconds;
    if (micros == 0) {
      return '0ms';
    }
    const units = [
      ('d', Duration.microsecondsPerDay),
      ('h', Duration.microsecondsPerHour),
      ('m', Duration.microsecondsPerMinute),
      ('s', Duration.microsecondsPerSecond),
      ('ms', Duration.microsecondsPerMillisecond),
    ];
    for (final (suffix, size) in units) {
      if (micros % size == 0) {
        return '${micros ~/ size}$suffix';
      }
    }
    return '${micros}us';
  }
}
