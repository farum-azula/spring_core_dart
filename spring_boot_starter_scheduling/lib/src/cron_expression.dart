// Rows of Markdown tables and sample log lines in documentation cannot wrap.
// ignore_for_file: lines_longer_than_80_chars
/// A repeating calendar schedule written as a cron expression, such as
/// `0 0 9 * * MON-FRI` for 9:00 on working days; [next] gives the next
/// matching time.
///
/// Most applications only write the text in `@Scheduled(cron: ...)`,
/// which reads it with this class. Use it in code to check an expression
/// a user typed ([isValid]), to show when something runs next, or to
/// build a `CronTrigger` for `TaskScheduler.schedule`.
///
/// The format is Spring's: six fields, starting with the seconds (Unix
/// cron has five):
///
/// ```text
/// ┌───────────── second (0-59)
/// │ ┌───────────── minute (0-59)
/// │ │ ┌───────────── hour (0-23)
/// │ │ │ ┌───────────── day of month (1-31)
/// │ │ │ │ ┌───────────── month (1-12 or JAN-DEC)
/// │ │ │ │ │ ┌───────────── day of week (0-7 or MON-SUN; 0 and 7 are Sunday)
/// │ │ │ │ │ │
/// * * * * * *
/// ```
///
/// Every field takes `*`, a value, a list (`1,15,30`), a range (`9-17`)
/// and a step (`*/5`, `0-30/10`, `5/15` = from 5 every 15). Names are
/// case-insensitive. `?` means "any" in the day fields.
///
/// Days of the week are numbered like in Spring (and `DateTime.weekday`):
/// MON = 1 ... SAT = 6, SUN = 7, and 0 is Sunday too. Sunday at the start
/// of a range counts as 0, so `SAT-SUN`, `MON-SUN` and `SUN-TUE` all work;
/// `*/2` is MON, WED, FRI, SUN.
///
/// The day fields also take Quartz-style specials, alone or in a list
/// (`1,L`, `MON#1,MON#3`, `MON-FRI,SATL`):
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
/// (`FRI-MON` is rejected; write `FRI-SUN,MON`).
///
/// ```dart
/// // A settings screen shows when the report will be sent next.
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
/// Local time and daylight saving time, as in Spring: [next] gives the
/// first moment the wall clock shows a matching time. A time inside the
/// hour skipped when clocks go forward does not exist and is skipped (a
/// daily `0 30 2 * * *` does not run that day); a time inside the hour
/// repeated when clocks go back matches twice, once before and once after
/// the change. `#k` in the day of week takes 1 to 5; Spring also accepts
/// larger ordinals, which never match.
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

  /// Reads [expression], six fields or a macro, ignoring surrounding
  /// spaces. Throws a [FormatException] that names the wrong field, so the
  /// message can be shown to whoever wrote the expression.
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
      special(
        'day-of-month',
        fields[3],
        () => _DayField.daysOfMonth(fields[3]),
      ),
      field(4, 'month', 1, 12, _monthNames),
      special('day-of-week', fields[5], () => _DayField.daysOfWeek(fields[5])),
    );
  }

  /// Whether [expression] is a valid cron expression, for checking user
  /// input without catching the [FormatException] of [CronExpression.parse].
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

  /// The text the expression was read from, as given (a macro stays a
  /// macro). Two expressions are equal when these texts are equal.
  final String expression;

  final _Bits _seconds;
  final _Bits _minutes;
  final _Bits _hours;
  final _DayField _daysOfMonth;
  final _Bits _months;
  final _DayField _daysOfWeek;

  static const _macros = {
    '@yearly': '0 0 0 1 1 *',
    '@annually': '0 0 0 1 1 *',
    '@monthly': '0 0 0 1 * *',
    '@weekly': '0 0 0 * * 0',
    '@daily': '0 0 0 * * *',
    '@midnight': '0 0 0 * * *',
    '@hourly': '0 0 * * * *',
  };

  /// The first matching time strictly after [after], in whole seconds and
  /// in the time zone of [after] (local or UTC). Returns `null` when the
  /// expression never matches, such as `0 0 0 30 2 *` (February 30th).
  ///
  /// ```dart
  /// CronExpression.parse('0 0 12 * * *')
  ///     .next(DateTime(2026, 3, 1, 12)); // 2026-03-02 12:00:00
  /// ```
  DateTime? next(DateTime after) {
    // Whole seconds, strictly after `after`, in wall-clock order.
    final first = _search(
      after,
      DateTime.utc(
        after.year,
        after.month,
        after.day,
        after.hour,
        after.minute,
        after.second + 1,
      ),
    );
    if (after.isUtc) {
      return first;
    }
    // Clocks going back soon: the wall clock shows again times that the
    // search above has passed (the second 02:30 after the first one).
    // Those come after the change; search again from it, as Spring does.
    final back = _clocksGoBackAfter(after);
    if (back == null || (first != null && first.isBefore(back))) {
      return first;
    }
    final repeated = _search(
      back.subtract(const Duration(microseconds: 1)),
      DateTime.utc(
        back.year,
        back.month,
        back.day,
        back.hour,
        back.minute,
        back.second,
      ),
    );
    if (first == null || (repeated != null && repeated.isBefore(first))) {
      return repeated;
    }
    return first;
  }

  /// The first time after [after] that matches, searching the wall-clock
  /// fields upwards from those of [from] (inclusive; read as UTC fields).
  DateTime? _search(DateTime after, DateTime from) {
    final utc = after.isUtc;
    var year = from.year;
    var month = from.month;
    var day = from.day;
    var hour = from.hour;
    var minute = from.minute;
    var second = from.second;
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
          : _localAfter(after, year, month, day, hour, minute, second);
      if (result != null && result.isAfter(after)) {
        return result;
      }
      // Only around a daylight saving change: the wall-clock time does not
      // exist (clocks went forward over it) or came before `after`.
      second++;
    }
    return null;
  }

  /// The earliest local time after [after] at which the wall clock shows
  /// the given fields; `null` when there is none.
  ///
  /// Usually there is exactly one. In the hour skipped when clocks go
  /// forward there is none, and the time is skipped (Spring too: no run on
  /// that day, where [DateTime.new] would move it forward). In the hour
  /// repeated when clocks go back there are two.
  static DateTime? _localAfter(
    DateTime after,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
  ) {
    final guess = DateTime(year, month, day, hour, minute, second);
    final wall = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
    ).microsecondsSinceEpoch;
    DateTime? best;
    for (final offset in {
      guess.timeZoneOffset,
      guess.subtract(_maxClockChange).timeZoneOffset,
      guess.add(_maxClockChange).timeZoneOffset,
    }) {
      final candidate = DateTime.fromMicrosecondsSinceEpoch(
        wall - offset.inMicroseconds,
      );
      if (candidate.year == year &&
          candidate.month == month &&
          candidate.day == day &&
          candidate.hour == hour &&
          candidate.minute == minute &&
          candidate.second == second &&
          candidate.isAfter(after) &&
          (best == null || candidate.isBefore(best))) {
        best = candidate;
      }
    }
    return best;
  }

  /// The moment the clocks go back within [_maxClockChange] after [after]
  /// (the local time's offset gets smaller), or `null`.
  static DateTime? _clocksGoBackAfter(DateTime after) {
    final offset = after.timeZoneOffset;
    if (after.add(_maxClockChange).timeZoneOffset >= offset) {
      return null;
    }
    // Changes happen at whole seconds; find the first second after it.
    var low = (after.microsecondsSinceEpoch / Duration.microsecondsPerSecond)
        .floor();
    var high = low + _maxClockChange.inSeconds + 1;
    DateTime at(int seconds) =>
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    while (high - low > 1) {
      final middle = low + (high - low) ~/ 2;
      if (at(middle).timeZoneOffset < offset) {
        high = middle;
      } else {
        low = middle;
      }
    }
    return at(high);
  }

  @override
  bool operator ==(Object other) =>
      other is CronExpression && other.expression == expression;

  @override
  int get hashCode => expression.hashCode;

  @override
  String toString() => expression;
}

