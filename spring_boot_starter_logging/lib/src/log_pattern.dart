// Rows of Markdown tables and sample log lines in documentation cannot wrap.
// ignore_for_file: lines_longer_than_80_chars
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_logging/src/platform.dart' as platform;

/// Turns a [SpringLogRecord] into text with a Logback pattern, like
/// Logback's `PatternLayout` with Spring Boot's converters
/// (`logging.pattern.console`, `logging.pattern.file`).
///
/// | Conversion | Output |
/// |---|---|
/// | `%d`, `%date{pattern[, UTC]}` | time; Java pattern letters (`yyyy-MM-dd'T'HH:mm:ss.SSSXXX`), `ISO8601` (the default, `yyyy-MM-dd HH:mm:ss,SSS`) |
/// | `%p`, `%le`, `%level` | level: `TRACE DEBUG INFO WARN ERROR` |
/// | `%c`, `%lo`, `%logger{n}` | logger name, abbreviated to about `n` characters like Logback (`n.c.Checkout`); `{0}`: the last segment |
/// | `%m`, `%msg`, `%message` | message |
/// | `%t`, `%thread` | isolate name (`main`) |
/// | `%X{key}`, `%X{key:-default}` | one field; `%X` all fields as ` {k=v, ...}` (nothing if none) |
/// | `%ex`, `%exception`, `%throwable{n}` (also `%xEx`, `%rEx`) | error and stack trace (`{short}`, `{full}` or `n` lines) |
/// | `%wEx` | the same between line breaks (Spring Boot) |
/// | `%nopex` | no error output |
/// | `%clr(...){color}` | colours its content (Spring Boot, with `spring.output.ansi.enabled`); without a colour by level |
/// | `%red(...)`, `%boldRed(...)`, `%gray(...)`, ... `%highlight(...)` | Logback's colours (always ANSI, like Logback): `black red green yellow blue magenta cyan white gray` and `bold...`; `%highlight` by level (error bold red, warn red, info blue) |
/// | `%replace(...){regex, replacement}` | its content with every match replaced (`$1` for groups) |
/// | `%kvp{DOUBLE\|SINGLE\|NONE}` | the fields as `key="value"` pairs, separated by spaces |
/// | `%prefix(...)` | each conversion inside as `name=value` (`level=INFO`, `%X{key}` as `key=...`) |
/// | `%property{key}` | a variable or property (`null` when there is none) |
/// | `%esb(...){VAR}` | `[value] ` of its content or of the variable, nothing when empty (Spring Boot) |
/// | `%(...)` | groups content for a format modifier |
/// | `%r`, `%relative` | milliseconds since the logging started |
/// | `%seq` | record sequence number |
/// | `%n` | line break |
/// | `%%`, `\%` | `%` |
///
/// Format modifiers as in Logback: `%5p` pads left, `%-5p` pads right,
/// `%.10logger` keeps the last 10 characters, `%.-10logger` the first 10;
/// `%-40.40logger{39}` combines them. `${NAME}` and `${NAME:-default}`
/// are replaced first, from `variables`, `PID` and `lookup`.
///
/// As in Logback, a pattern without an error conversion still prints the
/// error, on the lines after the record (`%nopex` turns that off). The
/// text may end with a line break (`%n`); appenders add their own, so
/// [formatLine] drops it.
///
/// ```dart
/// final pattern = LogPattern('%d{HH:mm:ss} %-5p [%logger{20}] %m');
/// pattern.format(record); // 12:00:01 INFO  [n.checkout.Payments] order placed
/// ```
///
/// Throws a [FormatException] for anything it cannot parse: an unknown
/// conversion word, an unclosed `(`, an unknown colour, date letter or
/// variable.
final class LogPattern {
  /// Parses [pattern]. `${NAME}` variables come from [variables], then
  /// `PID`, then [lookup] (for example `Environment.getProperty`). [ansi]
  /// turns on the colours of `%clr`.
  LogPattern(
    String pattern, {
    Map<String, String> variables = const {},
    String? Function(String name)? lookup,
    bool ansi = false,
  }) : this._(pattern, ansi, _Parser.compile(pattern, variables, lookup, ansi));

