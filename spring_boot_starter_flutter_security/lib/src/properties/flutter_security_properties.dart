import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// How a Flutter web app logs its user in: `spring.flutter.security.web.mode`.
///
/// A browser has no safe place for tokens, so the web needs a login of
/// its own; the app's code stays the same as on phones
/// (`OAuth2LoginService`).
enum WebLoginMode {
  /// The app's server logs the user in (backend-for-frontend, the
  /// default): `oauth2Login()` of `spring_boot_starter_security` keeps the
  /// tokens, the browser holds only an `HttpOnly` session cookie.
  server,

  /// The browser logs in by itself, as a public client with PKCE and the
  /// tokens in the tab's memory (`SpaOAuth2LoginService`): for an app
  /// without a server of its own. The provider must accept public browser
  /// clients and allow the page's origin (CORS) on its token endpoint.
  spa,
}

/// The settings of the web login, `spring.flutter.security.web.*`: which
/// mode, in `server` mode where the app's server is and which of its
/// endpoints log in, say who is logged in and log out, and in `spa` mode
/// whether a reload brings the user back without a click.
///
/// Read only on the web (the `web` platform profile). Most apps in server
/// mode set at most [serverUrl] (when the API is on another origin than
/// the page), [userEndpoint] and [logoutUrl]:
///
/// ```properties
/// # lib/resources/application-web.properties
/// spring.flutter.security.web.server-url=https://api.neon.books
/// spring.flutter.security.web.user-endpoint=/api/me
/// spring.flutter.security.web.logout-url=/api/logout
/// ```
///
/// An app in spa mode sets the mode; its registrations are the usual
/// `spring.security.oauth2.client.*` ones:
///
/// ```properties
/// spring.flutter.security.web.mode=spa
/// ```
///
/// Spring has no counterpart: Spring Security logs browsers in on the
/// server; these properties tell the browser side where that server is.
@Profile(['web'])
@ConfigurationProperties('spring.flutter.security.web')
final class FlutterWebSecurityProperties implements Validator {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const FlutterWebSecurityProperties({
    this.mode = WebLoginMode.server,
    this.serverUrl,
    this.userEndpoint = defaultUserEndpoint,
    this.logoutUrl = defaultLogoutUrl,
    this.authorizationBaseUri = defaultAuthorizationBaseUri,
    this.silentRestore = true,
  });

  /// The prefix of the properties.
  static const prefix = 'spring.flutter.security.web';

  @override
  bool supports(Object target) => target is FlutterWebSecurityProperties;

  // The app stops at startup for a value it cannot use, instead of failing
  // at the first login.
  @override
  void validate(Object target, Errors errors) {
    final properties = target as FlutterWebSecurityProperties;
    final serverUrl = properties.serverUrl;
    if (serverUrl != null && serverUrl.isNotEmpty) {
      final parsed = Uri.tryParse(serverUrl);
      if (parsed == null ||
          !(parsed.isScheme('http') || parsed.isScheme('https')) ||
          parsed.host.isEmpty ||
          parsed.hasQuery ||
          parsed.hasFragment) {
        errors.rejectValue(
          'serverUrl',
          'url',
          defaultMessage:
              'must be an absolute http(s) URL without query or fragment',
        );
      }
    }
    void endpoint(String field, String value) {
      final parsed = Uri.tryParse(value);
      if (parsed == null ||
          !(value.startsWith('/') ||
              parsed.isScheme('http') ||
              parsed.isScheme('https'))) {
        errors.rejectValue(
          field,
          'endpoint',
          defaultMessage:
              'must be a path starting with / or an absolute http(s) URL',
        );
      }
    }

    endpoint('userEndpoint', properties.userEndpoint);
    endpoint('logoutUrl', properties.logoutUrl);
    endpoint('authorizationBaseUri', properties.authorizationBaseUri);
  }

  /// `/user`: the path of the server's "who is logged in" endpoint, as in
  /// Spring's guide "Spring Boot and OAuth2".
  static const defaultUserEndpoint = '/user';

  /// `/logout`: Spring Security's logout URL.
  static const defaultLogoutUrl = '/logout';

  /// `/oauth2/authorization`: where Spring Security's `oauth2Login()`
  /// starts a login (`OAuth2AuthorizationRequestRedirectFilter`).
  static const defaultAuthorizationBaseUri = '/oauth2/authorization';

  /// Who logs in: the app's server (backend-for-frontend), or the browser by
  /// itself (`spa`: a public client with PKCE, tokens in the tab's memory,
  /// DPoP with a non-extractable WebCrypto key; without a registration the
  /// app stops at startup).
  ///
  /// `spring.flutter.security.web.mode`: [WebLoginMode.server] by default.
  final WebLoginMode mode;

