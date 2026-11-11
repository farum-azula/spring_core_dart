import 'package:spring_security_core/src/core/authentication.dart';

/// The login of the current user of a client application (a Flutter app,
/// a command-line tool), whatever the provider that logged the user in.
///
/// A client application has one user at a time, unlike a server with one
/// per request. How the user logs in differs from provider to provider (a
/// password, a one-time code, the provider's page in a browser window),
/// so that part is not here: each provider's own type has it. What the
/// rest of the application needs is the same for all of them, and is this
/// interface:
///
/// - who is logged in now ([authentication], [isLoggedIn]) and when that
///   changes ([authenticationChanges]), to redraw what shows the user;
/// - a token to send with a request ([accessToken]), kept fresh;
/// - the login of the last run back after a restart ([restore]);
/// - the end of the login ([logout]).
///
/// So an HTTP client that adds the user's token, a widget that shows the
/// user's name and a route guard are written once against this type and
/// work with any provider (an OAuth 2.0 / OpenID Connect provider, a
/// backend-as-a-service such as Supabase, a login of your own).
///
/// ```dart
/// // Adds the user's token to a request, whatever logged the user in.
/// final class UserTokenHeaders {
///   UserTokenHeaders(this.session);
///
///   final LoginSession session;
///
///   Future<Map<String, String>> headers() async {
///     final token = await session.accessToken();
///     return {if (token != null) 'authorization': 'Bearer $token'};
///   }
/// }
/// ```
///
/// An implementation keeps `SecurityContextHolder` in step: the
/// [authentication] it reports is the one of the current security
/// context, so `@PreAuthorize` and the code that reads the context see
/// the same user. Tokens are credentials: an implementation never logs
/// them and keeps them, between runs, only in a `SecretStore`.
///
/// Spring has no such type: Spring Security logs in the users of a
/// server, one per request (`SecurityContextHolder`, `SecurityContext`),
/// and its OAuth 2.0 client keeps tokens per user and registration
/// (`OAuth2AuthorizedClientManager`).
abstract interface class LoginSession {
  /// Who is logged in now, or `null` when nobody is.
  ///
  /// The user as the last login, [restore] or refresh left it; reading it
  /// starts no request.
  Authentication? get authentication;

  /// Whether a user is logged in: [authentication] is not `null` and is
  /// authenticated.
  bool get isLoggedIn;

  /// The user after each change: a login, a refresh that changed the
  /// user's data, and `null` after a logout or a refresh the provider
  /// refused.
  ///
  /// A broadcast stream, so several parts of the application may listen;
  /// it does not repeat the current value to a new listener (read
  /// [authentication] first).
  Stream<Authentication?> get authenticationChanges;

  /// An access token of the logged-in user that is not about to expire,
  /// or `null` when nobody is logged in.
  ///
  /// A token close to its expiry is refreshed first, so the caller can
  /// send the result at once; concurrent calls share one refresh. When
  /// the provider refuses the refresh (the login was revoked or is too
  /// old), the user is logged out, [authenticationChanges] reports
  /// `null`, and the call completes with `null`. A refresh that could not
  /// be made (no network) completes with an error and logs nobody out.
  ///
  /// The token is a credential: send it only to the server it is for,
  /// and never log it.
  Future<String?> accessToken();

  /// Brings back the login of the last run from where the implementation
  /// keeps it (a `SecretStore`), refreshing its tokens when needed.
  ///
  /// Completes with the user, or with `null` when there was no login or
  /// it can no longer be used. Call it once at startup, before the first
  /// screen that depends on the user.
  Future<Authentication?> restore();

  /// Ends the login: the tokens are forgotten (and revoked at the
  /// provider when it can do that), the security context is cleared and
  /// [authenticationChanges] reports `null`.
  ///
  /// The user is logged out here even when the provider could not be
  /// told. Nothing happens when nobody is logged in.
  Future<void> logout();
}
