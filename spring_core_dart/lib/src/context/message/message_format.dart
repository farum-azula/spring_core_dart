import 'dart:typed_data';

/// Fills arguments into a message pattern such as `Hello {0}!`, using the
/// syntax of Java's `MessageFormat`, which message files are written in.
///
/// Message sources call it for every message with arguments, so the syntax
/// below is what you can write in `messages.properties`. Call it directly
/// to format a pattern that does not come from a message source.
///
/// Supported: `{0}` placeholders; quoting (`''` is a quote, text inside
/// single quotes is literal, a `}` outside a placeholder is literal);
/// `{0,number}` (`#,##0.###`), `{0,number,integer}`,
/// `{0,number,percent}`, `{0,number,<pattern>}` (`DecimalFormat` patterns:
/// `#`, `0`, `,` grouping, `.` fraction, quoted and plain literal prefixes
/// and suffixes, `%`, a `;negative` subpattern such as
/// `#,##0.00;(#,##0.00)`); `{0,date}` and `{0,time}` with the styles
/// `short`, `medium` (the default), `long`, `full` or a `SimpleDateFormat`
/// pattern (`{0,date,yyyy-MM-dd}`); `{0,choice,0#none|1#one|1<{0} many}`.
/// Numbers are rounded half-even on their exact binary value, like Java's
/// `DecimalFormat` (`0.15` with `#.#` gives `0.1`: the double is slightly
/// below 0.15). Missing arguments stay as `{n}`. As with Java's
/// `applyPattern`, the whole pattern is checked: a malformed element
/// throws even when its argument is missing or of another type.
///
/// With a [format] `locale` (`de`, `fr_CA`, ...), numbers use its decimal
/// and grouping separators (`1.234,5` in German, `1 234,5` in French);
/// without one, US symbols.
///
/// ```dart
/// MessageFormat.format('Hello {0}, {1}!', ['Ada', 'Linus']);
/// // Hello Ada, Linus!
/// MessageFormat.format("It''s {0,number,#.##}", [3.14159]); // It's 3.14
/// MessageFormat.format(
///   'There {0,choice,0#are no files|1#is one file|1<are {0} files}.',
///   [1234],
/// ); // There are 1,234 files.
/// MessageFormat.format('{0,number}', [1234.5], locale: 'de'); // 1.234,5
/// MessageFormat.format('{0,date,short}', [DateTime(2026, 1, 12)]); // 1/12/26
/// ```
///
/// Spring (Java) uses `java.text.MessageFormat`:
/// ```java
/// MessageFormat.format("Hello {0}, {1}!", "Ada", "Linus");
/// new MessageFormat("It''s {0,number,#.##}", Locale.US)
///     .format(new Object[] {3.14159});
/// ```
///
/// Differences from Java: `{0,number,percent}` and `currency` keep the US
/// layout (`26%`; currency gives two decimals without a symbol); the minus
/// sign is always `-`; dates and times use the US English styles and
/// names whatever the locale (`Jan 12, 2026`, `3:30 PM` with a plain space
/// where JDK 20+ prints a narrow no-break space), and a time zone is the
/// `DateTime`'s (`UTC` or the local zone's name); no scientific notation
/// (`0.##E0`).
abstract final class MessageFormat {
  /// Returns [pattern] with [args] filled in; numbers use the decimal and
  /// grouping separators of [locale] (US ones without it).
  ///
  /// Throws a `FormatException` for an unclosed `{`, a bad argument index,
  /// an unknown format type or an invalid number/choice pattern.
  static String format(String pattern, List<Object?> args, {String? locale}) =>
      _format(pattern, args, _symbolsFor(locale));

