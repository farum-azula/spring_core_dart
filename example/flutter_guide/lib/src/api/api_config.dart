import 'package:neon_books_app/src/api/account_client.dart';
import 'package:neon_books_app/src/api/admin_client.dart';
import 'package:neon_books_app/src/api/api_properties.dart';
import 'package:neon_books_app/src/api/catalog_client.dart';
import 'package:neon_books_app/src/api/cookie_jar.dart';
import 'package:neon_books_app/src/api/session_transport.dart';
import 'package:neon_books_app/src/api/shop_client.dart';
import 'package:neon_books_app/src/api/stock_client.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// The server's API: its HTTP service interfaces in the `server` group,
/// whose `RestClient` has the base URL and the read timeout of
/// `spring.http.serviceclient.server.*`.
///
/// How the native apps reach the server. On the web the starter
/// (`spring_boot_starter_flutter_security`) declares the transport: the
/// browser's `fetch`, which sends the session cookie to the server
/// (another origin: `spring.flutter.security.web.server-url`), and the
/// CSRF token of the `XSRF-TOKEN` cookie on unsafe requests. An app's own
/// `HttpTransport` would replace it, so these two are not beans there.
@Configuration()
@ImportHttpServices(
  group: 'server',
  types: [
    AccountClient,
    AdminClient,
    CatalogClient,
    ShopClient,
    StockClient,
  ],
)
class ApiConfig {
  /// The network: `dart:io` on phones and desktops, calling only the
  /// allowed addresses (the `server` group's base URL, the Keycloak
  /// issuer). Tests replace this bean (by name) with a
  /// `MockHttpTransport`.
  @Bean()
  @Profile(['!web'])
  HttpTransport networkTransport(
    @Value(r'${api.connect-timeout:5s}') Duration connectTimeout,
    AllowedAddresses allowedAddresses,
  ) => platformHttpTransport(
    connectTimeout: connectTimeout,
    allowedAddresses: allowedAddresses,
  );

  /// What the HTTP service clients use: the network with the session's
  /// cookies.
  @Bean()
  @Primary()
  @Profile(['!web'])
  HttpTransport sessionTransport(
    @Qualifier('networkTransport') HttpTransport network,
    CookieJar cookies,
    ApiProperties api,
  ) => SessionTransport(network, cookies, Uri.parse(api.baseUrl));
}
