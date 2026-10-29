import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_flutter_security/src/login/oauth2_login_service.dart';
import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';
import 'package:spring_boot_starter_flutter_security/src/web/csrf_cookie_http_transport.dart';
import 'package:spring_boot_starter_flutter_security/src/web/flutter_web_security_properties.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

const _log = SpringLog('spring.security.oauth2.client.login');

/// The [OAuth2LoginService] of a Flutter web app whose server logs the
/// user in (backend-for-frontend, `spring.flutter.security.web.mode=server`,
/// the default).
///
/// A browser has no safe place for tokens: any script that gets into the
/// page reads what the app holds. So the app's server logs the user in
/// with `oauth2Login()` of `spring_boot_starter_security`, as a
/// confidential client, keeps the tokens in its session, and gives the
/// browser only an `HttpOnly` session cookie, which no script can read.
/// This service is the app's side of that login, with the same calls as
/// on phones:
///
/// - [login] navigates the page to the server's
///   `/oauth2/authorization/{registrationId}`; the server sends it on to
///   the provider and, after the login, back to the app, which starts
///   again.
/// - [restore] asks the server's user endpoint who holds the session
///   (`GET /user` by default, with the cookie) and puts that user into
///   the `SecurityContextHolder`.
/// - [logout] posts the server's logout URL (`/logout` by default) with
///   the CSRF token; when the server answers with the provider's logout
///   page (to end the provider's session too), the page goes there.
///
/// **The user endpoint.** Spring has no standard "who am I" endpoint, so
/// the server declares one (a controller of a few lines, see the
/// package's README). Its answer, for a request with a session:
///
/// ```json
/// {
///   "name": "ada",
///   "authorities": ["ROLE_USER", "OIDC_USER", "SCOPE_profile"],
///   "registrationId": "keycloak",
///   "attributes": {"sub": "f81d4fae", "email": "ada@neon.books"}
/// }
/// ```
///
/// `name` is required; `authorities` (strings, or `{"authority": ...}`
/// objects as Jackson writes Spring's `GrantedAuthority`) and
/// `attributes` are optional, other members are ignored. With a
/// `registrationId` the user becomes an [OAuth2AuthenticationToken],
/// without one (a form login of the server) a
/// [PreAuthenticatedAuthenticationToken]; the principal is an
/// [OAuth2User] with the server's attributes either way. A `401` or
/// `403`, a redirect (to a login page) or a `204` mean nobody is logged
/// in. A guide's `{"name": ...}` answer works as it is.
///
/// **The logout answer.** A script request cannot follow a redirect to
/// the provider (another origin), as Spring's
/// `OidcClientInitiatedLogoutSuccessHandler` sends; so the server answers
/// the provider's logout URL instead, either as JSON
/// (`{"logoutUrl": "https://id.neon.books/...logout?id_token_hint=..."}`)
/// or in the `Location` header of a `2xx` answer (`202 Accepted`). Any
/// other success (`204`, a redirect) only ends the server's session.
///
/// The requests carry the CSRF token through [CsrfCookieHttpTransport]
/// (added around [transport] when it is not one already); the cookies go
/// with them when the transport's `fetch` sends them (the package's
/// `httpTransport` bean does for a server on another origin).
///
/// Spring has no counterpart: Spring Security logs browsers in on the
/// server; this is the page's side of `oauth2Login()`.
class ServerOAuth2LoginService implements OAuth2LoginService {
  /// A login on the server of [properties] (the page's origin by
  /// default), through [transport]; the package's auto-configuration
  /// passes the beans.
  ServerOAuth2LoginService({
    required HttpTransport transport,
    required this.page,
    this.properties = const FlutterWebSecurityProperties(),
    this.eventPublisher,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    this.timeout = const Duration(seconds: 30),
  }) : server = properties.server(page.location),
       securityContextHolderStrategy =
           securityContextHolderStrategy ??
           SecurityContextHolder.getContextHolderStrategy() {
    this.transport = transport is CsrfCookieHttpTransport
        ? transport
        : CsrfCookieHttpTransport(transport, page: page, server: server);
  }

  /// Sends the requests to the server, with the CSRF token.
  late final HttpTransport transport;

  /// The page: its cookies, and leaving it for the login and logout pages.
  final BrowserPage page;

  /// Where the server and its endpoints are.
  final FlutterWebSecurityProperties properties;

  /// The server's address: `server-url`, or the page's origin.
  final Uri server;

  /// Receives the login and logout events, or `null`.
  final ApplicationEventPublisher? eventPublisher;

  /// Where the logged-in user is put.
  final SecurityContextHolderStrategy securityContextHolderStrategy;