  static String _format(String pattern, List<Object?> args, _Symbols symbols) {
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
      // Outside a placeholder `}` is plain text, as in Java.
      if (quoted || c != '{') {
        out.write(c);
        i++;
        continue;
      }
      final end = _closingBrace(pattern, i);
      out.write(
        _formatArgument(pattern.substring(i + 1, end), args, pattern, symbols),
      );
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
    _Symbols symbols,
  ) {
    final parts = _splitSpec(spec);
    final index = int.tryParse(parts.first.trim());
    if (index == null || index < 0) {
      throw FormatException("Invalid argument index '${parts.first}'", pattern);
    }
    final type = parts.length > 1 ? parts[1].trim().toLowerCase() : null;
    final style = parts.length > 2 ? parts[2] : null;
    // Checked before the argument, like Java's applyPattern.
    final _NumberPattern? numberPattern;
    final List<_DatePart>? datePattern;
    final List<(double, bool, String)>? choices;
    switch (type) {
      case null:
        numberPattern = null;
        datePattern = null;
        choices = null;
      case 'number':
        numberPattern = _numberPattern(style?.trim(), pattern);
        datePattern = null;
        choices = null;
      case 'date' || 'time':
        numberPattern = null;
        datePattern = _DatePart.parse(
          _dateStyle(type == 'date', style?.trim()),
          pattern,
        );
        choices = null;
      case 'choice':
        numberPattern = null;
        datePattern = null;
        choices = [
          for (final option in _splitChoices(style ?? ''))
            _parseChoice(option, pattern),
        ];
      default:
        throw FormatException("Unknown format type '$type'", pattern);
    }
    if (index >= args.length) {
      return '{$index}';
    }
    final value = args[index];
    if (numberPattern != null) {
      return value is num
          ? _decimal(value, numberPattern, symbols)
          : _plain(value, symbols);
    }
    if (datePattern != null) {
      return value is DateTime
          ? _DatePart.formatAll(datePattern, value)
          : _plain(value, symbols);
    }
    if (choices != null) {
      return _choice(value, choices, args, pattern, symbols);
    }
    return _plain(value, symbols);
  }

  // The SimpleDateFormat pattern of a date or time [style] (Java's
  // DateFormat styles in US English, CLDR); a custom pattern as it is.
  static String _dateStyle(bool date, String? style) =>
      switch (style?.toLowerCase()) {
        null || '' || 'medium' => date ? 'MMM d, y' : 'h:mm:ss a',
        'short' => date ? 'M/d/yy' : 'h:mm a',
        'long' => date ? 'MMMM d, y' : 'h:mm:ss a z',
        'full' => date ? 'EEEE, MMMM d, y' : 'h:mm:ss a zzzz',
        _ => style!,
      };

  // Java's default for a date without a format type:
  // DateFormat.getDateTimeInstance(SHORT, SHORT).
  static final List<_DatePart> _plainDate = _DatePart.parse(
    'M/d/yy, h:mm a',
    '',
  );

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

  // `{n}` without a type: numbers like `{n,number}`, dates in Java's
  // short date-time style (`1/12/26, 3:30 PM`), everything else via
  // toString.
  static String _plain(Object? value, _Symbols symbols) => switch (value) {
    null => 'null',
    num() => _decimal(value, _NumberPattern.standard, symbols),
    DateTime() => _DatePart.formatAll(_plainDate, value),
    _ => value.toString(),
  };

  // The pattern of `{n,number[,style]}`.
  static _NumberPattern _numberPattern(String? style, String pattern) =>
      switch (style) {
        null || '' => _NumberPattern.standard,
        'integer' => _NumberPattern.integer,
        'percent' => _NumberPattern.percent,
        'currency' => _NumberPattern.currency,
        _ => _NumberPattern.parse(style, pattern),
      };

  /// Formats [value] with [format]: half-even rounding on the exact value,
  /// prefixes/suffixes of the positive or negative subpattern.
  static String _decimal(num value, _NumberPattern format, _Symbols symbols) {
    if (value is double && (value.isNaN || value.isInfinite)) {
      return value.isNaN ? 'NaN' : (value > 0 ? '∞' : '-∞');
    }
    final negative = value < 0;
    final magnitude = format.multiplier == 1
        ? value.abs()
        : value.abs() * format.multiplier;
    // Round to maxFraction digits, then drop trailing zeros down to
    // minFraction and pad the integer part to minInteger.
    final rounded = _roundHalfEven(magnitude, format.maxFraction);
    var integerPart = rounded.contains('.')
        ? rounded.split('.').first
        : rounded;
    var fractionPart = rounded.contains('.') ? rounded.split('.').last : '';
    while (fractionPart.length > format.minFraction &&
        fractionPart.endsWith('0')) {
      fractionPart = fractionPart.substring(0, fractionPart.length - 1);
    }
    integerPart = integerPart.padLeft(format.minInteger, '0');
    // `#.#` style patterns print `.5` rather than `0.5`, like Java.
    if (format.minInteger == 0 &&
        integerPart == '0' &&
        fractionPart.isNotEmpty) {
      integerPart = '';
    }
    if (format.groupingSize > 0 && integerPart.length > format.groupingSize) {
      final groups = <String>[];
      var end = integerPart.length;
      while (end > 0) {
        final start = end - format.groupingSize < 0
            ? 0
            : end - format.groupingSize;
        groups.insert(0, integerPart.substring(start, end));
        end = start;
      }
      integerPart = groups.join(symbols.grouping);
    }
    final digits = fractionPart.isEmpty
        ? integerPart
        : '$integerPart${symbols.decimal}$fractionPart';
    // No `-0`: values that round to zero lose their sign.
    final isZero = !rounded.contains(RegExp('[1-9]'));
    if (negative && !isZero) {
      return '${format.negativePrefix}$digits${format.negativeSuffix}';
    }
    return '${format.prefix}$digits${format.suffix}';
  }

