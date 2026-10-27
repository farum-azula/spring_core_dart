import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.session');

/// A conversation with one client across requests, like the servlet
/// `HttpSession`: attributes kept on the server, the client holding only
/// a random id in a cookie (`JSESSIONID`).
///
/// ```dart
/// @GetMapping('/cart')
/// List<String> cart(ServerHttpRequest request) =>
///     (request.getSession()!.getAttribute('cart') as List<String>?) ?? [];
/// ```
abstract interface class HttpSession {
  /// The id (random, 256 bits).
  String get id;

  /// When it was created.
  DateTime get creationTime;

  /// When a request last used it.
  DateTime get lastAccessedTime;

  /// How long it lives without requests.
  Duration get maxInactiveInterval;
  set maxInactiveInterval(Duration value);

  /// Whether the client does not know it yet (created by this request).
  bool get isNew;

  /// The attribute [name], or `null`.
  Object? getAttribute(String name);

  /// Sets the attribute [name] (`null` removes it).
  void setAttribute(String name, Object? value);

  /// Removes the attribute [name].
  void removeAttribute(String name);

  /// The names of the attributes.
  Iterable<String> get attributeNames;

  /// Ends the session: its attributes are dropped and its id is never
  /// accepted again.
  void invalidate();

  /// Whether [invalidate] was called (or it expired).
  bool get isInvalidated;
}

/// Keeps sessions, like Spring Session's `SessionRepository`.
abstract interface class HttpSessionRepository {
  /// A new session with a fresh id.
  FutureOr<StoredHttpSession> createSession();

  /// The live session [id], or `null` (unknown, invalidated or expired).
  FutureOr<StoredHttpSession?> findById(String id);

  /// Gives [session] a new id (the old one stops working).
  FutureOr<void> changeSessionId(StoredHttpSession session);

  /// Forgets [id].
  FutureOr<void> deleteById(String id);
}

/// An [HttpSession] as a repository keeps it.
abstract class StoredHttpSession implements HttpSession {
  /// Marks a request's use.
  void touch(DateTime now);

  /// Whether the client does not know it yet.
  @override
  bool isNew = true;

  /// Whether it has not been used for longer than [maxInactiveInterval].
  bool isExpired(DateTime now);
}

/// `server.servlet.session.*`, like Spring Boot's `Session` properties.
///
/// | Property | Default |
/// |---|---|
/// | `server.servlet.session.timeout` | `30m` |
/// | `server.servlet.session.cookie.name` | `JSESSIONID` |
/// | `server.servlet.session.cookie.path` | the context path, or `/` |
/// | `server.servlet.session.cookie.domain` | — |
/// | `server.servlet.session.cookie.http-only` | `true` |
/// | `server.servlet.session.cookie.secure` | — (secure when the request was) |
/// | `server.servlet.session.cookie.same-site` | `lax` |
/// | `server.servlet.session.max-sessions` | `10000` (`-1`: no limit) |
///
/// Spring Boot leaves `same-site` unset and has no session limit (the
/// container's): here the cookie is `SameSite=Lax` and, when the limit is
/// reached, the sessions unused for the longest time are dropped, so
/// clients cannot fill the memory by opening sessions.
final class HttpSessionProperties {
  /// The settings.
  const HttpSessionProperties({
    this.timeout = const Duration(minutes: 30),
    this.cookieName = 'JSESSIONID',
    this.cookiePath,
    this.cookieDomain,
    this.httpOnly = true,
    this.secure,
    this.sameSite = 'Lax',
    this.maxSessions = 10000,
  });

