import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// The property that shows request parameters and headers in the logs, as
/// Spring MVC's `spring.mvc.log-request-details`.
const logRequestDetailsProperty = 'spring.mvc.log-request-details';

/// [text] as one line safe to log: line breaks become `<EOL>` and control
/// characters `?` (Spring's `LogFormatUtils`), cut at [maxLength]. Unlike
/// `LogFormatUtils.formatValue` of a `String` it adds no quotes.
String logSafe(Object? text, {int maxLength = 200}) =>
    LogFormatUtils.formatValue(_Unquoted('$text'), maxLength: maxLength);

/// [value] as `LogFormatUtils.formatValue` shows a quoted string.
String logQuoted(String value, {int maxLength = 1000}) =>
    LogFormatUtils.formatValue(value, maxLength: maxLength);

final class _Unquoted {
  _Unquoted(this._text);
  final String _text;
  @override
  String toString() => _text;
}

/// The value shown in a log for the header [name]: always `masked` for the
/// ones that carry credentials.
String logHeaderValue(String name, List<String> values) =>
    _isSensitiveHeader(name)
    ? 'masked'
    : logSafe(values.join(','), maxLength: 100);

bool _isSensitiveHeader(String name) {
  final lower = name.toLowerCase();
  return lower == 'authorization' ||
      lower == 'proxy-authorization' ||
      lower == 'cookie' ||
      lower == 'set-cookie' ||
      const ['token', 'secret', 'key', 'password', 'session'].any(
        lower.contains,
      );
}

/// The headers of a request as the trace line shows them, sensitive
/// values masked.
String logHeaders(HttpHeaders headers) {
  final out = <String>[];
  headers.forEach(
    (name, values) => out.add(
      '${logSafe(name, maxLength: 60)}: ${logHeaderValue(name, values)}',
    ),
  );
  return '{${out.join(', ')}}';
}

/// The parameters of a request as the debug line shows them: `masked`,
/// or with [details] the values too (those of a name that looks like a
/// credential, such as `password`, stay masked).
String logParameters(Map<String, List<String>> parameters, bool details) {
  if (!details) {
    return parameters.isEmpty ? '{}' : '{masked}';
  }
  final out = <String>[];
  parameters.forEach((name, values) {
    final shown = _isSensitiveHeader(name)
        ? 'masked'
        : values.map((v) => logSafe(v, maxLength: 100)).join(', ');
    out.add('${logSafe(name, maxLength: 60)}=[$shown]');
  });
  return '{${out.join(', ')}}';
}
