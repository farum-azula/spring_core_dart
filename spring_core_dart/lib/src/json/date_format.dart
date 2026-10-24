/// Date-time helpers of `ObjectMapper`: time zone offsets, strict ISO-8601
/// parsing and `@JsonFormat(pattern: ...)` patterns.
library;

/// `UTC`, `GMT`, `Z`, or an offset such as `+02:00`, `-0530`, `GMT+2`,
/// `UTC+02:00`. Named zones (`Europe/Berlin`) need a tz database.
Duration parseTimeZone(String timeZone, [String name = 'timeZone']) {
  final match = RegExp(r'^(?:UTC|GMT|UT|Z)?(?:([+-])(\d{1,2})(?::?(\d{2}))?)?$')
      .firstMatch(timeZone.trim());
  if (timeZone.trim().isEmpty || match == null) {
    throw ArgumentError.value(
      timeZone,
      name,
      'use UTC or a fixed offset such as +02:00 (named time zones are not '
      'supported: Dart has no time zone database)',
    );
  }
  if (match[1] == null) {
    return Duration.zero;
  }
  final offset = Duration(
    hours: int.parse(match[2]!),
    minutes: int.parse(match[3] ?? '0'),
  );
  if (offset > const Duration(hours: 18)) {
    throw ArgumentError.value(timeZone, name, 'offset out of range');
  }
  return match[1] == '-' ? -offset : offset;
}

final _iso = RegExp(
  r'^([+-]?\d{4,6})-(\d{2})-(\d{2})'
  r'(?:T(\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d{1,9}))?)?'
  r'(Z|[+-]\d{2}(?::?\d{2})?)?)?$',
);

/// A strict ISO-8601 date-time (`2026-01-31`, `2026-01-31T12:00`,
/// `2026-01-31T12:00:00.123456+02:00`), as Jackson's `StdDateFormat` reads
/// it: text without an offset is in [defaultOffset] (the mapper's time
/// zone, UTC by default). Returns a UTC `DateTime`, or `null` when the text
/// is not such a date or a field is out of range (month 13, February 30,
/// hour 24, ...).
DateTime? parseIsoDateTime(String text, Duration defaultOffset) {
  final match = _iso.firstMatch(text);
  if (match == null) {
    return null;
  }
  final zone = match[8];
  final offset = zone == null ? defaultOffset : _offset(zone);
  if (offset == null) {
    return null;
  }
  final fraction = (match[7] ?? '').padRight(6, '0').substring(0, 6);
  return _build(
    year: int.parse(match[1]!),
    month: int.parse(match[2]!),
    day: int.parse(match[3]!),
    hour: int.parse(match[4] ?? '0'),
    minute: int.parse(match[5] ?? '0'),
    second: int.parse(match[6] ?? '0'),
    microsecond: int.parse(fraction),
    offset: offset,
  );
}

Duration? _offset(String zone) {
  if (zone == 'Z') {
    return Duration.zero;
  }
  final digits = zone.substring(1).replaceAll(':', '');
  final hours = int.parse(digits.substring(0, 2));
  final minutes = digits.length > 2 ? int.parse(digits.substring(2)) : 0;
  if (hours > 18 || minutes > 59) {
    return null;
  }
  final offset = Duration(hours: hours, minutes: minutes);
  return zone.startsWith('-') ? -offset : offset;
}

// A UTC DateTime of the local fields in [offset], or null when a field is
// out of range (DateTime itself would roll it over).
DateTime? _build({
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
  required int microsecond,
  required Duration offset,
}) {
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final local = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    0,
    microsecond,
  );
  if (local.day != day || local.month != month) {
    return null; // February 30 and the like
  }
  return local.subtract(offset);
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// A `DateTimeFormatter`-style pattern (`yyyy-MM-dd HH:mm`), the subset
/// `@JsonFormat(pattern: ...)` supports: `y`/`u` year, `M`/`L` month
/// (`MMM` `Jan`, `MMMM` `January`), `d` day, `E` day of week, `a` AM/PM,
/// `H` `k` `h` `K` hours, `m` minutes, `s` seconds, `S` fraction of a
/// second, `X` `x` `Z` offsets, `'quoted text'`; other letters are
/// rejected, other characters are literal.
final class DatePattern {
  /// Parses [pattern]; throws an [ArgumentError] for unsupported letters.
  DatePattern(this.pattern) : _tokens = _tokenize(pattern);

