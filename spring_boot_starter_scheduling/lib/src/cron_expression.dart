/// A cron expression in Spring's six-field format, like Spring's
/// `CronExpression`:
///
/// ```text
/// ┌───────────── second (0-59)
/// │ ┌───────────── minute (0-59)
/// │ │ ┌───────────── hour (0-23)
/// │ │ │ ┌───────────── day of month (1-31)
/// │ │ │ │ ┌───────────── month (1-12 or JAN-DEC)
/// │ │ │ │ │ ┌───────────── day of week (0-7 or SUN-SAT; 0 and 7 are Sunday)
/// │ │ │ │ │ │
/// * * * * * *
/// ```
///
/// Every field takes `*`, a value, a list (`1,15,30`), a range (`9-17`)
/// and a step (`*/5`, `0-30/10`, `5/15` = from 5 every 15). Names are
/// case-insensitive. `?` means "any" in the day fields. The day fields also
/// take Quartz-style specials (one per field, not in a list):
///
/// | In | Means |
/// |---|---|
/// | day of month `L` | the last day of the month |
/// | day of month `L-3` | the third-to-last day |
/// | day of month `15W` | the weekday (Mon-Fri) nearest to the 15th, in the same month |
/// | day of month `LW` | the last weekday of the month |
/// | day of week `5L`, `FRIL` | the last Friday of the month |
/// | day of week `MON#2`, `1#2` | the second Monday of the month |
///
/// Macros: `@yearly` (`@annually`), `@monthly`, `@weekly`, `@daily`
/// (`@midnight`), `@hourly`.
///
/// As in Spring, a day must match both day fields (they are combined with
/// "and", unlike Unix cron's "or"), and ranges must not wrap around
/// (`FRI-MON` is rejected; write `FRI-SAT,SUN-MON`).
///
/// ```dart
/// final everyQuarter = CronExpression.parse('0 */15 * * * *');
/// everyQuarter.next(DateTime(2026, 1, 1, 10, 7)); // 2026-01-01 10:15:00
///
/// CronExpression.parse('0 0 9 * * MON-FRI'); // 9:00 on working days
/// CronExpression.parse('0 0 18 L * *');      // 18:00 on the last day
/// ```
///
/// Spring (Java):
/// ```java
/// CronExpression everyQuarter = CronExpression.parse("0 */15 * * * *");
/// LocalDateTime next = everyQuarter.next(LocalDateTime.of(2026, 1, 1, 10, 7));
/// ```
///
/// Local time and daylight saving time: [next] works on the wall clock. A
/// time inside the hour skipped in spring is moved forward by the
/// [DateTime] constructor (02:30 becomes 03:30); a time inside the hour
/// repeated in autumn matches once.
final class CronExpression {
  CronExpression._(
    this.expression,
    this._seconds,
    this._minutes,
    this._hours,
    this._daysOfMonth,
    this._months,
    this._daysOfWeek,
  );

  /// Parses [expression]; throws a [FormatException] naming the field
  /// that is wrong.
  ///
  /// ```dart
  /// CronExpression.parse('0 0 * * * *'); // every hour
  /// CronExpression.parse('@daily');      // 0 0 0 * * *
  /// CronExpression.parse('0 0 25 * * *'); // FormatException: hour ...
  /// ```
  factory CronExpression.parse(String expression) {
    final text = expression.trim();
    final expanded = _macros[text.toLowerCase()] ?? text;
    final fields = expanded.split(RegExp(r'\s+'));
    if (fields.length != 6) {
      throw FormatException(
        'A cron expression has 6 fields (second minute hour day-of-month '
        'month day-of-week), found ${fields.length} in "$expression"',
        expression,
      );
    }
    _Bits field(
      int index,
      String name,
      int min,
      int max, [
      Map<String, int> names = const {},
    ]) {
      try {
        return _parseBits(fields[index], min, max, names);
      } on FormatException catch (error) {
        throw FormatException(
          'Invalid cron expression "$expression": $name field '
          '"${fields[index]}": ${error.message}',
          expression,
        );
      }
    }

    T special<T>(String name, String value, T Function() parse) {
      try {
        return parse();
      } on FormatException catch (error) {
        throw FormatException(
          'Invalid cron expression "$expression": $name field "$value": '
          '${error.message}',
          expression,
        );
      }
    }

    return CronExpression._(
      expression,
      field(0, 'second', 0, 59),
      field(1, 'minute', 0, 59),
      field(2, 'hour', 0, 23),
      special('day-of-month', fields[3], () => _DayOfMonth.parse(fields[3])),
      field(4, 'month', 1, 12, _monthNames),
      special('day-of-week', fields[5], () => _DayOfWeek.parse(fields[5])),
    );
  }