  /// The app's server, with its context path if any. Default: the page's
  /// origin.
  ///
  /// `spring.flutter.security.web.server-url`: the app's server
  /// (`https://api.neon.books`, with a context path if it has one), or
  /// `null` when it serves the page too (the same origin, the default).
  final String? serverUrl;

  /// `GET` with the session cookie: who is logged in, as `{"name",
  /// "authorities", "registrationId", "attributes"}` (only `name` required).
  ///
  /// `spring.flutter.security.web.user-endpoint`: the server's endpoint
  /// that answers who holds the session ([defaultUserEndpoint]); a path
  /// on [serverUrl] or an absolute URL.
  final String userEndpoint;

  /// `POST` with the CSRF token; an answer `{"logoutUrl": "..."}` or a `2xx`
  /// with `Location` sends the page to the provider's logout.
  ///
  /// `spring.flutter.security.web.logout-url`: the server's logout
  /// ([defaultLogoutUrl]), posted with the CSRF token; a path on
  /// [serverUrl] or an absolute URL.
  final String logoutUrl;

  /// Where the server starts a login; `login('keycloak')` goes to
  /// `<server-url><this>/keycloak`.
  ///
  /// `spring.flutter.security.web.authorization-base-uri`: where the
  /// server starts a login, followed by `/{registrationId}`
  /// ([defaultAuthorizationBaseUri]); a path on [serverUrl] or an
  /// absolute URL.
  final String authorizationBaseUri;

  /// Spa mode: after a reload or in a new tab, `restore()` sends the page to
  /// the provider with `prompt=none` when someone logged in in this browser
  /// before, and comes back logged in (or with `login_required`: nobody).
  ///
  /// `spring.flutter.security.web.silent-restore` (spa mode, `true` by
  /// default): whether `restore()` brings back, after a reload or in a new
  /// tab, a user who logged in in this browser, by sending the page to the
  /// provider with `prompt=none` (no login page shown; the provider
  /// answers at once from its own session). `false`: after a reload
  /// nobody is logged in until the next `login()`.
  final bool silentRestore;

  /// The server's address as seen from the page at [page]: [serverUrl],
  /// or the page's origin when it is not set.
  Uri server(Uri page) => switch (serverUrl) {
    final url? when url.isNotEmpty => Uri.parse(url),
    _ => Uri(scheme: page.scheme, host: page.host, port: page.port),
  };

  /// Whether `fetch` must be asked to send the cookies to the server of
  /// the page at [page]: [FetchCredentials.include] for a server on
  /// another origin, [FetchCredentials.sameOrigin] (the browser's
  /// default, which sends them to the page's own origin) otherwise.
  FetchCredentials credentials(Uri page) => sameOrigin(page, server(page))
      ? FetchCredentials.sameOrigin
      : FetchCredentials.include;

  /// [path] (a property's value) on [server]: an absolute URL as it is, a
  /// path after the server's own path.
  static Uri resolve(Uri server, String path) {
    final parsed = Uri.parse(path);
    if (parsed.hasScheme) {
      return parsed;
    }
    final base = server.path.endsWith('/')
        ? server.path.substring(0, server.path.length - 1)
        : server.path;
    return server.replace(
      path: '$base${parsed.path}',
      query: parsed.hasQuery ? parsed.query : null,
    );
  }

  /// Whether [url] goes to the origin of [server] (scheme, host, port).
  static bool sameOrigin(Uri url, Uri server) =>
      url.scheme.toLowerCase() == server.scheme.toLowerCase() &&
      url.host.toLowerCase() == server.host.toLowerCase() &&
      url.port == server.port;
}

/// The settings of the Flutter security starter, `spring.flutter.security.*`:
/// the secret store's name on desktops and the login window on Apple
/// systems. The web login, `spring.flutter.security.web.*`, is
/// [FlutterWebSecurityProperties]: a class of its own, a bean on the web
/// only, so a bad value there does not stop an app on a phone.
@ConfigurationProperties('spring.flutter.security')
final class FlutterSecurityProperties {
  /// Settings with these values; the defaults are those of an app without
  /// any property.
  const FlutterSecurityProperties({
    this.applicationId,
    this.ephemeralSession = false,
  });

  /// The prefix of the properties.
  static const prefix = 'spring.flutter.security';

  /// Apps on Windows and Linux: the name the app's secrets are kept under,
  /// apart from other apps' (Windows: the folder under
  /// `%LOCALAPPDATA%\spring_secret_store`, `\` separates folders; Linux: the
  /// Secret Service items' `application` attribute). Default: the app's own
  /// id.
  final String? applicationId;

  /// Apps on iOS and macOS: the login window (`ASWebAuthenticationSession`)
  /// keeps no cookies of Safari: no system prompt before the window, but no
  /// single sign-on (every login asks for the password).
  final bool ephemeralSession;
}