/// More than any daylight saving change (two hours at most, Antarctica's
/// Troll station).
const _maxClockChange = Duration(hours: 3);

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

// Day-of-week names as in Spring's `CronField`: MON = 1 ... SUN = 7 (the
// numbers of java.time and of `DateTime.weekday`); 0 is Sunday too.
const _dayNames = {
  'MON': 1,
  'TUE': 2,
  'WED': 3,
  'THU': 4,
  'FRI': 5,
  'SAT': 6,
  'SUN': 7,
};

int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;

// ISO weekday (1 = Monday ... 7 = Sunday), independent of the time zone.
int _weekday(int year, int month, int day) =>
    DateTime.utc(year, month, day).weekday;

/// The values of one field as a bit set.
final class _Bits {
  _Bits(this._values, this.min, this.max);

  // _values[n] = value n allowed (values up to 59). A list rather than the
  // bits of an int: dart2js shifts are 32-bit, so `1 << 45` is lost on the
  // web.
  final List<bool> _values;
  final int min;
  final int max;

  bool contains(int value) =>
      value >= 0 && value < _values.length && _values[value];

  /// The values allowed by this field or [other].
  _Bits union(_Bits other) => _Bits(
    List.generate(
      _values.length,
      (v) => _values[v] || other.contains(v),
      growable: false,
    ),
    min,
    max,
  );

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
///
/// With [dayOfWeek] the rules of Spring's `BitsCronField` for the day of
/// week apply: `*` and `?` are 1-7 (so `*/2` is MON, WED, FRI, SUN), 0 is
/// Sunday like 7, and 7 at the start of a range means 0 (`SUN-TUE`).
_Bits _parseBits(
  String field,
  int min,
  int max,
  Map<String, int> names, {
  bool allowQuestionMark = false,
  bool dayOfWeek = false,
}) {
  final values = List.filled(max + 1, false);
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
      from = dayOfWeek ? 1 : min;
      to = max;
    } else if (range.contains('-')) {
      final [start, end, ...rest] = range.split('-');
      if (rest.isNotEmpty || start.isEmpty || end.isEmpty) {
        throw FormatException("'$range' is not a range");
      }
      from = _value(start, min, max, names);
      to = _value(end, min, max, names);
      if (dayOfWeek && from == 7) {
        from = 0; // Sunday at the start of a range: `SUN-TUE`, `7-2`
      }
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
      values[v] = true;
    }
  }
  if (dayOfWeek && values[0]) {
    // 0 is Sunday, like 7
    values
      ..[0] = false
      ..[7] = true;
  }
  return _Bits(values, min, max);
}