  /// The pattern.
  final String pattern;
  final List<_Token> _tokens;

  static const _letters = 'yuMLdEaHkhKmsSXxZ';

  static List<_Token> _tokenize(String pattern) {
    final tokens = <_Token>[];
    var i = 0;
    while (i < pattern.length) {
      final char = pattern[i];
      if (char == "'") {
        final end = pattern.indexOf("'", i + 1);
        if (end == i + 1) {
          tokens.add(_Token.literal("'"));
          i += 2;
          continue;
        }
        if (end < 0) {
          throw ArgumentError.value(pattern, 'pattern', 'unclosed quote');
        }
        tokens.add(
          _Token.literal(pattern.substring(i + 1, end).replaceAll("''", "'")),
        );
        i = end + 1;
        continue;
      }
      if (RegExp('[A-Za-z]').hasMatch(char)) {
        if (!_letters.contains(char)) {
          throw ArgumentError.value(
            pattern,
            'pattern',
            "unsupported pattern letter '$char'",
          );
        }
        var count = 1;
        while (i + count < pattern.length && pattern[i + count] == char) {
          count++;
        }
        tokens.add(_Token(char, count));
        i += count;
        continue;
      }
      tokens.add(_Token.literal(char));
      i++;
    }
    return tokens;
  }

  /// Whether the pattern has an offset field (`X`, `x` or `Z`).
  bool get hasOffset => _tokens.any((t) => 'XxZ'.contains(t.letter ?? '-'));

  /// [value] written in [offset].
  String format(DateTime value, Duration offset) {
    final local = value.toUtc().add(offset);
    final out = StringBuffer();
    for (final token in _tokens) {
      final count = token.count;
      String pad(int n, [int width = 0]) =>
          n.toString().padLeft(width == 0 ? count : width, '0');
      switch (token.letter) {
        case null:
          out.write(token.text);
        case 'y' || 'u':
          out.write(count == 2 ? pad(local.year % 100, 2) : pad(local.year));
        case 'M' || 'L':
          out.write(switch (count) {
            1 || 2 => pad(local.month),
            3 => _months[local.month - 1].substring(0, 3),
            _ => _months[local.month - 1],
          });
        case 'd':
          out.write(pad(local.day));
        case 'E':
          final day = _days[local.weekday - 1];
          out.write(count >= 4 ? day : day.substring(0, 3));
        case 'a':
          out.write(local.hour < 12 ? 'AM' : 'PM');
        case 'H':
          out.write(pad(local.hour));
        case 'k':
          out.write(pad(local.hour == 0 ? 24 : local.hour));
        case 'h':
          out.write(pad(local.hour % 12 == 0 ? 12 : local.hour % 12));
        case 'K':
          out.write(pad(local.hour % 12));
        case 'm':
          out.write(pad(local.minute));
        case 's':
          out.write(pad(local.second));
        case 'S':
          final micros = local.millisecond * 1000 + local.microsecond;
          final digits = micros.toString().padLeft(6, '0').padRight(9, '0');
          out.write(digits.substring(0, count.clamp(1, 9)));
        case 'X' || 'x' || 'Z':
          out.write(_formatOffset(token.letter!, count, offset));
      }
    }
    return out.toString();
  }

  static String _formatOffset(String letter, int count, Duration offset) {
    if (offset == Duration.zero && letter == 'X') {
      return 'Z';
    }
    if (offset == Duration.zero && letter == 'Z' && count == 5) {
      return 'Z';
    }
    final minutes = offset.inMinutes.abs();
    final hh = (minutes ~/ 60).toString().padLeft(2, '0');
    final mm = (minutes % 60).toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';
    return switch ((letter, count)) {
      ('X' || 'x', 1) => mm == '00' ? '$sign$hh' : '$sign$hh$mm',
      ('X' || 'x', 2) || ('Z', <= 3) => '$sign$hh$mm',
      ('Z', 4) => 'GMT$sign$hh:$mm',
      _ => '$sign$hh:$mm',
    };
  }

