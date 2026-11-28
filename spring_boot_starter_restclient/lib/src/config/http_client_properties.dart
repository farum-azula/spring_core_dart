import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How a client treats redirects (`spring.http.clients.redirects`).
///
/// Spring (Java): Spring Boot's `HttpRedirects`.
enum HttpRedirects {
  /// Follow them where the transport can (every platform follows; a
  /// browser by its own rules). The default.
  followWhenPossible,

  /// Follow them.
  follow,

  /// Do not follow them: the `3xx` is the answer (in a browser an opaque
  /// response with status 0).
  dontFollow;

  /// Whether a request follows redirects under this setting.
  bool get followsRedirects => this != dontFollow;
}

/// The settings every HTTP client of the application shares:
/// `spring.http.clients.*`.
///
/// ```yaml
/// spring:
///   http:
///     clients:
///       connect-timeout: 2s
///       read-timeout: 10s
///       redirects: dont-follow
///       allowed-addresses:
///         - api.neon.books
///         - 10.20.0.0/16
/// ```
///
/// Spring (Java): Spring Boot's `HttpClientsProperties`
/// (`spring.http.clients.*`); `allowed-addresses` is the family's, for
/// its outgoing addresses closed by default (Spring Boot 4.1 has an
/// `InetAddressFilter` bean and calls anything without one).
@ConfigurationProperties('spring.http.clients')
class HttpClientsProperties {
  /// The longest wait for a connection to open. Default: `10s` (`0`:
  /// none). The transport's own; a group's `connect-timeout` may be
  /// longer, the transport then waits as long as the longest of them.
  Duration connectTimeout = const Duration(seconds: 10);

  /// The longest wait for data: for the response, then between two
  /// chunks of the body (not a limit of the whole call; the deadline of
  /// the enclosing request is that). Default: `60s` (`0`: none).
  Duration readTimeout = const Duration(seconds: 60);

  /// Whether redirects are followed: `follow-when-possible` (the
  /// default), `follow` or `dont-follow`.
  HttpRedirects redirects = HttpRedirects.followWhenPossible;

  /// The hosts and addresses the clients may call; **every other one is
  /// denied**, private networks and loopback included. Each entry is a
  /// host name (`api.neon.books`), its subdomains (`*.neon.books`), an
  /// address literal (`203.0.113.7`), a CIDR block (`10.20.0.0/16`), or
  /// `*` for any host with a public address. The hosts of the
  /// `spring.http.serviceclient.<group>.base-url` values are on it by
  /// themselves. A name opens only public addresses: list the block of a
  /// private network (or `localhost`) too. Cloud metadata
  /// (`169.254.169.254`) needs its own entry. In a browser only the host
  /// of the URL is checked. Default: empty.
  List<String> allowedAddresses = [];
}

/// The HTTP service groups: `spring.http.serviceclient.<group>.*`, by the
/// group's name.
///
/// Spring (Java): Spring Boot's `HttpServiceClientProperties`.
@ConfigurationProperties('spring.http')
class HttpServiceClientProperties {
  /// The settings of each group, by its name (`@ImportHttpServices(group:
  /// ...)`; `default` for interfaces imported without one).
  Map<String, HttpServiceClientGroupProperties> serviceclient = {};
}

/// The settings of one HTTP service group
/// (`spring.http.serviceclient.<group>.*`); what a group leaves out comes
/// from `spring.http.clients.*`.
///
/// ```yaml
/// spring:
///   http:
///     serviceclient:
///       catalog:
///         base-url: https://catalog.neon.books
///         default-header:
///           X-Tenant: neon
///         apiversion:
///           default: '1.2'
///           insert:
///             header: API-Version
///         read-timeout: 5s
/// ```
///
/// Spring (Java): Spring Boot's `HttpClientProperties` of a group.
@Introspected()
class HttpServiceClientGroupProperties {
  /// The base URL of the group's calls; its host is allowed by itself
  /// (see `spring.http.clients.allowed-addresses`). Default: none.
  String? baseUrl;

  /// Headers sent with every call of the group, by name; a comma list or
  /// an indexed list gives several values.
  Map<String, List<String>> defaultHeader = {};

  /// The group's connect timeout. Default: `spring.http.clients`'.
  Duration? connectTimeout;

  /// The group's read timeout. Default: `spring.http.clients`'.
  Duration? readTimeout;

  /// The group's redirects. Default: `spring.http.clients`'.
  HttpRedirects? redirects;

  /// The API version of the group's calls, and where it goes.
  ApiversionProperties apiversion = ApiversionProperties();
}

/// The API version of an HTTP service group's calls
/// (`spring.http.serviceclient.<group>.apiversion.*`): the version a call
/// asks for unless its exchange annotation gives one, and where the
/// group's `RestClient` puts it.
///
/// ```yaml
/// spring:
///   http:
///     serviceclient:
///       catalog:
///         apiversion:
///           default: '1.2'
///           insert:
///             header: API-Version
/// ```
///
/// Spring (Java): Spring Boot's `ApiversionProperties`.
@Introspected()
class ApiversionProperties {
  /// The version every call of the group asks for, unless its method or
  /// interface gives one (`version:` of the exchange annotation). It needs
  /// a place to go (`insert.*`, or an `ApiVersionInserter` a customizer
  /// sets): a group with a default version and no inserter fails the
  /// start. Default: none.
  @Name('default')
  String? defaultVersion;

  /// Where the version goes into a request.
  ApiversionInsertProperties insert = ApiversionInsertProperties();
}

/// Where an HTTP service group puts the API version of a call
/// (`spring.http.serviceclient.<group>.apiversion.insert.*`); several
/// places may be set at once. With none set, the group keeps the inserter
/// of its builder (a `RestClientCustomizer`'s), if any; Spring Boot sets
/// one that inserts nothing.
///
/// Spring (Java): Spring Boot's `ApiversionProperties.Insert`.
@Introspected()
class ApiversionInsertProperties {
  /// The header that holds the version (`API-Version`).
  String? header;

  /// The query parameter that holds the version (`version`).
  String? queryParameter;

  /// The index of the path segment the version is inserted as (`0`:
  /// `/books` becomes `/1.2/books`).
  int? pathSegment;

  /// The parameter of the `Content-Type` that holds the version
  /// (`application/json;v=1.2`).
  String? mediaTypeParameter;
}