  /// How long a request to the server may take.
  final Duration timeout;

  bool _busy = false;
  final StreamController<Authentication?> _changes = StreamController.broadcast(
    sync: true,
  );

  /// The user of the security context, unless nobody or an anonymous
  /// user is there: in a browser the context is the only record of who
  /// is logged in (a form login of the app's own counts too).
  @override
  Authentication? get authentication {
    final current = securityContextHolderStrategy.getContext().authentication;
    return current == null ||
            !current.isAuthenticated ||
            current is AnonymousAuthenticationToken
        ? null
        : current;
  }

  @override
  bool get isLoggedIn => authentication != null;

  @override
  Stream<Authentication?> get authenticationChanges => _changes.stream;

  /// Navigates the page to the server's
  /// `{authorization-base-uri}/{registrationId}` and returns `null`: the
  /// app stops there, and starts again when the server sends the browser
  /// back after the login (call [restore] then).
  ///
  /// [additionalParameters] are added to that URL's query; Spring's
  /// default `OAuth2AuthorizationRequestResolver` does not pass them on
  /// to the provider, a resolver of the server's own may.
  ///
  /// Throws an [ArgumentError] for an empty [registrationId] and a
  /// [StateError] while a restore or logout runs.
  @override
  Future<Authentication?> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  }) async {
    if (registrationId.isEmpty) {
      throw ArgumentError.value(registrationId, 'registrationId', 'empty');
    }
    if (_busy) {
      throw StateError('A restore or logout is already running');
    }
    final base = FlutterWebSecurityProperties.resolve(
      server,
      properties.authorizationBaseUri,
    );
    final segments = [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      registrationId,
    ];
    final target = base.replace(
      pathSegments: segments,
      queryParameters: additionalParameters.isEmpty
          ? null
          : {...base.queryParameters, ...additionalParameters},
    );
    _log.debug(
      "Leaving for the server's login with registration '$registrationId'",
    );
    page.navigate(target);
    return null;
  }

  /// Asks the server's user endpoint who holds the session, puts that
  /// user into the security context and returns their authentication
  /// (publishing an `AuthenticationSuccessEvent`); `null` when the server
  /// says nobody is logged in (then a user left in the context is
  /// removed).
  ///
  /// When the server cannot be reached or answers something else (a
  /// `404`, a `500`, no JSON), a warning is logged, the context is left
  /// as it is and the result is `null`: an app starts all the same.
  ///
  /// Throws a [StateError] while a logout runs.
  @override
  Future<Authentication?> restore() => _exclusive(() async {
    final url = FlutterWebSecurityProperties.resolve(
      server,
      properties.userEndpoint,
    );
    final HttpResponse response;
    try {
      response = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: url,
          headers: HttpHeaders({'Accept': 'application/json'}),
          timeout: timeout,
          followRedirects: false,
        ),
      );
    } on HttpTransportException catch (e) {
      _log.warning(
        'Nobody restored: the user endpoint $url cannot be reached '
        '(${e.isTimeout ? 'timeout' : 'no answer'})',
      );
      return null;
    }
    final status = response.statusCode;
    if (_isNobody(status)) {
      _signedOut(publish: false);
      return null;
    }
    if (status < 200 || status > 299) {
      _log.warning(
        'Nobody restored: the user endpoint $url answered $status '
        '(${FlutterWebSecurityProperties.prefix}.user-endpoint)',
      );
      return null;
    }
    final Authentication user;
    try {
      user = userFrom(jsonDecode(response.bodyText));
    } on FormatException catch (e) {
      // Never log the answer itself: it describes the user.
      _log.warning(
        'Nobody restored: the user endpoint $url answered no usable user '
        '(${e.message})',
      );
      return null;
    }
    securityContextHolderStrategy.setContext(
      securityContextHolderStrategy.createEmptyContext()..authentication = user,
    );
    _changes.add(user);
    eventPublisher?.publishEvent(AuthenticationSuccessEvent(user));
    _log.debug("Restored '${user.name}' from the server's session");
    return user;
  });

  /// Posts the server's logout URL (with the CSRF token), clears the
  /// security context and publishes a `LogoutSuccessEvent` when someone
  /// was logged in; then, when the server answered the provider's logout
  /// page, navigates there (the provider ends its session and sends the
  /// browser back to the app).
  ///
  /// The post is sent even when the app knows of nobody (it ends a session
  /// the app did not restore). The local logout happens whatever the
  /// server answers; a failure is logged. [endSession] and
  /// [postLogoutRedirectUri] are not used: the server's logout handler
  /// decides about the provider's session and where it comes back to.
  ///
  /// Throws a [StateError] while a restore runs.
  @override
  Future<void> logout({bool endSession = false, Uri? postLogoutRedirectUri}) =>
      _exclusive(() async {
        final url = FlutterWebSecurityProperties.resolve(
          server,
          properties.logoutUrl,
        );
        Uri? next;
        try {
          final response = await transport.send(
            HttpRequest(
              method: HttpMethod.post,
              url: url,
              headers: HttpHeaders({'Accept': 'application/json'}),
              timeout: timeout,
              followRedirects: false,
            ),
          );
          next = _logoutTarget(url, response);
        } on HttpTransportException catch (e) {
          _log.warning(
            'The server logout $url was not reached '
            '(${e.isTimeout ? 'timeout' : 'no answer'}); logged out here only',
          );
        }
        _signedOut(publish: true);
        if (next != null) {
          page.navigate(next);
        }
      });

  // Where the page goes after the logout: the provider's logout page the
  // server answered, or null.
  Uri? _logoutTarget(Uri url, HttpResponse response) {
    final status = response.statusCode;
    if (status == 0 || (status >= 300 && status < 400)) {
      // fetch with redirect: 'manual' sees an opaque status 0.
      _log.debug(
        'The server logout answered a redirect, which a script cannot '
        "follow: the provider's session (if any) stays",
      );
      return null;
    }
    if (status == 403) {
      _log.warning(
        'The server refused the logout (403): no valid CSRF token. The '
        'server must send the XSRF-TOKEN cookie (CookieCsrfTokenRepository'
        '.withHttpOnlyFalse()) to the page; logged out here only',
      );
      return null;
    }
    if (status < 200 || status > 299) {
      _log.warning('The server logout $url answered $status');
      return null;
    }
    String? target = response.headers[HttpHeaders.locationHeader];
    if (target == null && response.bodyBytes.isNotEmpty) {
      try {
        if (jsonDecode(response.bodyText) case {
          'logoutUrl': final String logoutUrl,
        }) {
          target = logoutUrl;
        }
      } on FormatException {
        // Not JSON: no provider logout.
      }
    }
    if (target == null || target.isEmpty) {
      return null;
    }
    final resolved = Uri.tryParse(target);
    final absolute = resolved == null ? null : url.resolveUri(resolved);
    if (absolute == null ||
        !(absolute.isScheme('http') || absolute.isScheme('https'))) {
      // Never javascript: or data: URLs, whoever sent them.
      _log.warning('The server logout answered an unusable logout URL');
      return null;
    }
    return absolute;
  }

  void _signedOut({required bool publish}) {
    final previous = authentication;
    securityContextHolderStrategy.clearContext();
    if (previous != null) {
      _changes.add(null);
      if (publish) {
        eventPublisher?.publishEvent(LogoutSuccessEvent(previous));
      }
    }
  }

  static bool _isNobody(int status) =>
      status == 401 ||
      status == 403 ||
      status == 204 ||
      status == 0 ||
      (status >= 300 && status < 400);

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A restore or logout is already running');
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  /// The authentication the user endpoint's answer [json] describes (see
  /// the class); throws a [FormatException] when it names nobody.
  static Authentication userFrom(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('not a JSON object');
    }
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('no name');
    }
    final authorities = <GrantedAuthority>[
      if (json['authorities'] case final List<Object?> list)
        for (final entry in list)
          if (switch (entry) {
                final String value => value,
                {'authority': final String value} => value,
                _ => null,
              }
              case final String value when value.isNotEmpty)
            SimpleGrantedAuthority(value),
    ];
    final attributes = switch (json['attributes']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    final user = _ServerUser(name, attributes, authorities);
    return switch (json['registrationId']) {
      final String id when id.isNotEmpty => OAuth2AuthenticationToken(
        user,
        authorities,
        id,
      ),
      _ => PreAuthenticatedAuthenticationToken.authenticated(
        user,
        null,
        authorities,
      ),
    };
  }
}

// The user as the server's user endpoint describes them.
final class _ServerUser implements OAuth2User {
  _ServerUser(
    this.name,
    Map<String, Object?> attributes,
    List<GrantedAuthority> authorities,
  ) : attributes = Map.unmodifiable(attributes),
      authorities = List.unmodifiable(authorities);

  @override
  final String name;

  @override
  final Map<String, Object?> attributes;

  @override
  final List<GrantedAuthority> authorities;

  @override
  T? getAttribute<T>(String name) => switch (attributes[name]) {
    final T value => value,
    _ => null,
  };

  @override
  bool operator ==(Object other) => other is _ServerUser && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() =>
      'OAuth2User [Name: [$name], Granted Authorities: '
      '$authorities]';
}
