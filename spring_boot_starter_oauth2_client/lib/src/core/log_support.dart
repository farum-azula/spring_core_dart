import 'package:spring_boot_dart/spring_boot_dart.dart' show LogFormatUtils;

/// [value] for a log line, as Spring's `LogFormatUtils` writes values from
/// a client (line breaks as `<EOL>`, control characters as `?`, cut at
/// [maxLength]), but without the quotes.
String logText(Object? value, {int maxLength = 200}) =>
    LogFormatUtils.formatValue(_Unquoted('$value'), maxLength: maxLength);

/// The host and the path of [uri], as logs name an endpoint: the query
/// (an authorization request's `state`, a key) is left out.
String logEndpoint(Uri uri) => logText('${uri.host}${uri.path}');

final class _Unquoted {
  const _Unquoted(this.text);

  final String text;

  @override
  String toString() => text;
}
