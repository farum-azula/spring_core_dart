import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/auth/supabase_auth_exception.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_authentication_token.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_pkce.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_session.dart';
import 'package:spring_boot_starter_supabase/src/auth/supabase_user.dart';
import 'package:spring_boot_starter_supabase/src/config/supabase_properties.dart';
import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Which sessions a logout ends on the server.
enum SupabaseLogoutScope {
  /// This session only: the user stays signed in on their other devices.
  local,

  /// Every session of the user, on every device.
  global,

  /// Every session but this one: the user stays signed in here.
  others,
}

/// What a one-time code (or the token of a link) is for; sent as `type`
/// to Auth's `/verify`.
enum SupabaseOtpType {
  /// A code sent by email to sign in (or to sign up, when the user is
  /// new).
  email('email'),

  /// A code sent by SMS to sign in or to sign up.
  sms('sms'),

  /// The confirmation of a new account's email address.
  signup('signup'),

  /// An invitation.
  invite('invite'),

  /// A magic link.
  magiclink('magiclink'),

  /// A password recovery.
  recovery('recovery'),

  /// The confirmation of a changed email address.
  emailChange('email_change'),

  /// The confirmation of a changed phone number.
  phoneChange('phone_change');

  SupabaseOtpType(this.value);

  /// The name Auth knows the type by.
  final String value;
}

/// The login of the application through Supabase Auth (the bean
/// `supabaseAuth`, also its `LoginSession`): signs users up and in, keeps
/// their session fresh and across restarts, and signs them out.
///
/// ```dart
/// await auth.signInWithPassword(email: email, password: password);
/// print(auth.user?.email);
/// // Every call to Supabase is now made as the user; @PreAuthorize and
/// // the security context see them too.
/// await auth.logout();
/// ```
///
/// - **One login.** The signed-in user is Spring Security's: an
///   `Authentication` ([SupabaseAuthenticationToken]) in the
///   `SecurityContextHolder`, an `AuthenticationSuccessEvent` at each
///   login and restore, a `LogoutSuccessEvent` at [logout], and
///   [authenticationChanges] at every change. `SupabaseCredentials` takes
///   the token of every call from here.
/// - **Roles** are `ROLE_<role>` for each string in `app_metadata.roles`,
///   as on a server; `user_metadata` grants nothing.
/// - **The session** is kept in the application's `SecretStore`
///   (`spring.supabase.auth.persist-session`, on by default; in memory
///   without a store) and brought back at startup ([restore]).
/// - **Refresh.** [accessToken] refreshes a token that expires within
///   `spring.supabase.auth.refresh-margin`; however many callers wait,
///   one request is made. With `spring.supabase.auth.auto-refresh` a
///   timer does it before the expiry. A refresh token is used once: the
///   new one replaces it at once. When Auth refuses it
///   ([sessionEndingCodes]) the user is signed out here; when Auth cannot
///   be reached the session stays and the call fails.
/// - **Redirects** go only to `spring.supabase.auth.redirect-urls`: any
///   other `redirectTo` is an [ArgumentError] before a request is made.
/// - **Providers and links** use PKCE (S256): the code that comes back is
///   exchanged with a verifier that never left the application.
/// - **Errors** are Spring Security's `AuthenticationException`s
///   ([SupabaseAuthErrors]) with Auth's error code
///   ([SupabaseAuthFailure]); no answer at all is a
///   `SupabaseUnavailableException`. No token, password or code is ever
///   in a message or a log.
///
/// Spring (Java): no counterpart; the nearest are `oauth2Login()` and
/// `OAuth2AuthorizedClientManager` of Spring Security.
final class SupabaseAuth implements LoginSession, AsyncStartup, DisposableBean {
  /// The login of the project of [http].
  ///
  /// [secretStore] keeps the session (when
  /// `spring.supabase.auth.persist-session` is true; else, and without
  /// one, it is kept in memory); [authorizationWindow] opens a provider's
  /// page for [signInWithProvider]; [eventPublisher] gets the login and
  /// logout events; [securityContextHolderStrategy] is where the current
  /// user is set (`SecurityContextHolder`'s unless given); [errors] turns
  /// Auth's errors into exceptions. [clock] and [timerFactory] are for
  /// tests.
  SupabaseAuth({
    required this.http,
    SecretStore? secretStore,
    this.authorizationWindow,
    this.eventPublisher,
    SecurityContextHolderStrategy? securityContextHolderStrategy,
    SupabaseAuthErrors? errors,
    DateTime Function()? clock,
    Timer Function(Duration delay, void Function() callback)? timerFactory,
  }) : secretStore =
           (http.properties.auth.persistSession ? secretStore : null) ??
           InMemorySecretStore(),
       errors = errors ?? SupabaseAuthErrors(),
       _strategy = securityContextHolderStrategy,
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  /// The key of the session in the [secretStore].
  static const sessionKey = 'supabase.auth.session';

  /// The key, in the [secretStore], of the login that waits for its
  /// redirect (its PKCE code verifier).
  static const pkceKey = 'supabase.auth.pkce';

  /// Auth's error codes that mean the session is over, whatever is tried
  /// next: answered to a refresh or to a call made with the user's token,
  /// they sign the user out here.
  ///
  /// `invalid_grant` is what older versions of Auth answer to a refused
  /// refresh token. A refresh token Auth cannot even read
  /// (`validation_failed`) ends the session too. Anything else (a rate
  /// limit, a failure of the service, an answer of a gateway in front of
  /// Auth) keeps the session.
  static const Set<String> sessionEndingCodes = {
    'refresh_token_not_found',
    'refresh_token_already_used',
    'session_not_found',
    'session_expired',
    'user_not_found',
    'user_banned',
    'invalid_grant',
  };