  // [value] (non-negative) rounded half-even to exactly [digits] fraction
  // digits, as a plain decimal string.
  static String _roundHalfEven(num value, int digits) {
    if (value is int) {
      return digits == 0 ? '$value' : '$value.${'0' * digits}';
    }
    final factor = BigInt.from(10).pow(digits);
    // Exact decimal expansion of the double, then banker's rounding.
    final (whole, frac) = _exactDecimal(value.toDouble());
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
    final point = text.length - digits;
    return digits == 0
        ? text
        : '${text.substring(0, point)}.${text.substring(point)}';
  }

  /// Integer and fraction digits of the exact binary value of [value]
  /// (non-negative and finite): `0.15` is
  /// `0.1499999999999999944488848768742172978818416595458984375`.
  static (String, String) _exactDecimal(double value) {
    if (value == 0) {
      return ('0', '');
    }
    final bytes = ByteData(8)..setFloat64(0, value);
    final high = bytes.getUint32(0);
    final low = bytes.getUint32(4);
    final exponentBits = (high >> 20) & 0x7FF;
    var mantissa = (BigInt.from(high & 0xFFFFF) << 32) | BigInt.from(low);
    final int exponent;
    if (exponentBits == 0) {
      exponent = -1074; // subnormal
    } else {
      mantissa |= BigInt.one << 52;
      exponent = exponentBits - 1075;
    }
    // value = mantissa × 2^exponent = mantissa × 5^k / 10^k for k = -exponent.
    if (exponent >= 0) {
      return ((mantissa << exponent).toString(), '');
    }
    final k = -exponent;
    final digits = (mantissa * BigInt.from(5).pow(k)).toString().padLeft(
      k + 1,
      '0',
    );
    final whole = digits.substring(0, digits.length - k);
    final fraction = digits
        .substring(digits.length - k)
        .replaceFirst(RegExp(r'0+$'), '');
    return (whole, fraction);
  }

  /// Choice format: the last option whose limit the value
  /// reaches (`#` means `>=`, `<` means `>`), or the first option.
  static String _choice(
    Object? value,
    List<(double, bool, String)> options,
    List<Object?> args,
    String pattern,
    _Symbols symbols,
  ) {
    if (value is! num) {
      throw FormatException('choice format requires a number', pattern);
    }
    if (options.isEmpty) {
      return '';
    }
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
    return _format(options[index].$3, args, symbols);
  }