  LogPattern._(this.pattern, this.ansi, (List<_Render>, bool) compiled)
    : _parts = compiled.$1,
      _handlesErrors = compiled.$2;

  /// Spring Boot's console pattern (`CONSOLE_LOG_PATTERN`), with the
  /// record's fields (`%X`) after the message.
  ///
  /// ```text
  /// 2026-03-07T09:05:02.042+01:00  INFO 4711 --- [shop] [           main] n.checkout.Payments                      : paid {order=42}
  /// ```
  static const defaultConsolePattern =
      r"%clr(%d{${LOG_DATEFORMAT_PATTERN:-yyyy-MM-dd'T'HH:mm:ss.SSSXXX}}){faint} "
      r'%clr(${LOG_LEVEL_PATTERN:-%5p}) %clr(${PID:-}){magenta} '
      '%clr(--- %esb(){APPLICATION_NAME}%esb{APPLICATION_GROUP}[%15.15t] '
      r'${LOG_CORRELATION_PATTERN:-}){faint}%clr(%-40.40logger{39}){cyan} '
      r'%clr(:){faint} %m%X%n${LOG_EXCEPTION_CONVERSION_WORD:-%wEx}';

  /// Spring Boot's file pattern (`FILE_LOG_PATTERN`), with the record's
  /// fields (`%X`) after the message.
  static const defaultFilePattern =
      r"%d{${LOG_DATEFORMAT_PATTERN:-yyyy-MM-dd'T'HH:mm:ss.SSSXXX}} "
      r'${LOG_LEVEL_PATTERN:-%5p} ${PID:-} --- '
      '%esb(){APPLICATION_NAME}%esb{APPLICATION_GROUP}[%t] '
      r'${LOG_CORRELATION_PATTERN:-}%-40.40logger{39} : '
      r'%m%X%n${LOG_EXCEPTION_CONVERSION_WORD:-%wEx}';

  /// The source pattern.
  final String pattern;

  /// Whether `%clr` writes ANSI colour codes.
  final bool ansi;

  final List<_Render> _parts;

  // Whether the pattern has an error conversion (%ex, %wEx, %nopex, ...);
  // otherwise errors are appended, like Logback's EnsureExceptionHandling.
  final bool _handlesErrors;

  /// The formatted record, as Logback writes it (it may end with a line
  /// break).
  String format(SpringLogRecord record) {
    final buffer = StringBuffer();
    for (final part in _parts) {
      buffer.write(part(record));
    }
    if (!_handlesErrors && record.error != null) {
      if (!buffer.toString().endsWith('\n')) {
        buffer.write('\n');
      }
      buffer.write(_throwable(record, null));
    }
    return buffer.toString();
  }

  /// [format] without one final line break: what an appender writing one
  /// line per record (`print`, a file) writes before its own line break.
  String formatLine(SpringLogRecord record) {
    final text = format(record);
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }

  /// The display name of [level] (`WARN`, not `WARNING`).
  static String levelName(SpringLogLevel level) => switch (level) {
    SpringLogLevel.warning => 'WARN',
    _ => level.name.toUpperCase(),
  };

  /// Shortens a logger name to about [targetLength] characters like
  /// Logback's `%logger{n}`: leading segments become their first letter,
  /// from the left, until the name fits; the last segment is kept.
  /// `0` keeps only the last segment.
  ///
  /// ```dart
  /// LogPattern.abbreviate('mainPackage.sub.sample.Bar', 15); // m.s.sample.Bar
  /// LogPattern.abbreviate('mainPackage.sub.sample.Bar', 0);  // Bar
  /// ```
  static String abbreviate(String name, int targetLength) {
    if (targetLength <= 0) {
      return name.substring(name.lastIndexOf('.') + 1);
    }
    if (name.length <= targetLength) {
      return name;
    }
    final rightMostDot = name.lastIndexOf('.');
    if (rightMostDot < 0) {
      return name;
    }
    // Logback 1.5's TargetLengthBasedClassNameAbbreviator.
    final lastSegmentLength = name.length - rightMostDot;
    var leftTarget = targetLength - lastSegmentLength;
    if (leftTarget < 0) {
      leftTarget = 0;
    }
    final maxPossibleTrim = (name.length - lastSegmentLength) - leftTarget;
    final buffer = StringBuffer();
    var trimmed = 0;
    var inDotState = true;
    var i = 0;
    for (; i < rightMostDot; i++) {
      final c = name[i];
      if (c == '.') {
        if (trimmed >= maxPossibleTrim) {
          break;
        }
        buffer.write(c);
        inDotState = true;
      } else if (inDotState) {
        buffer.write(c);
        inDotState = false;
      } else {
        trimmed++;
      }
    }
    buffer.write(name.substring(i));
    return buffer.toString();
  }

