import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_security/src/web/entry_points.dart';

const _log = SpringLog('spring.security.oauth2.client.oidc');

/// A [LogoutSuccessHandler] that ends the user's session at the OpenID
/// Connect provider too (RP-initiated logout).
///
/// Logging out of the application alone leaves the browser logged in at
/// the provider: the next login passes without a password. After the
/// local logout, this handler redirects the browser to the provider's
/// `end_session_endpoint` (from its discovery metadata) with the ID token
/// of the login as `id_token_hint` and, when [postLogoutRedirectUri] is
/// set, where the provider sends the browser back afterwards. That URI
/// may use `{baseUrl}`, `{baseScheme}`, `{baseHost}`, `{basePort}`,
/// `{basePath}` and `{registrationId}`, filled in from the request; the
/// provider must allow it. A user who did not log in with OpenID Connect,
/// or a provider without the endpoint, gets the plain redirect to
/// [logoutSuccessUrl].
///
/// ```dart
/// @Bean()
/// SecurityFilterChain web(
///   HttpSecurity http,
///   ClientRegistrationRepository registrations,
/// ) => http
///     .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
///     .oauth2Login()
///     .logout((logout) => logout.logoutSuccessHandler(
///         OidcClientInitiatedLogoutSuccessHandler(
///           registrations,
///           postLogoutRedirectUri: '{baseUrl}/',
///         )))
///     .build();
/// ```
///
/// The logout itself stays a `POST` with the CSRF token.
///
/// Spring (Java): `OidcClientInitiatedLogoutSuccessHandler`.
final class OidcClientInitiatedLogoutSuccessHandler
    implements LogoutSuccessHandler {
  /// A handler ending the sessions of the providers of
  /// [clientRegistrationRepository].
  const OidcClientInitiatedLogoutSuccessHandler(
    this.clientRegistrationRepository, {
    this.postLogoutRedirectUri,
    this.logoutSuccessUrl = '/',
  });

  /// The registrations, for the provider's `end_session_endpoint`.
  final ClientRegistrationRepository clientRegistrationRepository;

  /// Where the provider sends the browser after its logout, a template
  /// (`{baseUrl}/`); `null` sends none, the provider then shows its own
  /// page.
  final String? postLogoutRedirectUri;

  /// Where the browser goes when the provider's session cannot be ended
  /// (no OpenID Connect login, no endpoint): a path of this application
  /// (the context path is put in front) or an absolute URL; `/` by
  /// default.
  final String logoutSuccessUrl;

  @override
  Future<void> onLogoutSuccess(
    ServerHttpRequest request,
    ServerHttpResponse response,
    Authentication? authentication,
  ) async {
    final target = await _endSessionUri(request, authentication);
    final contextPath = _contextPathOf(request);
    await sendRedirect(
      response,
      target ??
          (_isAbsolute(logoutSuccessUrl)
              ? logoutSuccessUrl
              : '$contextPath$logoutSuccessUrl'),
    );
  }

  Future<String?> _endSessionUri(
    ServerHttpRequest request,
    Authentication? authentication,
  ) async {
    if (authentication is! OAuth2AuthenticationToken) {
      return null;
    }
    final user = authentication.principal;
    if (user is! OidcUser) {
      return null;
    }
    final ClientRegistration? registration;
    try {
      registration = await clientRegistrationRepository.findByRegistrationId(
        authentication.authorizedClientRegistrationId,
      );
    } on Object catch (e) {
      _log.warning(
        'No provider logout: the registration cannot be resolved '
        '(${e.runtimeType})',
      );
      return null;
    }
    final endpoint = registration?.providerDetails.endSessionEndpoint;
    if (registration == null || endpoint == null || endpoint.isEmpty) {
      return null;
    }
    final base = Uri.parse(endpoint);
    final redirect = postLogoutRedirectUri;
    return base
        .replace(
          queryParameters: {
            ...base.queryParametersAll,
            OidcParameterNames.idTokenHint: user.idToken.tokenValue,
            if (redirect != null)
              OidcParameterNames.postLogoutRedirectUri: _expand(
                redirect,
                request,
                registration,
              ),
          },
        )
        .toString();
  }

  static String _expand(
    String template,
    ServerHttpRequest request,
    ClientRegistration registration,
  ) {
    final uri = request.uri;
    final path = _contextPathOf(request);
    final port = uri.hasPort ? ':${uri.port}' : '';
    final variables = {
      'baseScheme': uri.scheme,
      'baseHost': uri.host,
      'basePort': port,
      'basePath': path,
      'baseUrl': '${uri.scheme}://${uri.host}$port$path',
      'registrationId': registration.registrationId,
    };
    return template.replaceAllMapped(
      RegExp(r'\{([A-Za-z]+)\}'),
      (match) => variables[match[1]] ?? match[0]!,
    );
  }
}

// The context path of [request]: what its full path has before the path
// the chain sees.
String _contextPathOf(ServerHttpRequest request) {
  final full = request.uri.path;
  final path = request.path;
  if (full.endsWith(path) && full.length > path.length) {
    return full.substring(0, full.length - path.length);
  }
  if (path == '/' && full.length > 1) {
    return full.endsWith('/') ? full.substring(0, full.length - 1) : full;
  }
  return '';
}

bool _isAbsolute(String url) =>
    RegExp('^[a-z0-9.+-]+://', caseSensitive: false).hasMatch(url);