  static const Set<String> _refreshEndingCodes = {
    ...sessionEndingCodes,
    'validation_failed',
  };

  static const _reservedQueryParameters = {
    'provider',
    'redirect_to',
    'scopes',
    'code_challenge',
    'code_challenge_method',
  };

  static const _minRefreshDelay = Duration(seconds: 1);
  static const _firstRetryDelay = Duration(seconds: 2);
  static const _maxRetryDelay = Duration(minutes: 1);

  static const _log = SpringLog('spring.supabase.auth');

  /// The project.
  final SupabaseHttp http;

  /// Where the session is kept between runs.
  final SecretStore secretStore;

  /// What opens a provider's login page; `null` where the application has
  /// none (a server, a web page).
  final AuthorizationWindow? authorizationWindow;

  /// Where the login and logout events go; `null` for none.
  final ApplicationEventPublisher? eventPublisher;

  /// What turns Auth's errors into exceptions.
  final SupabaseAuthErrors errors;

  final SecurityContextHolderStrategy? _strategy;
  final DateTime Function() _clock;
  final Timer Function(Duration delay, void Function() callback) _timerFactory;

  final StreamController<Authentication?> _changes =
      StreamController<Authentication?>.broadcast();

  SupabaseSession? _session;
  SupabaseAuthenticationToken? _authentication;

  // Counts the logins and logouts: an answer that arrives after another
  // one of them is dropped.
  int _epoch = 0;

  Future<SupabaseSession?>? _refreshing;
  Timer? _timer;
  Duration? _retryDelay;
  Future<void>? _startup;
  Future<void> _storeQueue = Future<void>.value();
  bool _closed = false;

  SupabaseAuthProperties get _properties => http.properties.auth;

  SecurityContextHolderStrategy get _contexts =>
      _strategy ?? SecurityContextHolder.getContextHolderStrategy();

  DateTime _now() => _clock().toUtc();

  // The bearer token of the calls that make a session: nobody is signed
  // in yet.
  String get _anonKey => switch (http.properties.anonKey?.trim()) {
    final key? when key.isNotEmpty => key,
    _ => throw StateError(
      'spring.supabase.anon-key is not set: Supabase Auth needs the '
      "project's anon (publishable) key",
    ),
  };

  // The login.

  /// The signed-in user, or `null` when nobody is.
  SupabaseUser? get user => _authentication?.principal;

  @override
  SupabaseAuthenticationToken? get authentication => _authentication;

  @override
  bool get isLoggedIn => _authentication?.isAuthenticated ?? false;

  @override
  Stream<Authentication?> get authenticationChanges => _changes.stream;

  /// Creates a user with an [email] or a [phone] and a [password], with
  /// [data] as their `user_metadata`.
  ///
  /// Completes with the signed-in user when the project confirms new
  /// users by itself, else with `null`: nobody is signed in until the
  /// address is confirmed (the link of the email comes back to
  /// [redirectTo] and is finished by [completeSignIn]; a code is checked
  /// by [verifyOtp]). Auth answers the same for an address that is taken,
  /// so that nobody learns who has an account.
  ///
  /// ```dart
  /// final signedIn = await auth.signUp(
  ///   email: 'ada@example.com',
  ///   password: password,
  ///   data: {'name': 'Ada'},
  /// );
  /// if (signedIn == null) showMessage('Check your inbox');
  /// ```
  Future<SupabaseAuthenticationToken?> signUp({
    required String password,
    String? email,
    String? phone,
    Map<String, Object?> data = const {},
    String? redirectTo,
  }) async {
    final identity = _identity(email, phone);
    _secret(password, 'password');
    final redirect = _redirect(redirectTo);
    final byEmail = identity.containsKey('email');
    final pkce = byEmail ? await _startPkce(redirect) : null;
    final Map<String, Object?> json;
    try {
      json = await _send(
        HttpMethod.post,
        '/signup',
        query: [
          if (byEmail && redirect != null) MapEntry('redirect_to', redirect),
        ],
        json: {
          ...identity,
          'password': password,
          'data': data,
          if (!byEmail) 'channel': 'sms',
          ...?_challenge(pkce),
        },
        bearer: _anonKey,
        secrets: [password],
      );
    } on AuthenticationException {
      // Refused: no link will come back. (Without an answer the email
      // may be on its way, and the verifier stays.)
      await _clearPkce(pkce);
      rethrow;
    }
    if (json['access_token'] == null) {
      // The address is to be confirmed first.
      return null;
    }
    final session = _sessionOf(json);
    // Signed in at once: no link will come back for this verifier.
    await _clearPkce(pkce);
    return await _signedIn(session);
  }

  /// Signs in with an [email] or a [phone] and a [password].
  ///
  /// Throws a `BadCredentialsException` when they are wrong (Auth does
  /// not say which).
  Future<SupabaseAuthenticationToken> signInWithPassword({
    required String password,
    String? email,
    String? phone,
  }) async {
    final identity = _identity(email, phone);
    _secret(password, 'password');
    final json = await _send(
      HttpMethod.post,
      '/token',
      query: const [MapEntry('grant_type', 'password')],
      json: {...identity, 'password': password},
      bearer: _anonKey,
      secrets: [password],
    );
    return await _signedIn(_sessionOf(json));
  }