  @override
  String toString() => 'LogPattern($pattern)';
}

typedef _Render = String Function(SpringLogRecord record);

// The origin of %relative: when the first pattern was created, or the
// time of an earlier record (records buffered before the logging system
// started), so the value is never negative — Logback counts from the
// birth of its context, before any event.
DateTime _start = DateTime.now();

int _relative(SpringLogRecord record) {
  if (record.time.isBefore(_start)) {
    _start = record.time;
  }
  return record.time.difference(_start).inMilliseconds;
}

String _fields(SpringLogRecord record) {
  if (record.fields.isEmpty) {
    return '';
  }
  final fields = [
    for (final MapEntry(:key, :value) in record.fields.entries) '$key=$value',
  ].join(', ');
  return ' {$fields}';
}

// Logback's ThrowableProxyConverter: the error, then the stack trace
// (at most [depth] lines), each line ending with a line break.
String _throwable(SpringLogRecord record, int? depth) {
  final error = record.error;
  if (error == null) {
    return '';
  }
  final stack = record.stackTrace?.toString().trimRight() ?? '';
  final lines = stack.isEmpty ? const <String>[] : stack.split('\n');
  final kept = depth == null ? lines : lines.take(depth);
  return '${['$error', ...kept].join('\n')}\n';
}

const _ansiCodes = {
  'black': '30',
  'red': '31',
  'green': '32',
  'yellow': '33',
  'blue': '34',
  'magenta': '35',
  'cyan': '36',
  'white': '37',
  'bright_black': '90',
  'bright_red': '91',
  'bright_green': '92',
  'bright_yellow': '93',
  'bright_blue': '94',
  'bright_magenta': '95',
  'bright_cyan': '96',
  'bright_white': '97',
  'faint': '2',
};

final class _FormatInfo {
  _FormatInfo(
    this.min,
    this.max, {
    required this.leftPad,
    required this.leftTruncate,
  });

  final int? min;
  final int? max;
  final bool leftPad;
  final bool leftTruncate;

  String apply(String text) {
    final max = this.max;
    if (max != null && text.length > max) {
      return leftTruncate
          ? text.substring(text.length - max)
          : text.substring(0, max);
    }
    final min = this.min;
    if (min != null && text.length < min) {
      return leftPad ? text.padLeft(min) : text.padRight(min);
    }
    return text;
  }
}

// `${NAME}` / `${NAME:-default}` (and Spring's `${NAME:default}`), replaced
// before parsing, as Logback does when it reads its configuration.
final class _Variables {
  _Variables(this.source, this.values, this.lookup);

  final String source;
  final Map<String, String> values;
  final String? Function(String name)? lookup;

  String? operator [](String name) {
    if (values[name] case final value?) {
      return value;
    }
    if (name == 'PID') {
      if (platform.processId case final pid?) {
        return '$pid';
      }
    }
    try {
      return lookup?.call(name);
    } on Object {
      return null;
    }
  }