  /// Whether [expression] can be parsed.
  ///
  /// ```dart
  /// CronExpression.isValid('0 0 * * * *'); // true
  /// CronExpression.isValid('0 0 * *');     // false
  /// ```
  static bool isValid(String expression) {
    try {
      CronExpression.parse(expression);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// The source text.
  final String expression;

  final _Bits _seconds;
  final _Bits _minutes;
  final _Bits _hours;
  final _DayOfMonth _daysOfMonth;
  final _Bits _months;
  final _DayOfWeek _daysOfWeek;

  static const _macros = {
    '@yearly': '0 0 0 1 1 *',
    '@annually': '0 0 0 1 1 *',
    '@monthly': '0 0 0 1 * *',
    '@weekly': '0 0 0 * * 0',
    '@daily': '0 0 0 * * *',
    '@midnight': '0 0 0 * * *',
    '@hourly': '0 0 * * * *',
  };

  /// The first matching time strictly after [after] (whole seconds), in
  /// the time zone of [after] (local or UTC); `null` when the expression
  /// never matches again (e.g. `0 0 0 30 2 *`, February 30th).
  ///
  /// ```dart
  /// CronExpression.parse('0 0 12 * * *')
  ///     .next(DateTime(2026, 3, 1, 12)); // 2026-03-02 12:00:00
  /// ```
  DateTime? next(DateTime after) {
    final utc = after.isUtc;
    // Wall-clock fields; whole seconds, strictly after `after`.
    var year = after.year;
    var month = after.month;
    var day = after.day;
    var hour = after.hour;
    var minute = after.minute;
    var second = after.second + 1;
    final lastYear = year + 400; // the calendar repeats every 400 years

    while (year <= lastYear) {
      // Normalize the carries of the previous step.
      if (second > 59) {
        second = 0;
        minute++;
      }
      if (minute > 59) {
        minute = 0;
        hour++;
      }
      if (hour > 23) {
        hour = 0;
        day++;
      }
      if (day > _daysIn(year, month)) {
        day = 1;
        month++;
      }
      if (month > 12) {
        month = 1;
        year++;
        continue;
      }

      if (!_months.contains(month)) {
        final nextMonth = _months.nextFrom(month);
        if (nextMonth == null) {
          year++;
          month = _months.first;
        } else {
          month = nextMonth;
        }
        day = 1;
        hour = 0;
        minute = 0;
        second = 0;
        continue;
      }
      if (!_daysOfMonth.matches(year, month, day) ||
          !_daysOfWeek.matches(year, month, day)) {
        day++;
        hour = 0;
        minute = 0;
        second = 0;
        continue;
      }
      if (!_hours.contains(hour)) {
        final nextHour = _hours.nextFrom(hour);
        if (nextHour == null) {
          day++;
          hour = 0;
        } else {
          hour = nextHour;
        }
        minute = 0;
        second = 0;
        continue;
      }
      if (!_minutes.contains(minute)) {
        final nextMinute = _minutes.nextFrom(minute);
        if (nextMinute == null) {
          hour++;
          minute = 0;
        } else {
          minute = nextMinute;
        }
        second = 0;
        continue;
      }
      if (!_seconds.contains(second)) {
        final nextSecond = _seconds.nextFrom(second);
        if (nextSecond == null) {
          minute++;
          second = 0;
        } else {
          second = nextSecond;
        }
        continue;
      }
      final result = utc
          ? DateTime.utc(year, month, day, hour, minute, second)
          : DateTime(year, month, day, hour, minute, second);
      if (result.isAfter(after)) {
        return result;
      }
      // Only possible around a DST change: keep searching.
      second++;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is CronExpression && other.expression == expression;

  @override
  int get hashCode => expression.hashCode;

  @override
  String toString() => expression;
}

const _monthNames = {
  'JAN': 1,
  'FEB': 2,
  'MAR': 3,
  'APR': 4,
  'MAY': 5,
  'JUN': 6,
  'JUL': 7,
  'AUG': 8,
  'SEP': 9,
  'OCT': 10,
  'NOV': 11,
  'DEC': 12,
};

// Cron day-of-week values: 0 and 7 are Sunday.
const _dayNames = {
  'SUN': 0,
  'MON': 1,
  'TUE': 2,
  'WED': 3,
  'THU': 4,
  'FRI': 5,
  'SAT': 6,
};

int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;

// ISO weekday (1 = Monday ... 7 = Sunday), independent of the time zone.
int _weekday(int year, int month, int day) =>
    DateTime.utc(year, month, day).weekday;

/// The values of one field as a bit set.
final class _Bits {
  _Bits(this._bits, this.min, this.max);

  final int _bits; // bit n set = value n allowed (values up to 59)
  final int min;
  final int max;

  bool contains(int value) => value >= 0 && (_bits >> value) & 1 == 1;

  int get first => nextFrom(min)!;

  /// The smallest allowed value >= [value], or `null`.
  int? nextFrom(int value) {
    for (var v = value; v <= max; v++) {
      if (contains(v)) {
        return v;
      }
    }
    return null;
  }

  bool get isAll {
    for (var v = min; v <= max; v++) {
      if (!contains(v)) {
        return false;
      }
    }
    return true;
  }
}

int _value(String text, int min, int max, Map<String, int> names) {
  final upper = text.toUpperCase();
  final value = names[upper] ?? int.tryParse(text);
  if (value == null) {
    throw FormatException(
      "'$text' is not a number${names.isEmpty ? '' : ' or a name'}",
    );
  }
  if (value < min || value > max) {
    throw FormatException('$value is out of range $min-$max');
  }
  return value;
}

/// `*`, `?`, values, lists, ranges and steps of [min]..[max].
_Bits _parseBits(
  String field,
  int min,
  int max,
  Map<String, int> names, {
  bool allowQuestionMark = false,
}) {
  var bits = 0;
  for (final part in field.split(',')) {
    if (part.isEmpty) {
      throw const FormatException('empty list element');
    }
    var range = part;
    var step = 1;
    final slash = part.indexOf('/');
    if (slash >= 0) {
      range = part.substring(0, slash);
      final stepText = part.substring(slash + 1);
      final parsed = int.tryParse(stepText);
      if (parsed == null || parsed <= 0) {
        throw FormatException("step '$stepText' must be a positive number");
      }
      step = parsed;
    }
    int from;
    int to;
    if (range == '*' || (range == '?' && allowQuestionMark)) {
      from = min;
      to = max;
    } else if (range.contains('-')) {
      final [start, end, ...rest] = range.split('-');
      if (rest.isNotEmpty || start.isEmpty || end.isEmpty) {
        throw FormatException("'$range' is not a range");
      }
      from = _value(start, min, max, names);
      to = _value(end, min, max, names);
      if (from > to) {
        throw FormatException(
          "range '$range' goes backwards (ranges cannot wrap around)",
        );
      }
    } else {
      from = _value(range, min, max, names);
      // `5/15`: from 5 to the end, every 15.
      to = slash >= 0 ? max : from;
    }
    for (var v = from; v <= to; v += step) {
      bits |= 1 << v;
    }
  }
  return _Bits(bits, min, max);
}

/// The day-of-month field: values or one special (`L`, `L-n`, `nW`, `LW`).
sealed class _DayOfMonth {
  static _DayOfMonth parse(String field) {
    final upper = field.toUpperCase();
    if (upper == 'L') {
      return const _LastDay(0);
    }
    if (upper == 'LW') {
      return const _LastWeekday();
    }
    final lastMinus = RegExp(r'^L-(\d+)$').firstMatch(upper);
    if (lastMinus != null) {
      final offset = int.parse(lastMinus[1]!);
      if (offset > 30) {
        throw FormatException('offset $offset is out of range 0-30');
      }
      return _LastDay(offset);
    }
    final weekday = RegExp(r'^(\d+)W$').firstMatch(upper);
    if (weekday != null) {
      return _NearestWeekday(_value(weekday[1]!, 1, 31, const {}));
    }
    if (upper.contains('L') || upper.contains('W') || upper.contains('#')) {
      throw const FormatException(
        "'L', 'W' and '#' are allowed as L, L-n, nW or LW only, not in lists",
      );
    }
    return _DayValues(
      _parseBits(field, 1, 31, const {}, allowQuestionMark: true),
    );
  }

  bool matches(int year, int month, int day);
}

final class _DayValues implements _DayOfMonth {
  _DayValues(this.bits);

  final _Bits bits;

  @override
  bool matches(int year, int month, int day) => bits.contains(day);
}

final class _LastDay implements _DayOfMonth {
  const _LastDay(this.offset);

  final int offset;

  @override
  bool matches(int year, int month, int day) =>
      day == _daysIn(year, month) - offset;
}

final class _LastWeekday implements _DayOfMonth {
  const _LastWeekday();

  @override
  bool matches(int year, int month, int day) {
    var last = _daysIn(year, month);
    while (_weekday(year, month, last) > DateTime.friday) {
      last--;
    }
    return day == last;
  }
}

final class _NearestWeekday implements _DayOfMonth {
  const _NearestWeekday(this.target);

  final int target;

  @override
  bool matches(int year, int month, int day) {
    final length = _daysIn(year, month);
    if (target > length) {
      return false; // `31W` in a 30-day month: no match, as in Quartz
    }
    var result = target;
    switch (_weekday(year, month, target)) {
      case DateTime.saturday:
        // Friday before, or Monday after when the 1st is a Saturday.
        result = target == 1 ? 3 : target - 1;
      case DateTime.sunday:
        // Monday after, or Friday before when it is the last day.
        result = target == length ? target - 2 : target + 1;
    }
    return day == result;
  }
}

/// The day-of-week field: values or one special (`nL`, `n#k`).
sealed class _DayOfWeek {
  static _DayOfWeek parse(String field) {
    final upper = field.toUpperCase();
    final last = RegExp(r'^([0-7]|[A-Z]{3})L$').firstMatch(upper);
    if (last != null) {
      return _LastOfMonth(_isoDay(_value(last[1]!, 0, 7, _dayNames)));
    }
    final nth = RegExp(r'^([0-7]|[A-Z]{3})#(\d+)$').firstMatch(upper);
    if (nth != null) {
      final ordinal = int.parse(nth[2]!);
      if (ordinal < 1 || ordinal > 5) {
        throw FormatException('#$ordinal: the ordinal must be 1-5');
      }
      return _NthOfMonth(_isoDay(_value(nth[1]!, 0, 7, _dayNames)), ordinal);
    }
    if (upper.contains('#') || RegExp('L').hasMatch(upper)) {
      throw const FormatException(
        "'L' and '#' are allowed as 5L / FRIL or MON#2 only, not in lists",
      );
    }
    final bits = _parseBits(field, 0, 7, _dayNames, allowQuestionMark: true);
    return _WeekdayValues({
      for (var cron = 0; cron <= 7; cron++)
        if (bits.contains(cron)) _isoDay(cron),
    });
  }

  // Cron day (0 or 7 = Sunday, 1 = Monday) → ISO weekday (7 = Sunday).
  static int _isoDay(int cron) => cron == 0 ? 7 : cron;

  bool matches(int year, int month, int day);
}

final class _WeekdayValues implements _DayOfWeek {
  _WeekdayValues(this.days);

  final Set<int> days;

  @override
  bool matches(int year, int month, int day) =>
      days.contains(_weekday(year, month, day));
}

final class _LastOfMonth implements _DayOfWeek {
  const _LastOfMonth(this.weekday);

  final int weekday;

  @override
  bool matches(int year, int month, int day) =>
      _weekday(year, month, day) == weekday && day + 7 > _daysIn(year, month);
}

final class _NthOfMonth implements _DayOfWeek {
  const _NthOfMonth(this.weekday, this.ordinal);

  final int weekday;
  final int ordinal;

  @override
  bool matches(int year, int month, int day) =>
      _weekday(year, month, day) == weekday && (day - 1) ~/ 7 + 1 == ordinal;
}