  /// Sends a one-time code or a magic link to an [email], or a code to a
  /// [phone]. Nobody is signed in yet: the code is checked by
  /// [verifyOtp], the link comes back to [redirectTo] and is finished by
  /// [completeSignIn].
  ///
  /// With [createUser] (the default) an unknown address becomes a new
  /// user.
  Future<void> signInWithOtp({
    String? email,
    String? phone,
    bool createUser = true,
    String? redirectTo,
  }) async {
    final identity = _identity(email, phone);
    final redirect = _redirect(redirectTo);
    final byEmail = identity.containsKey('email');
    final pkce = byEmail ? await _startPkce(redirect) : null;
    try {
      await _send(
        HttpMethod.post,
        '/otp',
        query: [
          if (byEmail && redirect != null) MapEntry('redirect_to', redirect),
        ],
        json: {
          ...identity,
          'create_user': createUser,
          if (!byEmail) 'channel': 'sms',
          ...?_challenge(pkce),
        },
        bearer: _anonKey,
      );
    } on AuthenticationException {
      // Refused: no link will come back. (Without an answer the email
      // may be on its way, and the verifier stays.)
      await _clearPkce(pkce);
      rethrow;
    }
  }

  /// Signs in with the one-time code [token] that was sent to an [email]
  /// or a [phone]; [type] says what the code was sent for.
  ///
  /// Throws a `BadCredentialsException` when the code is wrong or too
  /// old.
  ///
  /// ```dart
  /// await auth.signInWithOtp(email: email);
  /// // The user types the code of the email:
  /// await auth.verifyOtp(
  ///   email: email,
  ///   token: code,
  ///   type: SupabaseOtpType.email,
  /// );
  /// ```
  Future<SupabaseAuthenticationToken> verifyOtp({
    required String token,
    required SupabaseOtpType type,
    String? email,
    String? phone,
  }) async {
    final identity = _identity(email, phone);
    _secret(token, 'token');
    final json = await _send(
      HttpMethod.post,
      '/verify',
      json: {...identity, 'token': token, 'type': type.value},
      bearer: _anonKey,
      secrets: [token],
    );
    return await _signedIn(_sessionOf(json));
  }

  /// Signs in with the [idToken] a [provider]'s own SDK gave (the native
  /// Google or Apple sign-in): Auth checks it and answers with a
  /// session.
  ///
  /// [accessToken] is the provider's access token, when the ID token
  /// names one (`at_hash`); [nonce] is the nonce the ID token was asked
  /// with.
  Future<SupabaseAuthenticationToken> signInWithIdToken({
    required String provider,
    required String idToken,
    String? accessToken,
    String? nonce,
  }) async {
    _name(provider, 'provider');
    _secret(idToken, 'idToken');
    final json = await _send(
      HttpMethod.post,
      '/token',
      query: const [MapEntry('grant_type', 'id_token')],
      json: {
        'provider': provider,
        'id_token': idToken,
        'access_token': ?accessToken,
        'nonce': ?nonce,
      },
      bearer: _anonKey,
      secrets: [idToken, accessToken, nonce],
    );
    return await _signedIn(_sessionOf(json));
  }

  /// Signs in through [provider] (`google`, `github`, `apple`, ...): its
  /// page is opened in the application's [authorizationWindow], and the
  /// code that comes back is exchanged for a session (PKCE, S256).
  ///
  /// [scopes] are asked of the provider; [queryParameters] are passed on
  /// to it (`prompt`, `access_type`, ...). [redirectTo] is one of
  /// `spring.supabase.auth.redirect-urls` (the first unless given).
  ///
  /// Throws a [StateError] when the application has no
  /// `AuthorizationWindow` bean (open the page yourself:
  /// [authorizationUrl], then [completeSignIn]), an
  /// `AuthorizationCancelledException` when the user closed the page, and
  /// an `AuthenticationException` when the redirect that came back is not
  /// the one asked for, carries an error, or its code is refused.
  ///
  /// ```dart
  /// await auth.signInWithProvider('github', scopes: ['read:user']);
  /// ```
  Future<SupabaseAuthenticationToken> signInWithProvider(
    String provider, {
    List<String> scopes = const [],
    String? redirectTo,
    Map<String, String> queryParameters = const {},
  }) async {
    final configured = _neededRedirect(redirectTo);
    final asked = Uri.parse(configured);
    _checkAuthorization(provider, queryParameters);
    final window =
        authorizationWindow ??
        (throw StateError(
          'signInWithProvider needs an AuthorizationWindow bean to open '
          "the provider's page (spring_boot_starter_flutter_security "
          'declares one); without it, open authorizationUrl(...) yourself '
          'and finish with completeSignIn(redirect)',
        ));
    // Kept in this call only: the window answers while it runs.
    final pkce = SupabasePkceFlow.start(redirectTo: configured);
    var used = asked;
    final redirect = await window.authorize(
      redirectUri: asked,
      authorizationUri: (actual) {
        used = _windowRedirect(asked, actual);
        return _authorizeUrl(
          provider,
          // As it is written in the configuration unless the window took
          // a port of its own.
          used == asked ? configured : '$used',
          pkce,
          scopes,
          queryParameters,
        );
      },
    );
    return await _exchange(_codeOf(redirect, used), pkce.verifier);
  }

  /// The address of [provider]'s login page, for an application that
  /// opens the browser itself; the redirect that comes back is finished
  /// by [completeSignIn] (or its code by [exchangeCode]).
  ///
  /// The PKCE verifier of the login is kept in the [secretStore] until
  /// then, so the application may be restarted in between. Starting
  /// another login replaces it: one login waits at a time.
  ///
  /// ```dart
  /// final url = await auth.authorizationUrl('google');
  /// await launchUrl(url);
  /// // Later, from the application's deep link:
  /// await auth.completeSignIn(link);
  /// ```
  Future<Uri> authorizationUrl(
    String provider, {
    List<String> scopes = const [],
    String? redirectTo,
    Map<String, String> queryParameters = const {},
  }) async {
    final redirect = _neededRedirect(redirectTo);
    _checkAuthorization(provider, queryParameters);
    final pkce = await _startPkce(redirect);
    return _authorizeUrl(provider, redirect, pkce, scopes, queryParameters);
  }