  String substitute(String text, [int depth = 0]) {
    if (depth > 10) {
      throw FormatException(
        'Log pattern variables nest too deeply (a cycle?)',
        source,
      );
    }
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c == r'\' && i + 1 < text.length) {
        out.write(text.substring(i, i + 2));
        i += 2;
      } else if (c == r'$' && i + 1 < text.length && text[i + 1] == '{') {
        final end = _closingBrace(text, i + 1);
        if (end < 0) {
          throw FormatException(r"Unclosed '${' in log pattern", source);
        }
        out.write(_resolve(text.substring(i + 2, end), depth));
        i = end + 1;
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  String _resolve(String body, int depth) {
    var name = body;
    String? fallback;
    final colon = body.indexOf(':');
    if (colon >= 0) {
      name = body.substring(0, colon);
      fallback = body.startsWith(':-', colon)
          ? body.substring(colon + 2)
          : body.substring(colon + 1);
    }
    final value = this[name.trim()];
    if (value != null) {
      return substitute(value, depth + 1);
    }
    if (fallback != null) {
      return substitute(fallback, depth + 1);
    }
    throw FormatException(
      'Unknown variable \${$name} in log pattern (give a default: '
      '\${$name:-text})',
      source,
    );
  }

  static int _closingBrace(String text, int open) {
    var depth = 0;
    for (var i = open; i < text.length; i++) {
      switch (text[i]) {
        case r'\':
          i++;
        case '{':
          depth++;
        case '}':
          if (--depth == 0) {
            return i;
          }
      }
    }
    return -1;
  }
}

// Logback's PatternLayout names of the converters, for %prefix.
const _converterNames = {
  'd': 'date',
  'date': 'date',
  'p': 'level',
  'le': 'level',
  'level': 'level',
  'c': 'logger',
  'lo': 'logger',
  'logger': 'logger',
  'm': 'message',
  'msg': 'message',
  'message': 'message',
  't': 'thread',
  'thread': 'thread',
  'r': 'relative',
  'relative': 'relative',
  'seq': 'sequenceNumber',
};

// Logback's colour converters (ANSIConstants): foreground codes.
const _logbackColors = {
  'black': '30',
  'red': '31',
  'green': '32',
  'yellow': '33',
  'blue': '34',
  'magenta': '35',
  'cyan': '36',
  'white': '37',
  'gray': '1;30',
  'boldRed': '1;31',
  'boldGreen': '1;32',
  'boldYellow': '1;33',
  'boldBlue': '1;34',
  'boldMagenta': '1;35',
  'boldCyan': '1;36',
  'boldWhite': '1;37',
};

final class _Parser {
  _Parser(this.text, this.variables, this.ansi);

  // The %prefix name of a conversion's render function.
  static final _names = Expando<String>();

  static (List<_Render>, bool) compile(
    String pattern,
    Map<String, String> values,
    String? Function(String name)? lookup,
    bool ansi,
  ) {
    final variables = _Variables(pattern, values, lookup);
    final parser = _Parser(variables.substitute(pattern), variables, ansi);
    final parts = parser._sequence(nested: false);
    return (List.unmodifiable(parts), parser.handlesErrors);
  }

  final String text;
  final _Variables variables;
  final bool ansi;
  var _pos = 0;
  bool handlesErrors = false;

  Never _fail(String message) =>
      throw FormatException('$message in log pattern', variables.source);

  // Literals and conversions up to the end, or (nested) up to the `)`
  // closing the composite, which is left for the caller.
  List<_Render> _sequence({required bool nested}) {
    final parts = <_Render>[];
    final literal = StringBuffer();
    var parens = 0;
    void flush() {
      if (literal.isNotEmpty) {
        final value = literal.toString();
        parts.add((_) => value);
        literal.clear();
      }
    }

    while (_pos < text.length) {
      final c = text[_pos];
      if (c == r'\') {
        literal.write(_escape());
        continue;
      }
      if (c == '%') {
        flush();
        _pos++;
        parts.add(_conversion());
        continue;
      }
      if (nested && c == ')') {
        if (parens == 0) {
          flush();
          return parts;
        }
        parens--;
      } else if (nested && c == '(') {
        parens++;
      }
      literal.write(c);
      _pos++;
    }
    if (nested) {
      _fail("Unclosed '('");
    }
    flush();
    return parts;
  }