/// A day field (day of month or day of week): values and Quartz-style
/// specials, also mixed in a list (`1,L`, `MON#1,MON#3`), like Spring's
/// `CompositeCronField`. A day matches when any element does.
final class _DayField {
  _DayField(this._values, this._specials, this._valueOf);

  final _Bits? _values;
  final List<_DaySpecial> _specials;
  // The value of a date in this field: the day of month or the weekday.
  final int Function(int year, int month, int day) _valueOf;

  bool matches(int year, int month, int day) =>
      (_values?.contains(_valueOf(year, month, day)) ?? false) ||
      _specials.any((special) => special.matches(year, month, day));

  /// The day-of-month field: values and `L`, `L-n`, `nW`, `LW`.
  static _DayField daysOfMonth(String field) => _parse(
    field.toUpperCase(),
    isSpecial: (element) => element.contains('L') || element.contains('W'),
    parseSpecial: _dayOfMonthSpecial,
    parseValues: (values) =>
        _parseBits(values, 1, 31, const {}, allowQuestionMark: true),
    valueOf: (year, month, day) => day,
  );

  /// The day-of-week field: values (MON = 1 ... SUN = 7, 0 = Sunday) and
  /// `nL`, `n#k`.
  static _DayField daysOfWeek(String field) => _parse(
    field.toUpperCase(),
    isSpecial: (element) => element.contains('L') || element.contains('#'),
    parseSpecial: _dayOfWeekSpecial,
    parseValues: (values) => _parseBits(
      values,
      0,
      7,
      _dayNames,
      allowQuestionMark: true,
      dayOfWeek: true,
    ),
    valueOf: _weekday,
  );

