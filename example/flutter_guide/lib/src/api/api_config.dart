import 'package:neon_books_app/src/api/api_properties.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:neon_books_app/src/api/session_transport.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// How the native apps reach the server. On the web the starter
/// (`spring_boot_starter_flutter_security`) declares the transport: the
/// browser's `fetch`, which sends the session cookie to the server
/// (another origin: `spring.flutter.security.web.server-url`), and the
/// CSRF token of the `XSRF-TOKEN` cookie on unsafe requests. An app's own
/// `HttpTransport` would replace it, so these two are not beans there.
@Configuration()
class ApiConfig {
  /// The network: `dart:io` on phones and desktops. Tests replace this
  /// bean (by name) with a `MockHttpTransport`.
  @Bean()
  @Profile(['!web'])
  HttpTransport networkTransport(
    @Value(r'${api.connect-timeout:5s}') Duration connectTimeout,
  ) => platformHttpTransport(connectTimeout: connectTimeout);

  /// What the Feign clients use: the network with the session's cookies.
  @Bean()
  @Primary()
  @Profile(['!web'])
  HttpTransport sessionTransport(
    @Qualifier('networkTransport') HttpTransport network,
    CookieJar cookies,
    ApiProperties api,
  ) => SessionTransport(network, cookies, Uri.parse(api.baseUrl));

  /// Retries what failed without an answer (no connection, a timeout, a
  /// 503 with `Retry-After`): 3 attempts, 150 ms, 225 ms apart. Nothing
  /// else is retried, so a `POST` is never sent twice after an answer.
  @Bean()
  Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
}