  // `limit#text`, `limit<text` or `limit≤text` → (limit, strict, text).
  static (double, bool, String) _parseChoice(String option, String pattern) {
    final separator = RegExp('[#<≤]').firstMatch(option);
    if (separator == null) {
      throw FormatException("Invalid choice '$option'", pattern);
    }
    final limitText = option.substring(0, separator.start).trim();
    final limit = switch (limitText) {
      '∞' || 'Infinity' => double.infinity,
      '-∞' || '-Infinity' => double.negativeInfinity,
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

  // Decimal and grouping separators of [locale] (CLDR, as Java uses them);
  // US symbols for other and missing locales.
  static _Symbols _symbolsFor(String? locale) {
    if (locale == null || locale.trim().isEmpty) {
      return _us;
    }
    final parts = locale.trim().replaceAll('-', '_').split('_');
    final language = parts.first.toLowerCase();
    final region = parts
        .skip(1)
        .where((p) => p.length == 2 || p.length == 3 && int.tryParse(p) != null)
        .firstOrNull
        ?.toUpperCase();
    if (_regionSymbols['${language}_$region'] case final symbols?) {
      return symbols;
    }
    return _languageSymbols[language] ?? _us;
  }

  static const ({String decimal, String grouping}) _us = (
    decimal: '.',
    grouping: ',',
  );
  static const ({String decimal, String grouping}) _dotGrouping = (
    decimal: ',',
    grouping: '.',
  );
  static const ({String decimal, String grouping}) _spaceGrouping = (
    decimal: ',',
    grouping: ' ',
  );

  static const _languageSymbols = <String, _Symbols>{
    'de': _dotGrouping,
    'es': _dotGrouping,
    'it': _dotGrouping,
    'nl': _dotGrouping,
    'pt': _dotGrouping,
    'id': _dotGrouping,
    'tr': _dotGrouping,
    'da': _dotGrouping,
    'el': _dotGrouping,
    'ro': _dotGrouping,
    'hr': _dotGrouping,
    'sl': _dotGrouping,
    'sr': _dotGrouping,
    'vi': _dotGrouping,
    'ca': _dotGrouping,
    'fr': (decimal: ',', grouping: ' '),
    'ru': _spaceGrouping,
    'uk': _spaceGrouping,
    'be': _spaceGrouping,
    'pl': _spaceGrouping,
    'cs': _spaceGrouping,
    'sk': _spaceGrouping,
    'sv': _spaceGrouping,
    'nb': _spaceGrouping,
    'no': _spaceGrouping,
    'fi': _spaceGrouping,
    'hu': _spaceGrouping,
    'bg': _spaceGrouping,
    'et': _spaceGrouping,
    'lt': _spaceGrouping,
    'lv': _spaceGrouping,
    'kk': _spaceGrouping,
  };

  static const _regionSymbols = <String, _Symbols>{
    'de_CH': (decimal: '.', grouping: '’'),
    'de_LI': (decimal: '.', grouping: '’'),
    'it_CH': (decimal: '.', grouping: '’'),
    'pt_PT': _spaceGrouping,
    'es_MX': _us,
    'es_US': _us,
    'fr_CH': (decimal: ',', grouping: ' '),
  };
}

typedef _Symbols = ({String decimal, String grouping});

/// A parsed `DecimalFormat` pattern, as used by `{0,number,...}`: digit
/// counts, grouping, and the literal prefix and suffix of the positive and
/// negative subpatterns.
final class _NumberPattern {
  const _NumberPattern({
    required this.minInteger,
    required this.minFraction,
    required this.maxFraction,
    required this.groupingSize,
    this.prefix = '',
    this.suffix = '',
    this.negativePrefix = '-',
    this.negativeSuffix = '',
    this.multiplier = 1,
  });

  final int minInteger;
  final int minFraction;
  final int maxFraction;

  /// Digits per group between grouping separators; 0 for no grouping.
  final int groupingSize;
  final String prefix;
  final String suffix;
  final String negativePrefix;
  final String negativeSuffix;

  /// What the value is multiplied by before formatting: 100 for `%`,
  /// 1000 for `‰`, else 1.
  final int multiplier;

  /// The format of `{0,number}`: `#,##0.###`.
  static const standard = _NumberPattern(
    minInteger: 1,
    minFraction: 0,
    maxFraction: 3,
    groupingSize: 3,
  );

  /// The format of `{0,number,integer}`: `#,##0` with half-even rounding.
  static const integer = _NumberPattern(
    minInteger: 1,
    minFraction: 0,
    maxFraction: 0,
    groupingSize: 3,
  );

  /// The format of `{0,number,percent}`: `#,##0%`.
  static const percent = _NumberPattern(
    minInteger: 1,
    minFraction: 0,
    maxFraction: 0,
    groupingSize: 3,
    suffix: '%',
    negativeSuffix: '%',
    multiplier: 100,
  );

  /// The format of `{0,number,currency}`: `#,##0.00`, without a currency
  /// symbol.
  static const currency = _NumberPattern(
    minInteger: 1,
    minFraction: 2,
    maxFraction: 2,
    groupingSize: 3,
  );

  static const _digitChars = '#0123456789,.';

  /// Parses a `DecimalFormat` pattern such as `#,##0.00;(#,##0.00)` or
  /// `'#'0 units`.
  static _NumberPattern parse(String style, String pattern) {
    final subpatterns = _splitNegative(style);
    final positive = _parseSubpattern(subpatterns.first, style, pattern);
    final negative = subpatterns.length > 1
        ? _parseSubpattern(subpatterns[1], style, pattern)
        : null;
    final number = positive.number;
    final dot = number.indexOf('.');
    final integerPart = dot < 0 ? number : number.substring(0, dot);
    final fractionPart = dot < 0 ? '' : number.substring(dot + 1);
    if (integerPart.replaceAll(',', '').isEmpty && fractionPart.isEmpty) {
      throw FormatException("Invalid number pattern '$style'", pattern);
    }
    // Java's DecimalFormat.applyPattern: one decimal separator, no
    // grouping in the fraction, `#` before `0` in the integer part and
    // after it in the fraction, no empty group.
    if (fractionPart.contains('.') || fractionPart.contains(',')) {
      throw FormatException("Malformed number pattern '$style'", pattern);
    }
    if (RegExp('0[,]*#').hasMatch(integerPart) ||
        RegExp('#0').hasMatch(fractionPart) ||
        integerPart.endsWith(',') ||
        integerPart.contains(',,')) {
      throw FormatException("Malformed number pattern '$style'", pattern);
    }
    final lastComma = integerPart.lastIndexOf(',');
    final multiplier = positive.multiplier;
    return _NumberPattern(
      minInteger: RegExp('[0-9]').allMatches(integerPart).length,
      minFraction: RegExp('[0-9]').allMatches(fractionPart).length,
      maxFraction: fractionPart.length,
      groupingSize: lastComma < 0 ? 0 : integerPart.length - lastComma - 1,
      prefix: positive.prefix,
      suffix: positive.suffix,
      // Without a negative subpattern: a minus before the positive one.
      negativePrefix: negative?.prefix ?? '-${positive.prefix}',
      negativeSuffix: negative?.suffix ?? positive.suffix,
      multiplier: multiplier,
    );
  }

  // Splits at the `;` outside quotes.
  static List<String> _splitNegative(String style) {
    var quoted = false;
    for (var i = 0; i < style.length; i++) {
      if (style[i] == "'") {
        quoted = !quoted;
      } else if (!quoted && style[i] == ';') {
        return [style.substring(0, i), style.substring(i + 1)];
      }
    }
    return [style];
  }

  // Prefix (literal), number part (digits, `,`, `.`) and suffix (literal)
  // of one subpattern; quotes make special characters literal (`''` is a
  // quote).
  static ({String prefix, String number, String suffix, int multiplier})
  _parseSubpattern(String subpattern, String style, String pattern) {
    final prefix = StringBuffer();
    final number = StringBuffer();
    final suffix = StringBuffer();
    var multiplier = 1;
    var phase = 0; // 0 prefix, 1 number, 2 suffix
    var i = 0;
    while (i < subpattern.length) {
      final c = subpattern[i];
      final literal = phase == 0 ? prefix : suffix;
      if (c == "'") {
        final end = subpattern.indexOf("'", i + 1);
        if (end == i + 1) {
          (phase == 1 ? suffix : literal).write("'");
          if (phase == 1) {
            phase = 2;
          }
          i += 2;
          continue;
        }
        if (end < 0) {
          throw FormatException("Unterminated quote in '$style'", pattern);
        }
        if (phase == 1) {
          phase = 2;
        }
        (phase == 0 ? prefix : suffix).write(subpattern.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      if (phase < 2 && _digitChars.contains(c)) {
        phase = 1;
        number.write(c);
      } else {
        if (phase == 1) {
          phase = 2;
        }
        if (c == '%') {
          multiplier = 100;
        } else if (c == '‰') {
          multiplier = 1000;
        } else if (c == 'E' && phase == 2 && suffix.isEmpty) {
          throw FormatException(
            "Scientific notation is not supported: '$style'",
            pattern,
          );
        }
        (phase == 0 ? prefix : suffix).write(c);
      }
      i++;
    }
    return (
      prefix: prefix.toString(),
      number: number.toString(),
      suffix: suffix.toString(),
      multiplier: multiplier,
    );
  }
}

/// One element of a `SimpleDateFormat` pattern, as used by
/// `{0,date,...}`: a run of one letter (`yyyy`, `MMM`) or literal text.
final class _DatePart {
  const _DatePart(this.letter, this.count, this.text);

  /// The pattern letter, or `null` for literal [text].
  final String? letter;
  final int count;
  final String text;

  // Java's SimpleDateFormat letters this formatter knows.
  static const _letters = 'GyYMLdDEuaHkKhmsSzZX';

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];
  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
    'Sunday',
  ];

  /// Parses [style]; an unknown letter or an unterminated quote throws,
  /// like Java's `SimpleDateFormat`.
  static List<_DatePart> parse(String style, String pattern) {
    final parts = <_DatePart>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        parts.add(_DatePart(null, 0, literal.toString()));
        literal.clear();
      }
    }

    var i = 0;
    while (i < style.length) {
      final c = style[i];
      if (c == "'") {
        if (i + 1 < style.length && style[i + 1] == "'") {
          literal.write("'");
          i += 2;
          continue;
        }
        final end = style.indexOf("'", i + 1);
        if (end < 0) {
          throw FormatException("Unterminated quote in '$style'", pattern);
        }
        literal.write(style.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      if (RegExp('[a-zA-Z]').hasMatch(c)) {
        if (!_letters.contains(c)) {
          throw FormatException(
            "Illegal pattern character '$c' in '$style'",
            pattern,
          );
        }
        var end = i;
        while (end < style.length && style[end] == c) {
          end++;
        }
        flush();
        parts.add(_DatePart(c, end - i, ''));
        i = end;
        continue;
      }
      literal.write(c);
      i++;
    }
    flush();
    return parts;
  }

  static String formatAll(List<_DatePart> parts, DateTime value) =>
      parts.map((part) => part._format(value)).join();

  static String _pad(int value, int count) =>
      value.toString().padLeft(count, '0');

  String _format(DateTime d) {
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return switch (letter) {
      null => text,
      'G' => 'AD',
      'y' || 'Y' => count == 2 ? _pad(d.year % 100, 2) : _pad(d.year, count),
      'M' || 'L' => switch (count) {
        1 || 2 => _pad(d.month, count),
        3 => _months[d.month - 1].substring(0, 3),
        _ => _months[d.month - 1],
      },
      'd' => _pad(d.day, count),
      'D' => _pad(
        DateTime.utc(
              d.year,
              d.month,
              d.day,
            ).difference(DateTime.utc(d.year)).inDays +
            1,
        count,
      ),
      'E' =>
        count <= 3
            ? _days[d.weekday - 1].substring(0, 3)
            : _days[d.weekday - 1],
      'u' => _pad(d.weekday, count),
      'a' => d.hour < 12 ? 'AM' : 'PM',
      'H' => _pad(d.hour, count),
      'k' => _pad(d.hour == 0 ? 24 : d.hour, count),
      'K' => _pad(d.hour % 12, count),
      'h' => _pad(hour12, count),
      'm' => _pad(d.minute, count),
      's' => _pad(d.second, count),
      'S' => _pad(d.millisecond, count),
      'z' => d.isUtc ? 'UTC' : d.timeZoneName,
      'Z' => _offset(d, colon: false, zulu: false),
      'X' => _offset(d, colon: count >= 3, zulu: true, hoursOnly: count == 1),
      _ => '',
    };
  }

  // `+0200`, `+02:00`, `+02` or `Z`.
  static String _offset(
    DateTime d, {
    required bool colon,
    required bool zulu,
    bool hoursOnly = false,
  }) {
    final offset = d.isUtc ? Duration.zero : d.timeZoneOffset;
    if (offset == Duration.zero && zulu) {
      return 'Z';
    }
    final minutes = offset.inMinutes.abs();
    final sign = offset.isNegative ? '-' : '+';
    final hours = _pad(minutes ~/ 60, 2);
    if (hoursOnly) {
      return '$sign$hours';
    }
    return '$sign$hours${colon ? ':' : ''}${_pad(minutes % 60, 2)}';
  }
}
