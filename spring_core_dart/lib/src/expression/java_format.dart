// Java's String.format for `T(String).format(...)` and `'...'.formatted(...)`
// in SpEL (internal; not exported).

import 'package:spring_core_dart/src/expression/spel_numbers.dart';

/// An integral real number (a Java `double` such as `2.0`) handed to
/// [javaFormat]. Internal.
///
/// On the web `2.0` is an `int` at run time, so the evaluator wraps the
/// arguments it knows to be real: `%s` then prints `2.0` like Java's
/// `Double.toString`, `%f` / `%e` take its value and `%d` rejects it,
/// like a Java double.
final class JavaReal {
  /// Wraps the real number [value].
  const JavaReal(this.value);

  /// The number, integral.
  final int value;

  @override
  String toString() => javaRealString(value);
}

final _specifier = RegExp(r'%(\d+\$)?([-#+ 0,(<]*)?(\d+)?(\.\d+)?([a-zA-Z%])');

/// [format] filled with [args] like Java's `String.format`
/// (`Locale.ROOT`), for SpEL's `String.format(...)` and
/// `'...'.formatted(...)`. Internal. Supported:
/// `%s %S %d %f %e %E %x %X %o %c %b %B %n %%`, argument indexes (`%2$s`),
/// the flags `-`, `0`, `+`, space and `,`, width and precision.
///
/// Throws [FormatException] for an unknown conversion or a missing
/// argument (Java's `IllegalFormatException`).
String javaFormat(String format, List<Object?> args) {
  final out = StringBuffer();
  var next = 0;
  var end = 0;
  for (final match in _specifier.allMatches(format)) {
    out.write(format.substring(end, match.start));
    end = match.end;
    final conversion = match[5]!;
    if (conversion == 'n') {
      out.write('\n');
      continue;
    }
    if (conversion == '%') {
      out.write('%');
      continue;
    }
    final flags = match[2] ?? '';
    final width = match[3] == null ? null : int.parse(match[3]!);
    final precision = match[4] == null
        ? null
        : int.parse(match[4]!.substring(1));
    final index = match[1] == null
        ? next++
        : int.parse(match[1]!.substring(0, match[1]!.length - 1)) - 1;
    if (index < 0 || index >= args.length) {
      throw FormatException("Format specifier '${match[0]}' has no argument");
    }
    final arg = args[index];
    var text = switch (conversion) {
      's' || 'S' => _truncate('$arg', precision),
      'b' || 'B' => _truncate('${arg is bool ? arg : arg != null}', precision),
      'c' || 'C' => arg is int ? String.fromCharCode(arg) : '$arg',
      'd' => _integer(arg, flags, match[0]!),
      'x' || 'X' => _radix(arg, 16, match[0]!),
      'o' => _radix(arg, 8, match[0]!),
      'f' => _signed(
        _number(arg, match[0]!).toStringAsFixed(precision ?? 6),
        flags,
        grouping: flags.contains(','),
      ),
      'e' ||
      'E' => _signed(_exponent(_number(arg, match[0]!), precision ?? 6), flags),
      _ => throw FormatException("Unknown format conversion '${match[0]}'"),
    };
    if (conversion == conversion.toUpperCase() && conversion != 'd') {
      text = text.toUpperCase();
    }
    if (width != null && text.length < width) {
      if (flags.contains('-')) {
        text = text.padRight(width);
      } else if (flags.contains('0') && 'dxXofeE'.contains(conversion)) {
        final sign = text.startsWith(RegExp('[-+ ]')) ? text[0] : '';
        text =
            sign +
            text.substring(sign.length).padLeft(width - sign.length, '0');
      } else {
        text = text.padLeft(width);
      }
    }
    out.write(text);
  }
  out.write(format.substring(end));
  return out.toString();
}

String _truncate(String text, int? precision) =>
    precision == null || text.length <= precision
    ? text
    : text.substring(0, precision);

num _number(Object? arg, String specifier) => arg is JavaReal
    ? arg.value
    : arg is num
    ? arg
    : throw FormatException("'$specifier' needs a number, got $arg");

String _integer(Object? arg, String flags, String specifier) {
  if (arg is! int) {
    throw FormatException("'$specifier' needs an integer, got $arg");
  }
  return _signed('$arg', flags, grouping: flags.contains(','));
}

String _radix(Object? arg, int radix, String specifier) {
  if (arg is! int) {
    throw FormatException("'$specifier' needs an integer, got $arg");
  }
  // Java prints negative values as their unsigned 64-bit form.
  return arg < 0
      ? BigInt.from(arg).toUnsigned(64).toRadixString(radix)
      : arg.toRadixString(radix);
}

// `1.234560e+01`, Java's `%e`.
String _exponent(num value, int precision) {
  final text = value.toStringAsExponential(precision);
  final e = text.indexOf('e');
  final exponent = text.substring(e + 2);
  return '${text.substring(0, e)}e${text[e + 1]}${exponent.padLeft(2, '0')}';
}

String _signed(String digits, String flags, {bool grouping = false}) {
  var text = digits;
  if (grouping) {
    final negative = text.startsWith('-');
    final body = negative ? text.substring(1) : text;
    final dot = body.indexOf('.');
    final whole = dot < 0 ? body : body.substring(0, dot);
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    text =
        '${negative ? '-' : ''}$grouped${dot < 0 ? '' : body.substring(dot)}';
  }
  if (!text.startsWith('-')) {
    if (flags.contains('+')) {
      text = '+$text';
    } else if (flags.contains(' ')) {
      text = ' $text';
    }
  }
  return text;
}