  /// Finishes the login that waits for its redirect, with the address the
  /// application was opened with ([redirect]): a provider's answer after
  /// [authorizationUrl], or the link of an email sent by [signInWithOtp]
  /// (a magic link), [signUp] (the confirmation) or [resetPassword] (the
  /// user is then signed in and sets a new password with [updateUser]).
  ///
  /// The redirect must be the address the login asked for (the same
  /// scheme, host, port and path) and carry a `code`; the code is
  /// exchanged with the verifier kept since the login started, which is
  /// used once. Throws an `AuthenticationException` when no login waits,
  /// when the address is another one (the waiting login stays), when it
  /// carries an `error`, or when Auth refuses the code.
  Future<SupabaseAuthenticationToken> completeSignIn(Uri redirect) async {
    final pkce = await _readPkce();
    final asked = pkce?.redirectTo;
    if (pkce == null || asked == null) {
      throw SupabaseAuthenticationException(
        'No login is waiting for a redirect: start one with '
        'authorizationUrl, signInWithOtp, signUp or resetPassword (with '
        'spring.supabase.auth.redirect-urls set)',
      );
    }
    final expected = Uri.parse(asked);
    if (!_isRedirectTo(redirect, expected)) {
      throw SupabaseAuthenticationException(
        'The redirect is not the address the login asked for '
        '(${_address(expected)})',
      );
    }
    // From here the verifier is spent, whatever the redirect carries.
    await _clearPkce(pkce);
    return await _exchange(_codeOf(redirect, expected), pkce.verifier);
  }

  /// Exchanges the authorization [code] of the login that waits (see
  /// [completeSignIn], which also checks where the code came from) for a
  /// session. The verifier is used once.
  Future<SupabaseAuthenticationToken> exchangeCode(String code) async {
    _secret(code, 'code');
    final pkce = await _readPkce();
    if (pkce == null) {
      throw SupabaseAuthenticationException(
        'No login is waiting for a code: start one with authorizationUrl, '
        'signInWithOtp, signUp or resetPassword',
      );
    }
    await _clearPkce(pkce);
    return await _exchange(code, pkce.verifier);
  }

  /// Sends the email that lets the user of [email] set a new password.
  /// Its link comes back to [redirectTo]; [completeSignIn] signs the user
  /// in, and `updateUser(password: ...)` sets the password.
  ///
  /// Auth answers the same whether the address has an account or not.
  Future<void> resetPassword(String email, {String? redirectTo}) async {
    final identity = _identity(email, null);
    final redirect = _redirect(redirectTo);
    final pkce = await _startPkce(redirect);
    try {
      await _send(
        HttpMethod.post,
        '/recover',
        query: [if (redirect != null) MapEntry('redirect_to', redirect)],
        json: {...identity, ...?_challenge(pkce)},
        bearer: _anonKey,
      );
    } on AuthenticationException {
      // Refused: no link will come back. (Without an answer the email
      // may be on its way, and the verifier stays.)
      await _clearPkce(pkce);
      rethrow;
    }
  }

  /// Changes the signed-in user: their [email] (Auth confirms the new
  /// address first), their [password], or [data], merged into their
  /// `user_metadata`. Completes with the user as Auth has them now, who
  /// is also the new [user].
  ///
  /// Throws an `AuthenticationCredentialsNotFoundException` when nobody
  /// is signed in.
  Future<SupabaseUser> updateUser({
    String? email,
    String? password,
    Map<String, Object?>? data,
  }) async {
    if (email == null && password == null && data == null) {
      throw ArgumentError('updateUser needs an email, a password or data');
    }
    if (password != null) {
      _secret(password, 'password');
    }
    final json = await _asUser(
      HttpMethod.put,
      json: {'email': ?email, 'password': ?password, 'data': ?data},
      secrets: [password],
    );
    return await _userChanged(json);
  }

  /// Reads the signed-in user from Auth again (after their address was
  /// confirmed, or the project changed their roles) and makes them the
  /// new [user].
  ///
  /// The roles of the access token change only at its next refresh
  /// ([refreshSession]).
  Future<SupabaseUser> reloadUser() async =>
      await _userChanged(await _asUser(HttpMethod.get));

  /// Exchanges the refresh token for a new pair of tokens now, whatever
  /// the age of the access token. Concurrent calls share one request.
  ///
  /// Throws a [SupabaseSessionExpiredException] when Auth refuses the
  /// refresh token (the user is then signed out here), an
  /// `AuthenticationCredentialsNotFoundException` when nobody is signed
  /// in, and a `SupabaseUnavailableException` when Auth cannot be reached
  /// (the session stays).
  Future<SupabaseAuthenticationToken> refreshSession() async {
    if (_session == null) {
      throw AuthenticationCredentialsNotFoundException('Nobody is signed in');
    }
    await _refresh();
    return _authentication ??
        (throw AuthenticationCredentialsNotFoundException(
          'The user was signed out while the session was refreshed',
        ));
  }

  @override
  Future<String?> accessToken() async {
    final session = _session;
    if (session == null || _authentication == null) {
      return null;
    }
    if (!session.expiresWithin(_properties.refreshMargin, _now())) {
      return session.accessToken;
    }
    try {
      return (await _refresh())?.accessToken;
    } on _SessionEnded {
      // Signed out, and the listeners were told.
      return null;
    }
  }