  String _escape() {
    if (_pos + 1 >= text.length) {
      _pos++;
      return r'\';
    }
    final next = text[_pos + 1];
    _pos += 2;
    return switch (next) {
      'n' => '\n',
      't' => '\t',
      '%' || '(' || ')' || r'\' || '{' || '}' || r'$' => next,
      _ => '\\$next',
    };
  }

  _Render _conversion() {
    if (_pos < text.length && text[_pos] == '%') {
      _pos++;
      return (_) => '%';
    }
    final info = _formatInfo();
    final start = _pos;
    while (_pos < text.length && _isWordChar(text[_pos], _pos == start)) {
      _pos++;
    }
    final word = start == _pos ? null : text.substring(start, _pos);
    List<_Render>? children;
    if (_pos < text.length && text[_pos] == '(') {
      _pos++;
      children = _sequence(nested: true);
      _pos++; // the closing ')'
    }
    String? option;
    if (_pos < text.length && text[_pos] == '{') {
      option = _option();
    }
    if (word == null && children == null) {
      _fail(
        _pos < text.length
            ? "Missing conversion word after '%' (before '${text[_pos]}')"
            : "Missing conversion word after '%' at the end",
      );
    }
    final render = word == null
        ? _concat(children!)
        : _converter(word, option, children);
    // The type gives the closure's parameter its type (strict-inference).
    // ignore: omit_local_variable_types
    final _Render result = info == null ? render : (r) => info.apply(render(r));
    if (word != null) {
      _names[result] = (word == 'X' || word == 'mdc') && option != null
          ? option.split(':-').first
          : _converterNames[word] ?? word;
    }
    return result;
  }

  static final _modifier = RegExp(r'(-)?(\d+)?(?:\.(-)?(\d+))?');

  static bool _isWordChar(String c, bool first) {
    final code = c.codeUnitAt(0);
    final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    return letter || (!first && ((code >= 48 && code <= 57) || c == '_'));
  }

  _FormatInfo? _formatInfo() {
    final match = _modifier.matchAsPrefix(text, _pos)!;
    if (match.end < text.length && text[match.end] == '.') {
      _fail("Bad format modifier '${match[0]}.'");
    }
    if (match.end == _pos) {
      return null;
    }
    final min = match[2];
    final max = match[4];
    if (min == null && max == null) {
      _fail("Bad format modifier '${match[0]}'");
    }
    _pos = match.end;
    return _FormatInfo(
      min == null ? null : int.parse(min),
      max == null ? null : int.parse(max),
      leftPad: match[1] == null,
      leftTruncate: match[3] == null,
    );
  }

  String _option() {
    _pos++; // '{'
    final start = _pos;
    String? quote;
    while (_pos < text.length) {
      final c = text[_pos];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
      } else if (c == "'" || c == '"') {
        quote = c;
      } else if (c == '}') {
        final option = text.substring(start, _pos);
        _pos++;
        return option;
      }
      _pos++;
    }
    _fail("Unclosed '{'");
  }