  /// Reads `server.servlet.session.*` from [environment]; the cookie path
  /// defaults to [contextPath].
  factory HttpSessionProperties.of(
    PropertyResolver environment, {
    String contextPath = '',
  }) {
    String? text(String key) {
      final value = environment
          .getProperty('server.servlet.session.$key')
          ?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    bool? flag(String key) => switch (text(key)?.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => null,
    };

    final timeout = text('timeout');
    return HttpSessionProperties(
      timeout: timeout == null
          ? const Duration(minutes: 30)
          : DurationStyle.parse(timeout, unit: ChronoUnit.seconds),
      cookieName: text('cookie.name') ?? 'JSESSIONID',
      cookiePath:
          text('cookie.path') ?? (contextPath.isEmpty ? '/' : contextPath),
      cookieDomain: text('cookie.domain'),
      httpOnly: flag('cookie.http-only') ?? true,
      secure: flag('cookie.secure'),
      sameSite: switch (text('cookie.same-site')?.toLowerCase()) {
        null || 'lax' => 'Lax',
        'strict' => 'Strict',
        'none' => 'None',
        'unset' => null,
        final other => throw ArgumentError(
          'server.servlet.session.cookie.same-site: unknown value $other',
        ),
      },
      maxSessions: int.tryParse(text('max-sessions') ?? '') ?? 10000,
    );
  }

  /// How long a session lives without requests.
  final Duration timeout;

  /// The cookie's name.
  final String cookieName;

  /// The cookie's path (`/` when `null`).
  final String? cookiePath;

  /// The cookie's domain.
  final String? cookieDomain;

  /// Whether scripts cannot read the cookie.
  final bool httpOnly;

  /// Whether the cookie is sent over HTTPS only (`null`: when the request
  /// was secure).
  final bool? secure;

  /// The cookie's `SameSite` (`null`: not sent).
  final String? sameSite;

  /// Sessions kept at most (`-1`: no limit).
  final int maxSessions;
}

final Random _random = Random.secure();

/// A new session id: 256 random bits, base64url.
String newSessionId() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Sessions in memory, like the servlet container's default: lost with the
/// process, not shared between instances.
final class InMemoryHttpSessionRepository implements HttpSessionRepository {
  /// A repository giving sessions [timeout], keeping at most [maxSessions]
  /// (`-1`: no limit; when full, the least recently used is dropped).
  InMemoryHttpSessionRepository({
    this.timeout = const Duration(minutes: 30),
    this.maxSessions = 10000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The default timeout of new sessions.
  final Duration timeout;

  /// The limit.
  final int maxSessions;

  final DateTime Function() _clock;

  // Insertion order is kept least-recently-used first (see _touch).
  final _sessions = <String, _MemorySession>{};

  /// How many sessions are kept.
  int get size => _sessions.length;

  @override
  StoredHttpSession createSession() {
    final now = _clock();
    _purge(now);
    if (maxSessions >= 0 && _sessions.length >= maxSessions) {
      final oldest = _sessions.keys.first;
      _sessions.remove(oldest)?._invalidated = true;
      _log.warning(
        'Session limit $maxSessions reached: dropped the least recently '
        'used session',
      );
    }
    final session = _MemorySession(this, newSessionId(), now, timeout);
    _sessions[session.id] = session;
    return session;
  }

  @override
  StoredHttpSession? findById(String id) {
    final session = _sessions[id];
    if (session == null) {
      return null;
    }
    final now = _clock();
    if (session.isExpired(now)) {
      _sessions.remove(id);
      session._invalidated = true;
      return null;
    }
    // Most recently used last.
    _sessions
      ..remove(id)
      ..[id] = session;
    return session;
  }

  @override
  void changeSessionId(StoredHttpSession session) {
    final memory = session as _MemorySession;
    _sessions.remove(memory.id);
    memory._id = newSessionId();
    _sessions[memory.id] = memory;
  }

  @override
  void deleteById(String id) => _sessions.remove(id)?._invalidated = true;

  // Drops expired sessions (at most every minute).
  DateTime? _lastPurge;
  void _purge(DateTime now) {
    final last = _lastPurge;
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastPurge = now;
    _sessions.removeWhere((_, session) {
      final expired = session.isExpired(now);
      if (expired) {
        session._invalidated = true;
      }
      return expired;
    });
  }
}

final class _MemorySession extends StoredHttpSession {
  _MemorySession(
    this._repository,
    this._id,
    this.creationTime,
    this.maxInactiveInterval,
  ) : lastAccessedTime = creationTime;

  final InMemoryHttpSessionRepository _repository;
  String _id;
  final _attributes = <String, Object?>{};
  bool _invalidated = false;

  @override
  String get id => _id;

  @override
  final DateTime creationTime;

  @override
  DateTime lastAccessedTime;

  @override
  Duration maxInactiveInterval;

  void _check() {
    if (_invalidated) {
      throw StateError('The session has been invalidated');
    }
  }

  @override
  Object? getAttribute(String name) {
    _check();
    return _attributes[name];
  }

  @override
  void setAttribute(String name, Object? value) {
    _check();
    if (value == null) {
      _attributes.remove(name);
    } else {
      _attributes[name] = value;
    }
  }

  @override
  void removeAttribute(String name) {
    _check();
    _attributes.remove(name);
  }

  @override
  Iterable<String> get attributeNames {
    _check();
    return List.unmodifiable(_attributes.keys);
  }

  @override
  void invalidate() {
    _check();
    _attributes.clear();
    _repository.deleteById(_id);
    _invalidated = true;
  }

  @override
  bool get isInvalidated => _invalidated;

  @override
  void touch(DateTime now) {
    lastAccessedTime = now;
  }

  @override
  bool isExpired(DateTime now) =>
      maxInactiveInterval > Duration.zero &&
      now.difference(lastAccessedTime) > maxInactiveInterval;
}

/// Finds and creates the session of a request, like the servlet
/// container's session handling: the id comes from the session cookie, a
/// new or changed id goes out in `Set-Cookie`. The client never chooses an
/// id: an unknown id gets a new session with a new one.
final class HttpSessionManager {
  /// Sessions of [repository] with [properties].
  HttpSessionManager(this.repository, this.properties);

  /// Keeps the sessions.
  final HttpSessionRepository repository;

  /// The cookie and timeout settings.
  final HttpSessionProperties properties;

  static const _attribute = 'spring.web.session';

  /// Makes sessions available to [request] (the [HttpSessionFilter] does
  /// it for every request).
  Future<void> attach(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    final requested = request.cookies[properties.cookieName];
    StoredHttpSession? session;
    if (requested != null && requested.isNotEmpty && requested.length <= 128) {
      session = await repository.findById(requested);
      if (session != null) {
        session
          ..touch(DateTime.now())
          ..isNew = false;
      }
    }
    request.attributes[_attribute] = _RequestSessions(
      this,
      request,
      response,
      requested,
      session,
    );
  }

  static _RequestSessions? _of(ServerHttpRequest request) =>
      request.attributes[_attribute] as _RequestSessions?;

  ResponseCookie _cookie(
    ServerHttpRequest request,
    String value, {
    bool expire = false,
  }) => ResponseCookie(
    properties.cookieName,
    value,
    path: properties.cookiePath ?? '/',
    domain: properties.cookieDomain,
    httpOnly: properties.httpOnly,
    secure: properties.secure ?? request.isSecure,
    sameSite: properties.sameSite,
    maxAge: expire ? Duration.zero : null,
  );
}

final class _RequestSessions {
  _RequestSessions(
    this.manager,
    this.request,
    this.response,
    this.requestedId,
    this.session,
  );

  final HttpSessionManager manager;
  final ServerHttpRequest request;
  final ServerHttpResponse response;
  final String? requestedId;
  StoredHttpSession? session;

  StoredHttpSession? current() {
    final existing = session;
    return existing != null && !existing.isInvalidated ? existing : null;
  }

  // Synchronous with a synchronous repository (the in-memory one).
  FutureOr<HttpSession> create() {
    final created = manager.repository.createSession();
    return created is StoredHttpSession
        ? _started(created)
        : created.then(_started);
  }

  HttpSession _started(StoredHttpSession created) {
    created.maxInactiveInterval = manager.properties.timeout;
    session = created;
    _sendCookie(created.id);
    return created;
  }

  Future<String> changeId(StoredHttpSession current) async {
    await manager.repository.changeSessionId(current);
    _sendCookie(current.id);
    return current.id;
  }

  void _sendCookie(String id) {
    if (response.isCommitted) {
      _log.warning('Cannot send the session cookie: the response is committed');
      return;
    }
    response.addCookie(manager._cookie(request, id));
  }
}

/// Sessions of a request (with the session filter of the web starter).
extension ServerHttpRequestSession on ServerHttpRequest {
  /// The request's session: the existing one, else (when [create]) a new
  /// one, sending its cookie; `null` without one when [create] is false.
  ///
  /// Use [getSessionAsync] with a repository that is not in memory.
  HttpSession? getSession({bool create = true}) {
    final sessions = HttpSessionManager._of(this);
    if (sessions == null) {
      throw StateError(
        "No sessions for this request: the web starter's HttpSessionFilter "
        'did not run (spring.web.session.enabled=false?)',
      );
    }
    final current = sessions.current();
    if (current != null || !create) {
      return current;
    }
    final created = sessions.create();
    if (created is HttpSession) {
      return created;
    }
    created.ignore();
    throw StateError(
      'The session repository is asynchronous: use getSessionAsync',
    );
  }

  /// Like [getSession], for any repository.
  Future<HttpSession?> getSessionAsync({bool create = true}) async {
    final sessions = HttpSessionManager._of(this);
    if (sessions == null) {
      throw StateError('No sessions for this request');
    }
    return sessions.current() ?? (create ? await sessions.create() : null);
  }

  /// Gives the current session a new id (after a login: the old id, which
  /// someone else may have planted, stops working) and sends it; the new id.
  Future<String> changeSessionId() async {
    final sessions = HttpSessionManager._of(this);
    final current = sessions?.current();
    if (sessions == null || current == null) {
      throw StateError('The request has no session');
    }
    return await sessions.changeId(current);
  }

  /// The session id the client sent (valid or not).
  String? get requestedSessionId => HttpSessionManager._of(this)?.requestedId;

  /// Whether the client's session id names a live session.
  bool get isRequestedSessionIdValid {
    final sessions = HttpSessionManager._of(this);
    final current = sessions?.current();
    return current != null && current.id == sessions!.requestedId;
  }
}

/// Makes the session of the request available (`request.getSession()`),
/// before every other filter (Spring Security's included).
final class HttpSessionFilter implements WebFilter, Ordered {
  /// A filter attaching sessions of [manager].
  HttpSessionFilter(this.manager);

  /// Before the security filter chain (`-100`).
  static const filterOrder = -1000;

  @override
  int get order => filterOrder;

  /// The sessions.
  final HttpSessionManager manager;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    await manager.attach(request, response);
    await chain.doFilter(request, response);
  }
}
