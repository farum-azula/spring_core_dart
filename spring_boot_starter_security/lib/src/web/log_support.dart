import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// [value] for a log line, as Spring's `LogFormatUtils` writes values from
/// a client (line breaks as `<EOL>`, control characters as `?`, cut at
/// [maxLength]), but without the quotes.
String logText(Object? value, {int maxLength = 200}) =>
    LogFormatUtils.formatValue(
      _Unquoted('$value'),
      maxLength: maxLength,
    );

final class _Unquoted {
  const _Unquoted(this.text);

  final String text;

  @override
  String toString() => text;
}

/// `GET /api/books`: the method and the path of [request], as Spring's
/// `requestLine`. The query is left out: it can hold an OAuth 2.0 `code`
/// or `state`.
String requestLine(ServerHttpRequest request) =>
    '${request.method.value} ${logText(request.path)}';

/// [authentication] as Spring's `AbstractAuthenticationToken.toString`
/// writes it: the credentials always `[PROTECTED]`, the details only when
/// they are the web details (which hide the session id).
String describeAuthentication(Authentication authentication) {
  final details = authentication.details;
  final shown = switch (details) {
    null => null,
    final WebAuthenticationDetails d => d,
    _ => details.runtimeType,
  };
  return logText(
    '${authentication.runtimeType} [Principal=${authentication.name}, '
    'Credentials=[PROTECTED], Authenticated=${authentication.isAuthenticated}, '
    'Details=$shown, Granted Authorities=${authentication.authorities}]',
    maxLength: -1,
  );
}

/// The user and the authorities of [authentication], nothing else.
String describeUser(Authentication authentication) => logText(
  '${authentication.runtimeType} [Principal=${authentication.name}, '
  'Granted Authorities=${authentication.authorities}]',
  maxLength: -1,
);