  static _Render _concat(List<_Render> parts) => (record) {
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write(part(record));
    }
    return buffer.toString();
  };

  _Render _converter(String word, String? option, List<_Render>? children) {
    _Render simple(_Render render) {
      if (children != null) {
        _fail('%$word does not take (...)');
      }
      return render;
    }

    switch (word) {
      case 'd' || 'date':
        return simple(_date(option));
      case 'p' || 'le' || 'level':
        return simple((r) => LogPattern.levelName(r.level));
      case 'c' || 'lo' || 'logger':
        final length = option == null ? null : int.tryParse(option.trim());
        if (option != null && option.trim().isNotEmpty && length == null) {
          _fail('%$word{$option}: the option is a length');
        }
        return simple(
          length == null
              ? (r) => r.loggerName
              : (r) => LogPattern.abbreviate(r.loggerName, length),
        );
      case 'm' || 'msg' || 'message':
        return simple((r) => r.message);
      case 'n':
        return simple((_) => '\n');
      case 't' || 'thread':
        return simple((_) => platform.isolateName);
      case 'X' || 'mdc':
        if (option == null || option.isEmpty) {
          return simple(_fields);
        }
        final separator = option.indexOf(':-');
        final key = separator < 0 ? option : option.substring(0, separator);
        final fallback = separator < 0 ? '' : option.substring(separator + 2);
        return simple((r) => '${r.fields[key] ?? fallback}');
      case 'seq':
        return simple((r) => '${r.sequence}');
      case 'r' || 'relative':
        // Reads the late field to initialize it.
        // ignore: unnecessary_statements
        _start; // initialized no later than the pattern
        return simple((r) => '${_relative(r)}');
      case 'ex' ||
          'exception' ||
          'throwable' ||
          'xEx' ||
          'xException' ||
          'xThrowable' ||
          'rEx' ||
          'rootException':
        handlesErrors = true;
        final depth = _depth(word, option);
        return simple((r) => _throwable(r, depth));
      case 'wEx' || 'wex':
        handlesErrors = true;
        final depth = _depth(word, option);
        return simple(
          (r) => r.error == null ? '' : '\n${_throwable(r, depth)}\n',
        );
      case 'nopex' || 'nopexception':
        handlesErrors = true;
        return simple((_) => '');
      case 'clr':
        if (children == null) {
          _fail('%clr needs (...) around the coloured text');
        }
        return _color(_concat(children), option);
      case 'highlight':
        final inner = _requireChildren(word, children);
        return (r) {
          final code = switch (r.level) {
            SpringLogLevel.error => '1;31',
            SpringLogLevel.warning => '31',
            SpringLogLevel.info => '34',
            _ => '39',
          };
          return '\x1B[${code}m${inner(r)}\x1B[0;39m';
        };
      case _ when _logbackColors.containsKey(word):
        final inner = _requireChildren(word, children);
        final code = _logbackColors[word];
        return (r) => '\x1B[${code}m${inner(r)}\x1B[0;39m';
      case 'replace':
        final inner = _requireChildren(word, children);
        final options = _splitOptions(option ?? '');
        if (options.length != 2) {
          _fail('%replace needs {regex, replacement}');
        }
        final RegExp regex;
        try {
          regex = RegExp(_unquote(options[0].trim()));
        } on FormatException catch (error) {
          _fail('%replace: invalid regex (${error.message})');
        }
        final replacement = _unquote(options[1].trim());
        return (r) => inner(r).replaceAllMapped(
          regex,
          (match) => _javaReplacement(match, replacement),
        );
      case 'kvp':
        final quote = switch (option?.trim().toUpperCase()) {
          null || '' || 'DOUBLE' => '"',
          'SINGLE' => "'",
          'NONE' => '',
          _ => _fail('%kvp{$option}: use DOUBLE, SINGLE or NONE'),
        };
        return simple(
          (r) => [
            for (final MapEntry(:key, :value) in r.fields.entries)
              '$key=$quote$value$quote',
          ].join(' '),
        );
      case 'prefix':
        final parts = children;
        if (parts == null) {
          _fail('%prefix needs (...) around the conversions');
        }
        return (r) {
          final buffer = StringBuffer();
          for (final part in parts) {
            if (_names[part] case final name?) {
              buffer.write('$name=');
            }
            buffer.write(part(r));
          }
          return buffer.toString();
        };
      case 'property':
        final key = option?.trim();
        if (key == null || key.isEmpty) {
          return simple((_) => 'Property_HAS_NO_KEY');
        }
        return simple((_) => variables[key] ?? 'null');
      case 'esb':
        final inner = children == null ? null : _concat(children);
        final fallback = option == null ? null : variables[option.trim()];
        return (r) {
          final value = inner?.call(r) ?? '';
          final text = value.isNotEmpty ? value : (fallback ?? '');
          return text.isEmpty ? '' : '[$text] ';
        };
      default:
        _fail('Unknown conversion word %$word');
    }
  }

  _Render _requireChildren(String word, List<_Render>? children) {
    if (children == null) {
      _fail('%$word needs (...) around its content');
    }
    return _concat(children);
  }

  static String _unquote(String value) =>
      value.length >= 2 &&
          ((value.startsWith("'") && value.endsWith("'")) ||
              (value.startsWith('"') && value.endsWith('"')))
      ? value.substring(1, value.length - 1)
      : value;

  // Java's Matcher.replaceAll replacement: `$n` / `${name}` groups, `\x`
  // a literal x.
  static String _javaReplacement(Match match, String replacement) {
    final out = StringBuffer();
    for (var i = 0; i < replacement.length; i++) {
      final c = replacement[i];
      if (c == r'\' && i + 1 < replacement.length) {
        out.write(replacement[++i]);
      } else if (c == r'$' && i + 1 < replacement.length) {
        var j = i + 1;
        while (j < replacement.length &&
            replacement.codeUnitAt(j) >= 48 &&
            replacement.codeUnitAt(j) <= 57) {
          j++;
        }
        if (j > i + 1) {
          final group = int.parse(replacement.substring(i + 1, j));
          out.write(group <= match.groupCount ? match.group(group) ?? '' : '');
          i = j - 1;
        } else {
          out.write(c);
        }
      } else {
        out.write(c);
      }
    }
    return out.toString();
  }

  int? _depth(String word, String? option) {
    final value = option?.trim() ?? '';
    return switch (value) {
      '' || 'full' => null,
      'short' => 1,
      _ =>
        int.tryParse(value) ??
            _fail('%$word{$option}: use short, full or a number of lines'),
    };
  }

  _Render _color(_Render inner, String? option) {
    final name = option?.trim().toLowerCase();
    final fixed = name == null || name.isEmpty
        ? null
        : (_ansiCodes[name] ??
              _fail(
                "Unknown colour '$option' in %clr (use "
                "${_ansiCodes.keys.join(', ')})",
              ));
    if (!ansi) {
      return inner;
    }
    return (record) {
      final code =
          fixed ??
          switch (record.level) {
            SpringLogLevel.error => '31',
            SpringLogLevel.warning => '33',
            _ => '32',
          };
      return '\x1B[${code}m${inner(record)}\x1B[0;39m';
    };
  }

  _Render _date(String? option) {
    final options = _splitOptions(option ?? '');
    var format = options.isEmpty ? '' : options.first.trim();
    if (format.length >= 2 && format.startsWith('"') && format.endsWith('"')) {
      format = format.substring(1, format.length - 1);
    }
    format = switch (format) {
      '' || 'ISO8601' => 'yyyy-MM-dd HH:mm:ss,SSS',
      'STRICT' => "yyyy-MM-dd'T'HH:mm:ss,SSS",
      _ => format,
    };
    var utc = false;
    if (options.length > 1) {
      final zone = options[1].trim();
      if (const {
        'UTC',
        'GMT',
        'Z',
        'UT',
        'ETC/UTC',
      }.contains(zone.toUpperCase())) {
        utc = true;
      } else {
        _fail(
          "%d time zone '$zone' is not supported: use UTC or leave it out "
          'for local time (Dart has no time zone database); quote a date '
          'pattern containing a comma: %d{"HH:mm:ss,SSS"}',
        );
      }
    }
    if (options.length > 2) {
      _fail('%d takes a pattern and a time zone, found "$option"');
    }
    final render = _DateFormat.compile(format, _fail);
    return utc ? (r) => render(r.time.toUtc()) : (r) => render(r.time);
  }

  // Logback's option list: comma-separated, commas in quotes kept.
  static List<String> _splitOptions(String option) {
    if (option.isEmpty) {
      return const [];
    }
    final result = <String>[];
    final current = StringBuffer();
    String? quote;
    for (var i = 0; i < option.length; i++) {
      final c = option[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        }
      } else if (c == "'" || c == '"') {
        quote = c;
      } else if (c == ',') {
        result.add(current.toString());
        current.clear();
        continue;
      }
      current.write(c);
    }
    result.add(current.toString());
    return result;
  }
}

