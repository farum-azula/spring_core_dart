import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:neon_books_app/src/api/session_transport.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// How the app reaches the server.
@Configuration()
class ApiConfig {
  /// The network: `dart:io` on phones and desktops, `fetch` in a browser.
  /// Tests replace this bean (by name) with a `MockHttpTransport`.
  @Bean()
  HttpTransport networkTransport(
    @Value(r'${api.connect-timeout:5s}') Duration connectTimeout,
  ) => platformHttpTransport(connectTimeout: connectTimeout);

  /// What the Feign clients use: the network with the session's cookies.
  /// Not in a browser, which keeps the cookies itself (and hides them
  /// from the app).
  @Bean()
  @Primary()
  @Profile(['!web'])
  HttpTransport sessionTransport(
    @Qualifier('networkTransport') HttpTransport network,
    CookieJar cookies,
  ) => SessionTransport(network, cookies);

  /// Retries what failed without an answer (no connection, a timeout, a
  /// 503 with `Retry-After`): 3 attempts, 150 ms, 225 ms apart. Nothing
  /// else is retried, so a `POST` is never sent twice after an answer.
  @Bean()
  Retryer retryer() => const DefaultRetryer(maxAttempts: 3);
}