  /// Brings back the session of the last run from the [secretStore].
  ///
  /// A session whose access token has expired is refreshed first; when
  /// Auth refuses its refresh token, it is forgotten and the result is
  /// `null`. When Auth cannot be reached the user is restored all the
  /// same (an application starts offline) and the tokens are refreshed
  /// at their next use. A stored value that cannot be read is removed.
  /// Publishes an `AuthenticationSuccessEvent`, as Spring's remember-me
  /// login does.
  ///
  /// The application does not call it: it runs at startup
  /// ([awaitStartup]).
  @override
  Future<SupabaseAuthenticationToken?> restore() async {
    if (_session != null) {
      return _authentication;
    }
    final epoch = _epoch;
    final stored = await secretStore.read(sessionKey);
    if (epoch != _epoch || stored == null) {
      return _authentication;
    }
    final session = SupabaseSession.decode(stored);
    if (session == null) {
      // Never log the value: it holds tokens.
      _log.warning('Removing a stored session that cannot be read');
      await _inOrder(() => secretStore.delete(sessionKey));
      return null;
    }
    if (!session.expiresWithin(_properties.refreshMargin, _now())) {
      return _restored(session);
    }
    // Not the login yet: nobody is told until the tokens are fresh.
    _epoch++;
    _session = session;
    final refreshing = _epoch;
    try {
      await _refresh();
    } on _SessionEnded {
      return null;
    } on Object catch (e) {
      if (refreshing != _epoch) {
        return _authentication;
      }
      _log.debug(
        'The stored session could not be refreshed (${e.runtimeType}); '
        'restored as it is, to be refreshed later',
      );
      return _restored(session);
    }
    final authentication = _authentication;
    if (authentication != null && refreshing == _epoch) {
      eventPublisher?.publishEvent(AuthenticationSuccessEvent(authentication));
    }
    return authentication;
  }