  // Without specials the field is one set of values; with them, every
  // list element is parsed on its own (Spring's `CronField.parseList`).
  static _DayField _parse(
    String field, {
    required bool Function(String element) isSpecial,
    required _DaySpecial Function(String element) parseSpecial,
    required _Bits Function(String values) parseValues,
    required int Function(int year, int month, int day) valueOf,
  }) {
    if (!isSpecial(field)) {
      return _DayField(parseValues(field), const [], valueOf);
    }
    _Bits? values;
    final specials = <_DaySpecial>[];
    for (final element in field.split(',')) {
      if (element.isEmpty) {
        throw const FormatException('empty list element');
      }
      if (isSpecial(element)) {
        specials.add(parseSpecial(element));
      } else {
        final bits = parseValues(element);
        values = values?.union(bits) ?? bits;
      }
    }
    return _DayField(values, specials, valueOf);
  }

  static _DaySpecial _dayOfMonthSpecial(String element) {
    if (element == 'L') {
      return const _LastDay(0);
    }
    if (element == 'LW') {
      return const _LastWeekday();
    }
    final lastMinus = RegExp(r'^L-(\d+)$').firstMatch(element);
    if (lastMinus != null) {
      final offset = int.parse(lastMinus[1]!);
      if (offset < 1 || offset > 30) {
        throw FormatException("'$element': the offset after L- must be 1-30");
      }
      return _LastDay(offset);
    }
    final weekday = RegExp(r'^(\d+)W$').firstMatch(element);
    if (weekday != null) {
      return _NearestWeekday(_value(weekday[1]!, 1, 31, const {}));
    }
    throw FormatException(
      "'$element' is not one of the day-of-month specials L, L-n, nW, LW",
    );
  }

  static _DaySpecial _dayOfWeekSpecial(String element) {
    final last = RegExp(r'^(\w+)L$').firstMatch(element);
    if (last != null) {
      return _LastOfMonth(_isoDay(last[1]!));
    }
    final nth = RegExp(r'^(\w+)#(\d+)$').firstMatch(element);
    if (nth != null) {
      final ordinal = int.parse(nth[2]!);
      if (ordinal < 1 || ordinal > 5) {
        throw FormatException('#$ordinal: the ordinal must be 1-5');
      }
      return _NthOfMonth(_isoDay(nth[1]!), ordinal);
    }
    throw FormatException(
      "'$element' is not one of the day-of-week specials nL (FRIL) or n#k "
      '(MON#2)',
    );
  }

  // The day of week before `L` / `#` (0-7 or a name) as ISO weekday.
  static int _isoDay(String text) {
    final day = _value(text, 0, 7, _dayNames);
    return day == 0 ? DateTime.sunday : day;
  }
}

/// A Quartz-style special of a day field (`L`, `LW`, `15W`, `FRIL`,
/// `MON#2`): matches certain days of each month.
sealed class _DaySpecial {
  bool matches(int year, int month, int day);
}

final class _LastDay implements _DaySpecial {
  const _LastDay(this.offset);

  final int offset;

  @override
  bool matches(int year, int month, int day) =>
      day == _daysIn(year, month) - offset;
}

final class _LastWeekday implements _DaySpecial {
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

final class _NearestWeekday implements _DaySpecial {
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

final class _LastOfMonth implements _DaySpecial {
  const _LastOfMonth(this.weekday);

  final int weekday;

  @override
  bool matches(int year, int month, int day) =>
      _weekday(year, month, day) == weekday && day + 7 > _daysIn(year, month);
}

final class _NthOfMonth implements _DaySpecial {
  const _NthOfMonth(this.weekday, this.ordinal);

  final int weekday;
  final int ordinal;

  @override
  bool matches(int year, int month, int day) =>
      _weekday(year, month, day) == weekday && (day - 1) ~/ 7 + 1 == ordinal;
}