// A subset of java.time's DateTimeFormatter pattern letters.
abstract final class _DateFormat {
  static const _months = [
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

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String Function(DateTime time) compile(
    String pattern,
    Never Function(String message) fail,
  ) {
    final parts = <String Function(DateTime)>[];
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == "'") {
        final end = pattern.indexOf("'", i + 1);
        if (end < 0) {
          fail("Unclosed quote in date pattern '$pattern'");
        }
        final literal = end == i + 1 ? "'" : pattern.substring(i + 1, end);
        parts.add((_) => literal);
        i = end + 1;
        continue;
      }
      if (!_isLetter(c)) {
        parts.add((_) => c);
        i++;
        continue;
      }
      var count = 1;
      while (i + count < pattern.length && pattern[i + count] == c) {
        count++;
      }
      parts.add(_field(c, count, pattern, fail));
      i += count;
    }
    return (time) {
      final buffer = StringBuffer();
      for (final part in parts) {
        buffer.write(part(time));
      }
      return buffer.toString();
    };
  }

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }

  static String _pad(int value, int width) => '$value'.padLeft(width, '0');

  static String Function(DateTime) _field(
    String letter,
    int count,
    String pattern,
    Never Function(String message) fail,
  ) {
    switch (letter) {
      case 'y' || 'u':
        return count == 2
            ? (t) => _pad(t.year % 100, 2)
            : (t) => _pad(t.year, count);
      case 'M' || 'L':
        return switch (count) {
          1 || 2 => (t) => _pad(t.month, count),
          3 => (t) => _months[t.month - 1].substring(0, 3),
          _ => (t) => _months[t.month - 1],
        };
      case 'd':
        return (t) => _pad(t.day, count);
      case 'D':
        return (t) => _pad(
          DateTime.utc(
                t.year,
                t.month,
                t.day,
              ).difference(DateTime.utc(t.year)).inDays +
              1,
          count,
        );
      case 'E':
        return count <= 3
            ? (t) => _days[t.weekday - 1].substring(0, 3)
            : (t) => _days[t.weekday - 1];
      case 'a':
        return (t) => t.hour < 12 ? 'AM' : 'PM';
      case 'H':
        return (t) => _pad(t.hour, count);
      case 'k':
        return (t) => _pad(t.hour == 0 ? 24 : t.hour, count);
      case 'K':
        return (t) => _pad(t.hour % 12, count);
      case 'h':
        return (t) => _pad(t.hour % 12 == 0 ? 12 : t.hour % 12, count);
      case 'm':
        return (t) => _pad(t.minute, count);
      case 's':
        return (t) => _pad(t.second, count);
      case 'S':
        return (t) {
          final fraction = _pad(t.millisecond * 1000 + t.microsecond, 6);
          return count <= 6
              ? fraction.substring(0, count)
              : fraction.padRight(count, '0');
        };
      case 'X' || 'x':
        if (count > 3) {
          fail("Too many '$letter' in date pattern '$pattern'");
        }
        return (t) => _offset(t, count, zulu: letter == 'X');
      case 'Z':
        return switch (count) {
          <= 3 => (t) => _offset(t, 2, zulu: false),
          5 => (t) => _offset(t, 3, zulu: true),
          _ => fail("Use Z, ZZ, ZZZ or ZZZZZ in date pattern '$pattern'"),
        };
      case 'z':
        return (t) => t.timeZoneName;
      default:
        fail("Unsupported letter '$letter' in date pattern '$pattern'");
    }
  }

  // X: +01 (+0130 with minutes), XX: +0100, XXX: +01:00; `Z` for UTC with
  // the X letters, like java.time.
  static String _offset(DateTime time, int count, {required bool zulu}) {
    final offset = time.isUtc ? Duration.zero : time.timeZoneOffset;
    if (offset == Duration.zero && zulu) {
      return 'Z';
    }
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    final hh = _pad(minutes ~/ 60, 2);
    final mm = _pad(minutes % 60, 2);
    return switch (count) {
      1 => minutes % 60 == 0 ? '$sign$hh' : '$sign$hh$mm',
      2 => '$sign$hh$mm',
      _ => '$sign$hh:$mm',
    };
  }
}