  /// Signs the user out: the session is forgotten here (memory, the
  /// [secretStore], the security context, the refresh timer) and then
  /// revoked at Auth, for [scope] (this session only unless given).
  ///
  /// The user is signed out here even when Auth cannot be reached or
  /// refuses: a logout never depends on the network. (An access token
  /// that has expired cannot revoke anything, so the refresh token is
  /// exchanged one last time for one that can.) With
  /// [SupabaseLogoutScope.others] the user stays signed in here, and a
  /// failure is thrown.
  ///
  /// When the [secretStore] could not forget the session, the user is
  /// signed out of the running application all the same and the store's
  /// error is rethrown: the stored session may come back at the next
  /// start, so tell the user.
  @override
  Future<void> logout({
    SupabaseLogoutScope scope = SupabaseLogoutScope.local,
  }) async {
    if (scope == SupabaseLogoutScope.others) {
      await _logoutOthers();
      return;
    }
    final session = _session;
    Object? failure;
    StackTrace? failureTrace;
    try {
      await _signedOut(logout: true);
    } on Object catch (e, trace) {
      failure = e;
      failureTrace = trace;
    }
    if (session != null) {
      await _revoke(session, scope);
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureTrace!);
    }
  }

  // The life of the bean.

  /// Restores the session of the last run when the application starts.
  /// Never fails the start: without a network the user is restored
  /// offline, and any other failure is logged (without the session).
  @override
  Future<void> awaitStartup() => _startup ??= _restoreAtStartup();

  Future<void> _restoreAtStartup() async {
    try {
      await restore();
    } on Object catch (e) {
      _log.warning(
        'The session of the last run could not be restored '
        '(${e.runtimeType})',
      );
    }
  }

  /// Stops the refresh timer and closes [authenticationChanges], when the
  /// application stops. The session stays in the [secretStore] for the
  /// next run.
  @override
  Future<void> destroy() async {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    // Not awaited: a listener that is paused would hold the stop back.
    unawaited(_changes.close());
  }

  // Requests.

  Future<Map<String, Object?>> _send(
    HttpMethod method,
    String path, {
    required String bearer,
    Iterable<MapEntry<String, String>> query = const [],
    Object? json,
    Iterable<String?> secrets = const [],
  }) async {
    final response = await http.send(
      SupabaseService.auth,
      method,
      path,
      query: query,
      json: json,
      bearer: bearer,
    );
    if (!response.isSuccess) {
      throw errors.translate(
        errors.read(response, secrets: _sent(secrets, bearer)),
      );
    }
    return _object(response);
  }

  // Every secret a request carried: its own, its bearer token and the
  // key. Should an answer repeat one, it never reaches a message.
  List<String?> _sent(Iterable<String?> secrets, String bearer) => [
    ...secrets,
    bearer,
    http.properties.anonKey?.trim(),
    http.properties.serviceRoleKey?.trim(),
  ];

  static Map<String, Object?> _object(HttpResponse response) {
    if (response.bodyBytes.isEmpty) {
      return const {};
    }
    try {
      final json = jsonDecode(response.bodyText);
      return json is Map<String, Object?> ? json : const {};
    } on FormatException {
      return const {};
    }
  }

  // `/user` as the signed-in user, with a token that is not about to
  // expire.
  Future<Map<String, Object?>> _asUser(
    HttpMethod method, {
    Object? json,
    Iterable<String?> secrets = const [],
  }) async {
    final token = await accessToken();
    final epoch = _epoch;
    if (token == null) {
      throw AuthenticationCredentialsNotFoundException('Nobody is signed in');
    }
    final response = await http.send(
      SupabaseService.auth,
      method,
      '/user',
      json: json,
      bearer: token,
    );
    if (response.isSuccess) {
      return _object(response);
    }
    final error = errors.read(response, secrets: _sent(secrets, token));
    if (!_ends(error, sessionEndingCodes)) {
      throw errors.translate(error);
    }
    if (epoch == _epoch) {
      await _signedOut();
    }
    throw _SessionEnded(
      error.message,
      errorCode: error.code,
      statusCode: error.statusCode,
    );
  }

  static bool _ends(SupabaseAuthError error, Set<String> codes) =>
      codes.contains(error.code) && (error.statusCode ?? 0) < 500;

  SupabaseSession _sessionOf(Map<String, Object?> json) =>
      SupabaseSession.fromResponse(json, _now()) ??
      (throw SupabaseAuthenticationException(
        'Supabase Auth answered without a session',
      ));

  Future<SupabaseAuthenticationToken> _exchange(
    String code,
    String verifier,
  ) async {
    final json = await _send(
      HttpMethod.post,
      '/token',
      query: const [MapEntry('grant_type', 'pkce')],
      json: {'auth_code': code, 'code_verifier': verifier},
      bearer: _anonKey,
      secrets: [code, verifier],
    );
    return await _signedIn(_sessionOf(json));
  }

  // Arguments.

  static Map<String, String> _identity(String? email, String? phone) {
    final hasEmail = email != null && email.trim().isNotEmpty;
    final hasPhone = phone != null && phone.trim().isNotEmpty;
    if (hasEmail == hasPhone) {
      throw ArgumentError('Give an email or a phone, one of the two');
    }
    return hasEmail ? {'email': email.trim()} : {'phone': phone!.trim()};
  }

  // Never ArgumentError.value: the value is a secret.
  static void _secret(String value, String name) {
    if (value.isEmpty) {
      throw ArgumentError('$name is empty');
    }
  }

  static void _name(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$name is empty');
    }
  }

  static void _checkAuthorization(
    String provider,
    Map<String, String> queryParameters,
  ) {
    _name(provider, 'provider');
    for (final name in queryParameters.keys) {
      if (_reservedQueryParameters.contains(name.toLowerCase())) {
        throw ArgumentError.value(
          name,
          'queryParameters',
          'is set by the login itself',
        );
      }
    }
  }

  // Redirects.

  // One of spring.supabase.auth.redirect-urls: [redirectTo] when it is
  // one of them exactly, the first when none is asked for, null when
  // none is configured.
  String? _redirect(String? redirectTo) {
    final allowed = [
      for (final url in _properties.redirectUrls)
        if (url.trim().isNotEmpty) url.trim(),
    ];
    if (redirectTo == null) {
      return allowed.firstOrNull;
    }
    if (!allowed.contains(redirectTo)) {
      throw ArgumentError.value(
        redirectTo,
        'redirectTo',
        'is not one of spring.supabase.auth.redirect-urls: a login comes '
            'back only to an address listed there, exactly as it is written',
      );
    }
    return redirectTo;
  }

  String _neededRedirect(String? redirectTo) =>
      _redirect(redirectTo) ??
      (throw StateError(
        'spring.supabase.auth.redirect-urls is empty: a login through a '
        'provider needs the address it comes back to (the first of the '
        "list is the default), which must also be in the project's own "
        'list of redirect URLs',
      ));

  // The address a window really used. A window on a desktop takes a free
  // port of the loopback address (RFC 8252, 7.3); nothing else may
  // change.
  static Uri _windowRedirect(Uri asked, Uri actual) {
    if (actual == asked) {
      return actual;
    }
    const loopback = {'127.0.0.1', '::1', 'localhost'};
    if (actual.scheme == 'http' &&
        loopback.contains(actual.host) &&
        actual.userInfo.isEmpty &&
        _path(actual) == _path(asked) &&
        !actual.hasFragment) {
      return actual;
    }
    throw StateError(
      'The authorization window changed the redirect address to '
      'something other than a port of the loopback address',
    );
  }

  static String _path(Uri uri) =>
      uri.hasAuthority && uri.path.isEmpty ? '/' : uri.path;

  // Scheme, host and path: what a message may say of an address.
  static String _address(Uri uri) {
    final port = uri.hasPort ? ':${uri.port}' : '';
    final authority = uri.hasAuthority ? '//${uri.host}$port' : '';
    return '${uri.scheme}:$authority${uri.path}';
  }

  // The query of an address that came from outside; null when it cannot
  // be decoded.
  static Map<String, List<String>>? _query(Uri uri) {
    try {
      return uri.queryParametersAll;
    } on Object {
      return null;
    }
  }

  // Whether [redirect] is the address [expected], with whatever Auth
  // added to its query and fragment. Compared part by part: as text,
  // https://app.example.com.evil.org starts with https://app.example.com.
  static bool _isRedirectTo(Uri redirect, Uri expected) {
    if (redirect.scheme != expected.scheme ||
        redirect.userInfo != expected.userInfo ||
        redirect.host != expected.host ||
        redirect.port != expected.port ||
        _path(redirect) != _path(expected)) {
      return false;
    }
    final query = _query(redirect);
    if (query == null) {
      return false;
    }
    for (final MapEntry(:key, :value) in expected.queryParametersAll.entries) {
      if (query[key]?.join('\u0000') != value.join('\u0000')) {
        return false;
      }
    }
    return true;
  }

  // The authorization code of a redirect that came back to [expected].
  String _codeOf(Uri redirect, Uri expected) {
    if (!_isRedirectTo(redirect, expected)) {
      throw SupabaseAuthenticationException(
        'The redirect is not the address the login asked for '
        '(${_address(expected)})',
      );
    }
    // Auth reports a failed login in the query and, still, in the
    // fragment.
    final query = {
      for (final MapEntry(:key, :value) in _query(redirect)!.entries)
        if (value.isNotEmpty) key: value.first,
    };
    final parameters = {..._fragmentParameters(redirect), ...query};
    final error = parameters['error'];
    final errorCode = parameters['error_code'];
    if ((error != null && error.isNotEmpty) ||
        (errorCode != null && errorCode.isNotEmpty)) {
      final description = parameters['error_description'];
      throw errors.translate(
        SupabaseAuthError(
          code: errorCode != null && errorCode.isNotEmpty ? errorCode : error,
          message: SupabaseAuthErrors.protect(
            description != null && description.isNotEmpty
                ? description
                : 'The login was refused',
            const [],
          ),
        ),
      );
    }
    final code = query['code'];
    if (code == null || code.isEmpty) {
      throw SupabaseAuthenticationException(
        'The redirect carries no authorization code',
      );
    }
    return code;
  }

  static Map<String, String> _fragmentParameters(Uri uri) {
    if (uri.fragment.isEmpty) {
      return const {};
    }
    try {
      return Uri.splitQueryString(uri.fragment);
    } on Object {
      return const {};
    }
  }

  Uri _authorizeUrl(
    String provider,
    String redirect,
    SupabasePkceFlow pkce,
    List<String> scopes,
    Map<String, String> queryParameters,
  ) {
    final asked = [
      for (final scope in scopes)
        if (scope.trim().isNotEmpty) scope.trim(),
    ];
    return http.url(
      SupabaseService.auth,
      '/authorize',
      query: [
        MapEntry('provider', provider.trim()),
        MapEntry('redirect_to', redirect),
        if (asked.isNotEmpty) MapEntry('scopes', asked.join(' ')),
        MapEntry('code_challenge', pkce.challenge),
        const MapEntry('code_challenge_method', SupabasePkceFlow.method),
        ...queryParameters.entries,
      ],
    );
  }

  // PKCE.

  static Map<String, String>? _challenge(SupabasePkceFlow? pkce) => pkce == null
      ? null
      : {
          'code_challenge': pkce.challenge,
          'code_challenge_method': SupabasePkceFlow.method,
        };

  // A new login that waits for its redirect; it replaces the one before.
  Future<SupabasePkceFlow> _startPkce(String? redirect) async {
    final pkce = SupabasePkceFlow.start(redirectTo: redirect);
    await secretStore.write(pkceKey, pkce.encode());
    return pkce;
  }

  Future<SupabasePkceFlow?> _readPkce() async {
    final stored = await secretStore.read(pkceKey);
    return stored == null ? null : SupabasePkceFlow.decode(stored);
  }

  // Forgets [pkce] unless another login has replaced it meanwhile.
  Future<void> _clearPkce(SupabasePkceFlow? pkce) async {
    if (pkce == null) {
      return;
    }
    final stored = await _readPkce();
    if (stored == null || stored.verifier == pkce.verifier) {
      await secretStore.delete(pkceKey);
    }
  }

  // The session.

  // Writes and deletes of the session run one after the other, in the
  // order they were asked for: a logout during a login leaves nothing.
  Future<void> _inOrder(Future<void> Function() operation) {
    final next = _storeQueue.then((_) => operation());
    _storeQueue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _persist(SupabaseSession session) async {
    try {
      await _inOrder(() => secretStore.write(sessionKey, session.encode()));
    } on Object catch (e) {
      _log.warning(
        'The session could not be stored (${e.runtimeType}); the user '
        'stays signed in until the application stops',
      );
    }
  }

  SupabaseAuthenticationToken _install(SupabaseSession session) {
    final authentication = session.toAuthentication();
    _session = session;
    _authentication = authentication;
    final contexts = _contexts;
    contexts.setContext(
      contexts.createEmptyContext()..authentication = authentication,
    );
    return authentication;
  }

  void _emit(Authentication? authentication) {
    if (!_changes.isClosed) {
      _changes.add(authentication);
    }
  }

  Future<SupabaseAuthenticationToken> _signedIn(SupabaseSession session) async {
    _epoch++;
    _retryDelay = null;
    final authentication = _install(session);
    await _persist(session);
    if (identical(_session, session)) {
      _log.debug('Signed in ${session.user.id}');
      _emit(authentication);
      _schedule();
      eventPublisher?.publishEvent(AuthenticationSuccessEvent(authentication));
    }
    return authentication;
  }

  SupabaseAuthenticationToken _restored(SupabaseSession session) {
    _epoch++;
    _retryDelay = null;
    final authentication = _install(session);
    _log.debug('Restored the session of ${session.user.id}');
    _emit(authentication);
    _schedule();
    eventPublisher?.publishEvent(AuthenticationSuccessEvent(authentication));
    return authentication;
  }

  // New tokens for the same login. The new refresh token replaces the
  // old one, here and in the store, before anybody is told: the old one
  // is spent.
  Future<void> _refreshed(SupabaseSession session) async {
    _retryDelay = null;
    final authentication = _install(session);
    await _persist(session);
    if (identical(_session, session)) {
      _emit(authentication);
      _schedule();
    }
  }

  Future<SupabaseUser> _userChanged(Map<String, Object?> json) async {
    final user = SupabaseUser.fromJson(json);
    if (user == null) {
      throw SupabaseAuthenticationException(
        'Supabase Auth answered without a user',
      );
    }
    final session = _session;
    if (session != null && session.user.id == user.id) {
      await _refreshed(session.withUser(user));
    }
    return user;
  }

  // Nobody is signed in any more, here. With [logout] the listeners of
  // events hear of it; the stream tells in every case.
  Future<void> _signedOut({bool logout = false}) async {
    final authentication = _authentication;
    _epoch++;
    _session = null;
    _authentication = null;
    _retryDelay = null;
    _timer?.cancel();
    _timer = null;
    _contexts.clearContext();
    Object? failure;
    StackTrace? failureTrace;
    try {
      await _inOrder(() async {
        try {
          await secretStore.delete(sessionKey);
        } finally {
          await secretStore.delete(pkceKey);
        }
      });
    } on Object catch (e, trace) {
      failure = e;
      failureTrace = trace;
    }
    // Signed out of the running application whatever the store did: still
    // signed in after a logout would be worse.
    if (authentication != null) {
      _log.debug('Signed out ${authentication.name}');
      _emit(null);
      if (logout) {
        eventPublisher?.publishEvent(LogoutSuccessEvent(authentication));
      }
    }
    if (failure != null) {
      _log.warning(
        'The stored session could not be removed (${failure.runtimeType}); '
        'it may come back at the next start',
      );
      if (logout) {
        Error.throwWithStackTrace(failure, failureTrace!);
      }
    }
  }

  // Refresh.

  // One exchange of the refresh token at a time: every caller waits for
  // the same one. The session after it, or null when nobody is signed in
  // any more.
  Future<SupabaseSession?> _refresh() =>
      _refreshing ??= _exchangeRefreshToken().whenComplete(
        () => _refreshing = null,
      );

  Future<SupabaseSession?> _exchangeRefreshToken() async {
    final session = _session;
    if (session == null) {
      return null;
    }
    final epoch = _epoch;
    final HttpResponse response;
    try {
      response = await http.send(
        SupabaseService.auth,
        HttpMethod.post,
        '/token',
        query: const [MapEntry('grant_type', 'refresh_token')],
        json: {'refresh_token': session.refreshToken},
        bearer: _anonKey,
      );
    } on Object {
      if (epoch != _epoch) {
        return _session;
      }
      rethrow;
    }
    // The answer of a login that is over is nobody's: a login or a logout
    // that came meanwhile wins.
    if (epoch != _epoch) {
      return _session;
    }
    if (response.isSuccess) {
      final next = SupabaseSession.fromResponse(
        _object(response),
        _now(),
        user: session.user,
      );
      if (next == null) {
        throw SupabaseAuthenticationException(
          'Supabase Auth answered a refresh without a session',
          statusCode: response.statusCode.value,
        );
      }
      await _refreshed(next);
      return _session;
    }
    final error = errors.read(
      response,
      secrets: _sent([session.refreshToken], _anonKey),
    );
    if (!_ends(error, _refreshEndingCodes)) {
      throw errors.translate(error);
    }
    _log.debug(
      'The refresh token was refused (${error.code}): signing out '
      '${session.user.id}',
    );
    await _signedOut();
    throw _SessionEnded(
      error.message,
      errorCode: error.code,
      statusCode: error.statusCode,
    );
  }

  // The timer of spring.supabase.auth.auto-refresh: once, shortly before
  // the access token expires; after a failure that kept the session,
  // again after [retryIn].
  void _schedule([Duration? retryIn]) {
    _timer?.cancel();
    _timer = null;
    final session = _session;
    if (session == null || _closed || !_properties.autoRefresh) {
      return;
    }
    var delay = retryIn;
    if (delay == null) {
      final at = session.refreshAt(_properties.refreshMargin);
      if (at == null) {
        return;
      }
      delay = at.difference(_now());
      if (delay < _minRefreshDelay) {
        delay = _minRefreshDelay;
      }
    }
    _timer = _timerFactory(delay, _autoRefresh);
  }

  void _autoRefresh() {
    _timer = null;
    unawaited(() async {
      try {
        await _refresh();
      } on _SessionEnded {
        // Signed out, and the listeners were told.
      } on Object catch (e) {
        final last = _retryDelay;
        final delay = last == null
            ? _firstRetryDelay
            : (last * 2 > _maxRetryDelay ? _maxRetryDelay : last * 2);
        _retryDelay = delay;
        _log.debug(
          'The session could not be refreshed (${e.runtimeType}); next '
          'try in ${delay.inSeconds} s',
        );
        _schedule(delay);
      }
    }());
  }

  // Logout.

  // The other sessions of the user end; this one stays.
  Future<void> _logoutOthers() async {
    final token = await accessToken();
    if (token == null) {
      throw AuthenticationCredentialsNotFoundException('Nobody is signed in');
    }
    await _send(
      HttpMethod.post,
      '/logout',
      query: const [MapEntry('scope', 'others')],
      bearer: token,
    );
  }

  // Tells Auth that [session], already forgotten here, is over. Best
  // effort: nothing it does or fails to do brings the session back.
  Future<void> _revoke(
    SupabaseSession session,
    SupabaseLogoutScope scope,
  ) async {
    try {
      var token = session.accessToken;
      final expiresAt = session.expiresAt;
      if (expiresAt != null && !_now().isBefore(expiresAt)) {
        // An expired access token revokes nothing: the refresh token is
        // exchanged one last time for one that does. Its new refresh
        // token is never kept.
        final response = await http.send(
          SupabaseService.auth,
          HttpMethod.post,
          '/token',
          query: const [MapEntry('grant_type', 'refresh_token')],
          json: {'refresh_token': session.refreshToken},
          bearer: _anonKey,
        );
        final fresh = response.isSuccess
            ? _object(response)['access_token']
            : null;
        if (fresh is! String || fresh.isEmpty) {
          _log.debug(
            'Nothing to revoke at logout: the refresh token is no longer '
            'accepted (${response.statusCode.value})',
          );
          return;
        }
        token = fresh;
      }
      final response = await http.send(
        SupabaseService.auth,
        HttpMethod.post,
        '/logout',
        query: [MapEntry('scope', scope.name)],
        bearer: token,
      );
      if (!response.isSuccess) {
        _log.debug(
          'The session was not revoked at logout '
          '(${response.statusCode.value})',
        );
      }
    } on Object catch (e) {
      _log.debug('The session was not revoked at logout (${e.runtimeType})');
    }
  }
}

// The session ended and the user was signed out here: told apart from an
// answer that only carries one of the codes (a failure of the service).
final class _SessionEnded extends SupabaseSessionExpiredException {
  _SessionEnded(super.message, {super.errorCode, super.statusCode});
}
