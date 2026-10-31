import 'dart:async';

import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show OAuth2AuthenticationToken;
import 'package:spring_boot_starter_security/src/web/authentication.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

/// One live session of a user, as the [SessionRegistry] knows it.
///
/// Spring (Java): `SessionInformation`.
final class SessionInformation {
  /// The session [sessionId] of the user [principal], last used at
  /// [lastRequest].
  const SessionInformation(this.principal, this.sessionId, this.lastRequest);

  /// The user, as [SessionRegistry.principalKey] names it.
  final String principal;

  /// The session's id.
  final String sessionId;

  /// When a request last used the session.
  final DateTime lastRequest;
}

/// Knows the sessions each user holds, so that a login can be limited to
/// a number of sessions per user
/// ([ConcurrentSessionControlAuthenticationStrategy]).
///
/// Spring (Java): `SessionRegistry`.
abstract interface class SessionRegistry {
  /// The live sessions of [principal], least recently used first.
  FutureOr<List<SessionInformation>> getAllSessions(Authentication principal);

  /// Records that the session [sessionId] holds the login of [principal].
  FutureOr<void> registerNewSession(String sessionId, Authentication principal);

  /// Ends the session [sessionId]: the next request with its cookie is
  /// not logged in.
  FutureOr<void> expireSession(String sessionId);

  /// The name a user is counted under: the login's name with where it
  /// came from, so the application's own `ada` and an identity
  /// provider's `ada` are two users.
  static String principalKey(Authentication authentication) =>
      switch (authentication) {
        OAuth2AuthenticationToken(:final authorizedClientRegistrationId) =>
          'oauth2/$authorizedClientRegistrationId\u0000${authentication.name}',
        _ => 'local\u0000${authentication.name}',
      };
}

/// The [SessionRegistry] over the application's [HttpSessionRepository].
///
/// It keeps only the session ids of each user. Whether a session still
/// lives (not logged out, not expired) and when it was last used are
/// asked of the repository, so the registry never holds a session the
/// repository dropped; ids of sessions that are gone are forgotten when
/// their user logs in again, and all of them once a minute. Ending a
/// session removes it from the repository.
///
/// Spring (Java): `SessionRegistryImpl` (which learns of ended sessions
/// from `HttpSessionEventPublisher`, and marks a session expired for
/// `ConcurrentSessionFilter` instead of removing it).
final class SessionRegistryImpl implements SessionRegistry {
  /// A registry of the sessions of [repository]; [clock] gives the
  /// current time.
  SessionRegistryImpl(this.repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The registry shared by every chain over [repository].
  factory SessionRegistryImpl.of(HttpSessionRepository repository) =>
      _shared[repository] ??= SessionRegistryImpl(repository);

  static final _shared = Expando<SessionRegistryImpl>();

  /// Where the sessions are.
  final HttpSessionRepository repository;

  final DateTime Function() _clock;
  final _byPrincipal = <String, Set<String>>{};
  final _principalOf = <String, String>{};
  DateTime? _lastPurge;

  @override
  Future<List<SessionInformation>> getAllSessions(
    Authentication principal,
  ) async {
    final key = SessionRegistry.principalKey(principal);
    final live = <SessionInformation>[];
    for (final id in [...?_byPrincipal[key]]) {
      final session = await repository.findById(id);
      if (session == null) {
        _remove(id);
      } else {
        live.add(SessionInformation(key, id, session.lastAccessedTime));
      }
    }
    return live..sort((a, b) => a.lastRequest.compareTo(b.lastRequest));
  }

  @override
  Future<void> registerNewSession(
    String sessionId,
    Authentication principal,
  ) async {
    await _purge();
    _remove(sessionId);
    final key = SessionRegistry.principalKey(principal);
    (_byPrincipal[key] ??= {}).add(sessionId);
    _principalOf[sessionId] = key;
  }

  @override
  Future<void> expireSession(String sessionId) async {
    _remove(sessionId);
    await repository.deleteById(sessionId);
  }

  void _remove(String sessionId) {
    final key = _principalOf.remove(sessionId);
    if (key == null) {
      return;
    }
    final ids = _byPrincipal[key]!..remove(sessionId);
    if (ids.isEmpty) {
      _byPrincipal.remove(key);
    }
  }

  // Forgets every id whose session is gone, once a minute at most.
  Future<void> _purge() async {
    final now = _clock();
    final last = _lastPurge;
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastPurge = now;
    for (final id in [..._principalOf.keys]) {
      if (await repository.findById(id) == null) {
        _remove(id);
      }
    }
  }
}

/// A login was refused by the session rules: the user already holds the
/// most sessions allowed and `maxSessionsPreventsLogin` is set.
///
/// Spring (Java): `SessionAuthenticationException`.
class SessionAuthenticationException extends AuthenticationException {
  /// A refused login, described by [message].
  SessionAuthenticationException(super.message);
}

/// Limits each user to [maximumSessions] sessions at login: the least
/// recently used sessions of the user are ended to make room, or, with
/// [exceptionIfMaximumExceeded], the new login is refused
/// ([SessionAuthenticationException], the login's failure handler
/// answers it).
///
/// With it, one account cannot fill the session store by logging in
/// again and again. A login in a browser whose session is already one of
/// the user's takes no new place.
///
/// Spring (Java): `ConcurrentSessionControlAuthenticationStrategy`.
final class ConcurrentSessionControlAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// A strategy allowing [maximumSessions] sessions per user (`-1`: no
  /// limit) in [sessionRegistry].
  const ConcurrentSessionControlAuthenticationStrategy(
    this.sessionRegistry, {
    this.maximumSessions = 1,
    this.exceptionIfMaximumExceeded = false,
  });

  /// Where the sessions of each user are.
  final SessionRegistry sessionRegistry;

  /// The most sessions per user; `-1` for no limit.
  final int maximumSessions;

  /// Whether a login above the limit is refused, instead of ending the
  /// user's least recently used session.
  final bool exceptionIfMaximumExceeded;

  @override
  Future<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    if (maximumSessions < 0) {
      return;
    }
    final current = (await request.getSessionAsync(create: false))?.id;
    final others = [
      for (final session in await sessionRegistry.getAllSessions(
        authentication,
      ))
        if (session.sessionId != current) session,
    ];
    final excess = others.length - maximumSessions + 1;
    if (excess <= 0) {
      return;
    }
    if (exceptionIfMaximumExceeded) {
      throw SessionAuthenticationException(
        'Maximum sessions of $maximumSessions for this principal exceeded',
      );
    }
    for (final session in others.take(excess)) {
      await sessionRegistry.expireSession(session.sessionId);
    }
  }
}

/// Records the session of a successful login in the [sessionRegistry],
/// creating the session (the login is when a session is made). It runs
/// after the session got its new id.
///
/// Spring (Java): `RegisterSessionAuthenticationStrategy`.
final class RegisterSessionAuthenticationStrategy
    implements SessionAuthenticationStrategy {
  /// A strategy recording sessions in [sessionRegistry].
  const RegisterSessionAuthenticationStrategy(this.sessionRegistry);

  /// Where the sessions of each user are.
  final SessionRegistry sessionRegistry;

  @override
  Future<void> onAuthentication(
    Authentication authentication,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final session = (await request.getSessionAsync())!;
    await sessionRegistry.registerNewSession(session.id, authentication);
  }
}
