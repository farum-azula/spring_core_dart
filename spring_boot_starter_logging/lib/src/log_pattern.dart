import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Turns a [SpringLogRecord] into text, using a Logback-like pattern
/// (`logging.pattern.console`).
///
/// | Token | Output |
/// |---|---|
/// | `%d`, `%d{HH:mm:ss.SSS}` | time (default `yyyy-MM-dd HH:mm:ss.SSS`; `yyyy MM dd HH mm ss SSS`) |
/// | `%p`, `%level` | level: `TRACE DEBUG INFO WARN ERROR` |
/// | `%c`, `%logger` | logger name |
/// | `%m`, `%msg`, `%message` | message |
/// | `%X{key}` | one field; `%X` all fields as ` {k=v, ...}` (nothing if none) |
/// | `%ex` | error and stack trace on the next lines (nothing if none) |
/// | `%seq` | record sequence number |
/// | `%n` | new line |
/// | `%%` | `%` |
///
/// A width pads (`%5p`: right-aligned, `%-20logger`: left-aligned).
///
/// ```dart
/// final pattern = LogPattern('%d{HH:mm:ss} %-5p [%logger] %m');
/// pattern.format(record); // 12:00:01 INFO  [neon.checkout] order placed
/// ```
final class LogPattern {
  /// Parses [pattern]; throws [FormatException] for unknown tokens.
  LogPattern(this.pattern) : _parts = _parse(pattern);

  /// The default console pattern, close to Spring Boot's.
  static const defaultPattern =
      '%d{yyyy-MM-dd HH:mm:ss.SSS} %5p --- [%logger] %m%X%ex';

  /// The source pattern.
  final String pattern;

  final List<_Part> _parts;

  /// The formatted record.
  String format(SpringLogRecord record) {
    final buffer = StringBuffer();
    for (final part in _parts) {
      buffer.write(part.render(record));
    }
    return buffer.toString();
  }

  /// The display name of [level] (`WARN`, not `WARNING`).
  static String levelName(SpringLogLevel level) => switch (level) {
    SpringLogLevel.warning => 'WARN',
    _ => level.name.toUpperCase(),
  };

  static final _token = RegExp(r'%(-?\d+)?([a-zA-Z]+|%)(?:\{([^}]*)\})?');

  static List<_Part> _parse(String pattern) {
    final parts = <_Part>[];
    var last = 0;
    for (final match in _token.allMatches(pattern)) {
      if (match.start > last) {
        parts.add(_Literal(pattern.substring(last, match.start)));
      }
      last = match.end;
      final width = int.tryParse(match.group(1) ?? '');
      final option = match.group(3);
      final String Function(SpringLogRecord) render = switch (match.group(2)) {
        '%' => (_) => '%',
        'n' => (_) => '\n',
        'd' || 'date' => _date(option ?? 'yyyy-MM-dd HH:mm:ss.SSS'),
        'p' || 'le' || 'level' => (r) => levelName(r.level),
        'c' || 'lo' || 'logger' => (r) => r.loggerName,
        'm' || 'msg' || 'message' => (r) => r.message,
        'seq' => (r) => '${r.sequence}',
        'ex' || 'exception' => _exception,
        'X' || 'mdc' when option != null => (r) => '${r.fields[option] ?? ''}',
        'X' || 'mdc' => _fields,
        final other => throw FormatException(
          'Unknown log pattern token %$other',
          pattern,
          match.start,
        ),
      };
      parts.add(width == null ? _Token(render) : _Padded(render, width));
    }
    if (last < pattern.length) {
      parts.add(_Literal(pattern.substring(last)));
    }
    return parts;
  }

  static String _fields(SpringLogRecord record) => record.fields.isEmpty
      ? ''
      : ' {${[for (final MapEntry(:key, :value) in record.fields.entries) '$key=$value'].join(', ')}}';

  static String _exception(SpringLogRecord record) {
    final error = record.error;
    if (error == null) {
      return '';
    }
    final stack = record.stackTrace?.toString().trimRight() ?? '';
    return '\n$error${stack.isEmpty ? '' : '\n$stack'}';
  }

  static String Function(SpringLogRecord) _date(String format) {
    String two(int value) => value.toString().padLeft(2, '0');
    final tokens = RegExp('yyyy|MM|dd|HH|mm|ss|SSS');
    return (record) {
      final time = record.time;
      return format.replaceAllMapped(
        tokens,
        (match) => switch (match[0]) {
          'yyyy' => time.year.toString().padLeft(4, '0'),
          'MM' => two(time.month),
          'dd' => two(time.day),
          'HH' => two(time.hour),
          'mm' => two(time.minute),
          'ss' => two(time.second),
          _ => time.millisecond.toString().padLeft(3, '0'),
        },
      );
    };
  }

  @override
  String toString() => 'LogPattern($pattern)';
}

sealed class _Part {
  String render(SpringLogRecord record);
}

final class _Literal implements _Part {
  _Literal(this.text);

  final String text;

  @override
  String render(SpringLogRecord record) => text;
}

final class _Token implements _Part {
  _Token(this.renderer);

  final String Function(SpringLogRecord) renderer;

  @override
  String render(SpringLogRecord record) => renderer(record);
}

final class _Padded implements _Part {
  _Padded(this.renderer, this.width);

  final String Function(SpringLogRecord) renderer;
  final int width;

  @override
  String render(SpringLogRecord record) {
    final text = renderer(record);
    return width < 0 ? text.padRight(-width) : text.padLeft(width);
  }
}
