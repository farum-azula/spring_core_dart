/// Formats messages with the `MessageFormat` syntax Spring message sources
/// use (locale-neutral).
///
/// Supported: `{0}` placeholders; quoting (`''` is a quote, text inside
/// single quotes is literal); `{0,number}` (`#,##0.###`), `{0,number,integer}`,
/// `{0,number,percent}`, `{0,number,<pattern>}` with `#`, `0`, `,`, `.`
/// and literal prefix/suffix; `{0,date}`, `{0,time}` (ISO-8601 parts);
/// `{0,choice,0#none|1#one|1<{0} many}`. Numbers without a format are
/// grouped like Spring's default output (`1,234`). Missing arguments stay
/// as `{n}`.
///
/// ```dart
/// MessageFormat.format('Hello {0}, {1}!', ['Ada', 'Linus']);
/// // Hello Ada, Linus!
/// MessageFormat.format("It''s {0,number,#.##}", [3.14159]); // It's 3.14
/// MessageFormat.format(
///   'There {0,choice,0#are no files|1#is one file|1<are {0} files}.',
///   [1234],
/// ); // There are 1,234 files.
/// ```
///
/// Spring (Java) uses `java.text.MessageFormat`:
/// ```java
/// MessageFormat.format("Hello {0}, {1}!", "Ada", "Linus");
/// new MessageFormat("It''s {0,number,#.##}", Locale.US)
///     .format(new Object[] {3.14159});
/// ```
///
/// Differences from Java: output is always US-style (`,` grouping, `.`
/// decimals); `{0,number,currency}` gives two decimals without a symbol;
/// dates and times use ISO-8601 parts instead of locale styles, and date
/// styles (`short`, `long`, custom patterns) are ignored.
abstract final class MessageFormat {
  /// Formats [pattern] with [args].
  ///
  /// Throws a `FormatException` for unmatched braces, a bad argument index,
  /// an unknown format type or an invalid number/choice pattern.
  static String format(String pattern, List<Object?> args) {
    final out = StringBuffer();
    var i = 0;
    var quoted = false;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == "'") {
        // `''` is a literal quote both inside and outside quoted text; a
        // single quote toggles quoting.
        if (i + 1 < pattern.length && pattern[i + 1] == "'") {
          out.write("'");
          i += 2;
          continue;
        }
        quoted = !quoted;
        i++;
        continue;
      }
      if (quoted || c != '{') {
        if (!quoted && c == '}') {
          throw FormatException('Unmatched braces in the pattern', pattern, i);
        }
        out.write(c);
        i++;
        continue;
      }
      final end = _closingBrace(pattern, i);
      out.write(_formatArgument(pattern.substring(i + 1, end), args, pattern));
      i = end + 1;
    }
    // An unterminated quote makes the rest literal (same as Spring).
    return out.toString();
  }

  // Index of the `}` matching the `{` at [open], counting nested braces
  // (choice sub-patterns) and ignoring braces in quotes.
  static int _closingBrace(String pattern, int open) {
    var depth = 0;
    var quoted = false;
    for (var i = open; i < pattern.length; i++) {
      final c = pattern[i];
      if (c == "'") {
        quoted = !quoted;
      } else if (!quoted && c == '{') {
        depth++;
      } else if (!quoted && c == '}') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    throw FormatException('Unmatched braces in the pattern', pattern, open);
  }

  // Formats one `{index[,type[,style]]}` element (without the braces).
  static String _formatArgument(
    String spec,
    List<Object?> args,
    String pattern,
  ) {
    final parts = _splitSpec(spec);
    final index = int.tryParse(parts.first.trim());
    if (index == null || index < 0) {
      throw FormatException("Invalid argument index '${parts.first}'", pattern);
    }
    if (index >= args.length) {
      return '{$index}';
    }
    final value = args[index];
    final type = parts.length > 1 ? parts[1].trim().toLowerCase() : null;
    final style = parts.length > 2 ? parts[2] : null;
    switch (type) {
      case null:
        return _plain(value);
      case 'number':
        return _number(value, style?.trim(), pattern);
      case 'date':
        return value is DateTime
            ? value.toIso8601String().split('T').first
            : '$value';
      case 'time':
        return value is DateTime
            ? value.toIso8601String().split('T').last.substring(0, 8)
            : '$value';
      case 'choice':
        return _choice(value, style ?? '', args, pattern);
      default:
        throw FormatException("Unknown format type '$type'", pattern);
    }
  }

  /// Splits `index,type,style` at the first two top-level commas (not in
  /// nested `{...}` or quotes).
  static List<String> _splitSpec(String spec) =>
      _splitTopLevel(spec, ',', limit: 2);

  // Splits [text] at [separator] outside nested braces and quoted text,
  // after at most [limit] separators. Quotes are kept in the parts.
  static List<String> _splitTopLevel(
    String text,
    String separator, {
    int? limit,
  }) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      if (limit != null && parts.length >= limit) {
        break;
      }
      final c = text[i];
      if (c == "'") {
        quoted = !quoted;
      } else if (quoted) {
        continue;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
      } else if (c == separator && depth == 0) {
        parts.add(text.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }

  // `{n}` without a type: numbers like `{n,number}`, dates as
  // `yyyy-MM-dd HH:mm`, everything else via toString.
  static String _plain(Object? value) => switch (value) {
    null => 'null',
    num() => _decimal(value, minFraction: 0, maxFraction: 3, grouping: true),
    DateTime() =>
      value.toIso8601String().replaceFirst('T', ' ').substring(0, 16),
    _ => value.toString(),
  };

  // `{n,number[,style]}`; non-numbers are formatted as plain values.
  static String _number(Object? value, String? style, String pattern) {
    if (value is! num) {
      return _plain(value);
    }
    switch (style) {
      case null || '':
        return _decimal(value, minFraction: 0, maxFraction: 3, grouping: true);
      case 'integer':
        return _decimal(value, minFraction: 0, maxFraction: 0, grouping: true);
      case 'percent':
        return '${_decimal(value * 100, minFraction: 0, maxFraction: 0, grouping: true)}%';
      case 'currency':
        return _decimal(value, minFraction: 2, maxFraction: 2, grouping: true);
      default:
        return _customDecimal(value, style, pattern);
    }
  }

  /// Decimal pattern subset: optional literal prefix/suffix, `#`/`0`
  /// digits, `,` grouping, `.` fraction, `%` multiplies by 100.
  static String _customDecimal(num value, String style, String pattern) {
    // Groups: literal prefix, integer digits, fraction digits, suffix.
    final match = RegExp(r'^([^#0,.]*)([#0,]*)(?:\.([#0]*))?(.*)$')
        .firstMatch(style);
    if (match == null || (match[2]!.isEmpty && (match[3] ?? '').isEmpty)) {
      throw FormatException("Invalid number pattern '$style'", pattern);
    }
    final prefix = match[1]!;
    final integer = match[2]!;
    final fraction = match[3] ?? '';
    final suffix = match[4]!;
    final percent = suffix.contains('%') || prefix.contains('%');
    final minInteger = '0'.allMatches(integer).length;
    final text = _decimal(
      percent ? value * 100 : value,
      minFraction: '0'.allMatches(fraction).length,
      maxFraction: fraction.length,
      grouping: integer.contains(','),
      minInteger: minInteger,
    );
    return '$prefix$text$suffix';
  }

  /// Half-even rounding, as Spring's number formatting does.
  static String _decimal(
    num value, {
    required int minFraction,
    required int maxFraction,
    required bool grouping,
    int minInteger = 1,
  }) {
    if (value is double && (value.isNaN || value.isInfinite)) {
      return value.isNaN ? 'NaN' : (value > 0 ? '∞' : '-∞');
    }
    final negative = value < 0;
    // Round the magnitude to maxFraction digits, then drop trailing zeros
    // down to minFraction and pad the integer part to minInteger.
    final scaled = _roundHalfEven(value.abs(), maxFraction);
    var text = scaled;
    var integerPart = text.contains('.') ? text.split('.').first : text;
    var fractionPart = text.contains('.') ? text.split('.').last : '';
    while (fractionPart.length > minFraction && fractionPart.endsWith('0')) {
      fractionPart = fractionPart.substring(0, fractionPart.length - 1);
    }
    integerPart = integerPart.padLeft(minInteger, '0');
    // `#.#` style patterns print `.5` rather than `0.5`, like Java.
    if (minInteger == 0 && integerPart == '0' && fractionPart.isNotEmpty) {
      integerPart = '';
    }
    if (grouping) {
      integerPart = integerPart.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
    }
    text = fractionPart.isEmpty ? integerPart : '$integerPart.$fractionPart';
    // No `-0`: values that round to zero lose their sign.
    final isZero = RegExp(r'^[0.,]*$').hasMatch(text);
    return negative && !isZero ? '-$text' : text;
  }

  // [value] (non-negative) rounded half-even to exactly [digits] fraction
  // digits, as a plain decimal string.
  static String _roundHalfEven(num value, int digits) {
    if (value is int) {
      return digits == 0 ? '$value' : '$value.${'0' * digits}';
    }
    final factor = BigInt.from(10).pow(digits);
    // Exact decimal expansion of the double, then banker's rounding.
    final exact = _exactDecimal(value.toDouble());
    final (whole, frac) = exact;
    final kept = frac.padRight(digits + 1, '0');
    var units =
        BigInt.parse(whole) * factor +
        (digits == 0 ? BigInt.zero : BigInt.parse(kept.substring(0, digits)));
    // Decide on the dropped digits: > half rounds up, exactly half rounds
    // to the even neighbour.
    final rest = kept.substring(digits);
    final firstRest = int.parse(rest[0]);
    final restIsHalf =
        firstRest == 5 && rest.substring(1).replaceAll('0', '').isEmpty;
    if (firstRest > 5 ||
        (firstRest == 5 && !restIsHalf) ||
        (restIsHalf && units.isOdd)) {
      units += BigInt.one;
    }
    final text = units.toString().padLeft(digits + 1, '0');
    return digits == 0
        ? text
        : '${text.substring(0, text.length - digits)}.${text.substring(text.length - digits)}';
  }

  /// Integer and fraction digits of [value] as written by `toString`,
  /// expanded from exponent notation.
  static (String, String) _exactDecimal(double value) {
    var text = value.toString();
    if (text.contains('e') || text.contains('E')) {
      final [mantissa, exponentText] = text.toLowerCase().split('e');
      final exponent = int.parse(exponentText);
      final [whole, fraction] = mantissa.contains('.')
          ? mantissa.split('.')
          : [mantissa, ''];
      final digits = whole + fraction;
      final point = whole.length + exponent;
      // Dart only uses exponents below 1e-6 (point <= 0) and from 1e21 on
      // (point beyond the digits).
      text = point <= 0
          ? '0.${'0' * -point}$digits'
          : digits + '0' * (point - digits.length);
    }
    final [whole, fraction] = text.contains('.') ? text.split('.') : [text, ''];
    return (whole, fraction);
  }

  /// Choice format: the last option whose limit the value
  /// reaches (`#` means `>=`, `<` means `>`), or the first option.
  static String _choice(
    Object? value,
    String style,
    List<Object?> args,
    String pattern,
  ) {
    if (value is! num) {
      throw FormatException('choice format requires a number', pattern);
    }
    final options = [
      for (final option in _splitChoices(style)) _parseChoice(option, pattern),
    ];
    var index = 0;
    for (var i = 0; i < options.length; i++) {
      final (limit, strict, _) = options[i];
      if (!(strict ? value > limit : value >= limit)) {
        break;
      }
      index = i;
    }
    // The chosen text is formatted again, which resolves nested arguments
    // (as in Java) and removes the quoting of literal `|`, `#` and `{`.
    return format(options[index].$3, args);
  }

  // `limit#text`, `limit<text` or `limit≤text` → (limit, strict, text).
  static (double, bool, String) _parseChoice(String option, String pattern) {
    final separator = RegExp('[#<\u2264]').firstMatch(option);
    if (separator == null) {
      throw FormatException("Invalid choice '$option'", pattern);
    }
    final limitText = option.substring(0, separator.start).trim();
    final limit = switch (limitText) {
      '\u221E' || 'Infinity' => double.infinity,
      '-\u221E' || '-Infinity' => double.negativeInfinity,
      _ =>
        double.tryParse(limitText) ??
            (throw FormatException(
              "Invalid choice limit '$limitText'",
              pattern,
            )),
    };
    return (limit, separator[0] == '<', option.substring(separator.end));
  }

  // Splits choice options at top-level `|` (not inside nested `{...}` or
  // quotes, so `'|'` is a literal bar).
  static List<String> _splitChoices(String style) => _splitTopLevel(style, '|');
}