  /// A UTC `DateTime` of [text]; text without an offset field is in
  /// [defaultOffset]. Throws a [FormatException] when [text] does not match
  /// or a field is out of range.
  DateTime parse(String text, Duration defaultOffset) {
    var year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0;
    var micros = 0;
    int? hour12;
    bool? pm;
    Duration? offset;
    var position = 0;
    Never fail() => throw FormatException(
      "'$text' does not match the pattern '$pattern'",
      text,
      position,
    );
    bool isNumeric(_Token? token) =>
        token != null &&
        token.letter != null &&
        !'aEXxZ'.contains(token.letter!) &&
        !('ML'.contains(token.letter!) && token.count >= 3);
    int number(int count, _Token? next) {
      final start = position;
      final fixed = count > 1 && isNumeric(next);
      while (position < text.length &&
          RegExp(r'\d').hasMatch(text[position]) &&
          (!fixed || position - start < count)) {
        position++;
      }
      if (position == start || (fixed && position - start != count)) {
        fail();
      }
      return int.parse(text.substring(start, position));
    }

    int name(List<String> names, int length) {
      for (var i = 0; i < names.length; i++) {
        final candidate = length == 0
            ? names[i]
            : names[i].substring(0, length);
        if (text.length >= position + candidate.length &&
            text
                    .substring(position, position + candidate.length)
                    .toLowerCase() ==
                candidate.toLowerCase()) {
          position += candidate.length;
          return i;
        }
      }
      fail();
    }

    for (var t = 0; t < _tokens.length; t++) {
      final token = _tokens[t];
      final next = t + 1 < _tokens.length ? _tokens[t + 1] : null;
      final count = token.count;
      switch (token.letter) {
        case null:
          if (!text.startsWith(token.text, position)) {
            fail();
          }
          position += token.text.length;
        case 'y' || 'u':
          final value = number(count == 2 ? 2 : count, next);
          year = count == 2 ? 2000 + value : value;
        case 'M' || 'L':
          month = count >= 3
              ? name(_months, count == 3 ? 3 : 0) + 1
              : number(count, next);
        case 'd':
          day = number(count, next);
        case 'E':
          name(_days, count >= 4 ? 0 : 3);
        case 'a':
          pm = name(const ['AM', 'PM'], 0) == 1;
        case 'H' || 'k':
          hour = number(count, next);
          if (token.letter == 'k') {
            if (hour == 0 || hour > 24) {
              fail();
            }
            hour %= 24;
          }
        case 'h' || 'K':
          hour12 = number(count, next);
          if (token.letter == 'h' && (hour12 == 0 || hour12 > 12)) {
            fail();
          }
          hour12 %= 12;
        case 'm':
          minute = number(count, next);
        case 's':
          second = number(count, next);
        case 'S':
          final start = position;
          number(count, next);
          micros = int.parse(
            text.substring(start, position).padRight(6, '0').substring(0, 6),
          );
        case 'X' || 'x' || 'Z':
          final match = RegExp(r'Z|(?:GMT)?[+-]\d{2}(?::?\d{2})?')
              .matchAsPrefix(text, position);
          if (match == null) {
            fail();
          }
          position = match.end;
          offset = _offset(match[0]!.replaceFirst('GMT', '')) ?? fail();
      }
    }
    if (position != text.length) {
      fail();
    }
    if (hour12 != null) {
      if (hour12 > 11 || hour > 0) {
        fail();
      }
      hour = hour12 + ((pm ?? false) ? 12 : 0);
    }
    return _build(
          year: year,
          month: month,
          day: day,
          hour: hour,
          minute: minute,
          second: second,
          microsecond: micros,
          offset: offset ?? defaultOffset,
        ) ??
        fail();
  }
}

final class _Token {
  _Token(this.letter, this.count) : text = '';
  _Token.literal(this.text) : letter = null, count = 0;

  final String? letter;
  final int count;
  final String text;
}
