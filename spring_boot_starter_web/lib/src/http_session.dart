import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/dispatcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _log = SpringLog('spring.web.session');

/// Data the server keeps for one client across several requests, such as
/// a shopping cart or the logged-in user.
///
/// HTTP forgets everything between requests. A session remembers: its
/// attributes stay on the server, and the client holds only a random id
/// in a cookie (`JSESSIONID` by default) that it sends back with each
/// request. Get it with `request.getSession()`, which creates the session
/// (and sends the cookie) on first use; `getSession(create: false)` only
/// looks. A session ends when it is [invalidate]d or after
/// [maxInactiveInterval] without requests.
///
/// APIs called by programs usually carry a token instead and need no
/// session; sessions suit browsers, and the security starter keeps the
/// logged-in user in one.
///
/// ```dart
/// // Each visitor has a cart that lives as long as the session.
/// @PostMapping('/cart')
/// void add(ServerHttpRequest request, @RequestParam() String item) {
///   final session = request.getSession()!;
///   final cart = session.getAttribute('cart') as List<String>? ?? [];
///   session.setAttribute('cart', [...cart, item]);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping("/cart")
/// void add(HttpSession session, @RequestParam String item) {
///   List<String> cart = (List<String>) session.getAttribute("cart");
///   ...
///   session.setAttribute("cart", cart);
/// }
/// ```
abstract interface class HttpSession {
  /// The session id the cookie carries: 256 random bits, base64url
  /// encoded. It changes with `request.changeSessionId()`.
  String get id;

  /// When the session was created.
  DateTime get creationTime;

  /// When a request last came with this session; the inactivity timeout
  /// counts from here.
  DateTime get lastAccessedTime;

  /// How long the session lives without a request
  /// (`server.servlet.session.timeout`, 30 minutes by default). Set it
  /// to change the timeout of this session only; zero or negative means
  /// it never expires.
  Duration get maxInactiveInterval;
  set maxInactiveInterval(Duration value);

  /// Whether this request created the session, so the client does not
  /// know it yet.
  bool get isNew;

  /// The value stored under [name], or `null` when there is none. Throws
  /// a [StateError] once the session is invalidated.
  Object? getAttribute(String name);

  /// Stores [value] under [name]; `null` removes it. Values stay in the
  /// repository as they are (in memory by default, not copied). Throws a
  /// [StateError] once the session is invalidated.
  void setAttribute(String name, Object? value);

  /// Removes the value stored under [name], if any.
  void removeAttribute(String name);

  /// The names of the stored values (a copy).
  Iterable<String> get attributeNames;

  /// Ends the session, as a logout does: its values are dropped and its
  /// id is never accepted again. Using the session afterwards throws a
  /// [StateError]. The cookie stays in the browser; its next request just
  /// has no session.
  void invalidate();

  /// Whether the session has ended: invalidated or expired.
  bool get isInvalidated;
}

/// Where the sessions live.
///
/// The starter keeps sessions in memory ([InMemoryHttpSessionRepository]):
/// they are lost when the process stops and not shared between several
/// instances of the application. Declare a bean of this type to keep them
/// elsewhere, for example in a database or Redis, so they survive a
/// restart or are shared behind a load balancer; the in-memory one then
/// backs off. Methods may return a `Future`, but with an asynchronous
/// repository, code must use `request.getSessionAsync()`.
///
/// ```dart
/// // Sessions in the application's database, shared by every instance;
/// // DatabaseSessions is the application's own implementation.
/// @Bean()
/// HttpSessionRepository httpSessionRepository(Database database) =>
///     DatabaseSessions(database);
/// ```
///
/// Spring (Java), with Spring Session:
/// ```java
/// @Bean
/// SessionRepository<?> sessionRepository(JdbcOperations jdbc,
///     TransactionOperations transactions) {
///   return new JdbcIndexedSessionRepository(jdbc, transactions);
/// }
/// ```
abstract interface class HttpSessionRepository {
  /// A new, empty session with a fresh random id. The starter then sets
  /// its timeout from `server.servlet.session.timeout`.
  FutureOr<StoredHttpSession> createSession();

  /// The live session with [id], or `null` when it is unknown,
  /// invalidated or expired. Called once per request that carries the
  /// session cookie.
  FutureOr<StoredHttpSession?> findById(String id);

  /// Gives [session] a new id and forgets the old one, keeping the
  /// session's values.
  FutureOr<void> changeSessionId(StoredHttpSession session);

  /// Removes the session with [id], so that id is no longer found.
  FutureOr<void> deleteById(String id);
}

/// An [HttpSession] with the extra state a repository needs to keep it.
///
/// Extend it when you write an [HttpSessionRepository]: the starter
/// marks the session's use with [touch] and the repository decides with
/// [isExpired] when it is gone.
abstract class StoredHttpSession implements HttpSession {
  /// Records that a request used the session at [now]; it updates
  /// [lastAccessedTime].
  void touch(DateTime now);

  /// Whether this request created the session; `true` until a later
  /// request finds it again by its id.
  @override
  bool isNew = true;

  /// Whether the session, at [now], has gone unused for longer than
  /// [maxInactiveInterval].
  bool isExpired(DateTime now);
}

/// The session settings: how long a session lives, how many are kept, and
/// how the session cookie is written.
///
/// Applications set the `server.servlet.session.*` properties; the
/// starter reads them with [HttpSessionProperties.of].
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
/// A timeout without a unit is in seconds (`1800`), as in Spring Boot;
/// `same-site` takes `lax`, `strict`, `none` or `unset` (no `SameSite`
/// attribute).
///
/// ```properties
/// # Sessions end after 15 minutes without a request.
/// server.servlet.session.timeout=15m
/// server.servlet.session.cookie.name=SHOPSESSION
/// ```
///
/// Spring Boot leaves `same-site` unset and has no session limit (the
/// container has its own: Tomcat refuses new sessions above
/// `maxActiveSessions`, unlimited by default): here the cookie is
/// `SameSite=Lax` and the number of sessions is limited, so clients
/// cannot fill the memory by opening sessions. What happens at the limit:
/// [InMemoryHttpSessionRepository].
final class HttpSessionProperties {
  /// Settings with the defaults of the table above; a `null` [cookiePath]
  /// means `/`.
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

  /// Reads `server.servlet.session.*` from [environment]. The cookie path
  /// defaults to [contextPath] (`server.servlet.context-path`), else `/`.
  /// Throws an [ArgumentError] for an unknown `same-site` value; an
  /// unreadable `max-sessions` keeps the default.
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

  /// How long a session lives without a request; 30 minutes by default.
  final Duration timeout;

  /// The name of the cookie that carries the session id; `JSESSIONID` by
  /// default.
  final String cookieName;

  /// The `Path` of the cookie, the paths the browser sends it to; `/`
  /// when `null`.
  final String? cookiePath;

  /// The `Domain` of the cookie; `null` sends none, so the cookie goes
  /// back only to the host that set it.
  final String? cookieDomain;

  /// Whether the cookie is `HttpOnly`, hidden from the page's scripts;
  /// `true` by default.
  final bool httpOnly;

  /// Whether the cookie is `Secure`, sent back over HTTPS only. `null`
  /// (the default) decides per request: secure when the request came
  /// over HTTPS.
  final bool? secure;

  /// The `SameSite` attribute of the cookie (`Lax`, `Strict` or `None`);
  /// `Lax` by default, `null` sends none.
  final String? sameSite;

  /// How many sessions are kept at most; 10000 by default, `-1` for no
  /// limit. Above it, a new session pushes out one that holds no login,
  /// else a login of the user who holds the most sessions, or is refused
  /// (see [InMemoryHttpSessionRepository]).
  final int maxSessions;
}

final Random _random = Random.secure();

/// A new session id: 256 bits from a secure random generator, base64url
/// encoded without padding (43 characters), too many to guess. For
/// writers of an [HttpSessionRepository].
String newSessionId() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The default [HttpSessionRepository]: sessions in the memory of the
/// process.
///
/// It needs no setup, which fits one instance of an application. Its
/// sessions are lost when the process stops and are not shared between
/// instances; declare another repository bean when that matters. Expired
/// sessions are removed when found, and all of them at most once a
/// minute when a session is created.
///
/// At most [maxSessions] sessions are kept (`-1`: no limit). When the
/// limit is reached, creating a session first removes every expired
/// session; if the store is still full, the new session is refused with a
/// [TooManyActiveSessionsException] (a 503) and a warning is logged, at
/// most once a minute. A live session is never removed to make room. The
/// security starter creates a session only at a login, so anonymous
/// requests cannot fill the store; raise the limit when logged-in users
/// alone fill it.
///
/// ```dart
/// // A test that controls time, to check that sessions expire.
/// var now = DateTime(2026);
/// final repository = InMemoryHttpSessionRepository(
///   timeout: const Duration(minutes: 5),
///   clock: () => now,
/// );
/// final session = repository.createSession();
/// now = now.add(const Duration(minutes: 6));
/// assert(repository.findById(session.id) == null);
/// ```
///
/// Spring (Java): WebFlux's `InMemoryWebSessionStore` (`maxSessions`,
/// expired ones removed, then refused).
final class InMemoryHttpSessionRepository implements HttpSessionRepository {
  /// A repository whose new sessions time out after [timeout], keeping at
  /// most [maxSessions] (`-1`: no limit). [clock] gives the current time;
  /// tests replace it.
  InMemoryHttpSessionRepository({
    this.timeout = const Duration(minutes: 30),
    this.maxSessions = 10000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The inactivity timeout of new sessions; 30 minutes by default.
  final Duration timeout;

  /// How many sessions are kept at most; `-1` for no limit.
  final int maxSessions;

  final DateTime Function() _clock;

  final _sessions = <String, _MemorySession>{};

  /// How many sessions are kept, including expired ones not yet removed.
  int get size => _sessions.length;

  @override
  StoredHttpSession createSession() {
    final now = _clock();
    _purge(now);
    if (maxSessions >= 0 && _sessions.length >= maxSessions) {
      _dropExpired(now);
      if (_sessions.length >= maxSessions) {
        _warn(
          now,
          'Session limit $maxSessions reached: refused a new session '
          '(raise server.servlet.session.max-sessions)',
        );
        throw TooManyActiveSessionsException(maxSessions);
      }
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
    if (session.isExpired(_clock())) {
      _drop(session);
      return null;
    }
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
  void deleteById(String id) {
    final session = _sessions[id];
    if (session != null) {
      _drop(session);
    }
  }

  DateTime? _lastWarning;
  void _warn(DateTime now, String message) {
    final last = _lastWarning;
    if (last == null || now.difference(last) >= const Duration(minutes: 1)) {
      _lastWarning = now;
      _log.warning(message);
    }
  }

  void _drop(_MemorySession session) {
    if (identical(_sessions[session.id], session)) {
      _sessions.remove(session.id);
    }
    session._invalidated = true;
  }

  void _dropExpired(DateTime now) {
    [
      for (final session in _sessions.values)
        if (session.isExpired(now)) session,
    ].forEach(_drop);
  }

  // Drops expired sessions (at most every minute).
  DateTime? _lastPurge;
  void _purge(DateTime now) {
    final last = _lastPurge;
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _lastPurge = now;
    _dropExpired(now);
  }
}

/// Thrown when a new session is refused: the session limit
/// (`server.servlet.session.max-sessions`) is reached and no session
/// kept has expired (see [InMemoryHttpSessionRepository]).
///
/// The request gets a 503 Service Unavailable. Raise the limit when
/// logged-in users alone fill it.
///
/// Tomcat (Java): `TooManyActiveSessionsException`, thrown above the
/// `maxActiveSessions` of its session manager.
final class TooManyActiveSessionsException extends ResponseStatusException {
  /// The refusal of a new session above [maxActiveSessions].
  TooManyActiveSessionsException(this.maxActiveSessions)
    : super(HttpStatus.serviceUnavailable, 'Too many active sessions');

  /// The session limit that was reached.
  final int maxActiveSessions;
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

/// Connects requests to their sessions through the session cookie.
///
/// For each request it reads the id from the cookie and looks the session
/// up in the repository; when the request creates a session or changes
/// its id, it sends the new id in a `Set-Cookie` header. The client never
/// chooses an id: an unknown id is ignored, and a session created later
/// gets a new random one, so an attacker cannot plant an id in a victim's
/// browser (session fixation). Ids longer than 128 characters are
/// ignored without a lookup.
///
/// The starter declares it as the `httpSessionManager` bean and the
/// [HttpSessionFilter] calls it; applications use `request.getSession()`.
final class HttpSessionManager {
  /// A manager of the sessions in [repository], with the cookie and
  /// timeout of [properties].
  HttpSessionManager(this.repository, this.properties);

  /// Where the sessions are kept.
  final HttpSessionRepository repository;

  /// The cookie and timeout settings.
  final HttpSessionProperties properties;

  static const _attribute = 'spring.web.session';

  /// Finds the session named by the cookie of [request], marks it used,
  /// and makes `request.getSession()` work for this request; [response]
  /// receives the cookie of a session created later. The
  /// [HttpSessionFilter] calls it for every request.
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

/// The session methods of a request: `request.getSession()` and friends.
///
/// They work in any code that has the request, once the starter's
/// [HttpSessionFilter] has run (it runs before every other filter).
/// Called on a request that did not pass the filter, they throw a
/// [StateError].
///
/// ```dart
/// // After a successful login: a new id, so an id seen before the login
/// // is worthless, then the user goes into the session.
/// await request.changeSessionId();
/// request.getSession()!.setAttribute('user', user.name);
/// ```
extension ServerHttpRequestSession on ServerHttpRequest {
  /// The request's session. Without one, [create] (the default) makes a
  /// new session and sends its cookie with the response; with `create:
  /// false` the result is `null` instead, which is how code checks for a
  /// session without starting one.
  ///
  /// Works only with a repository that answers at once, as the in-memory
  /// one does; otherwise creating a session throws a [StateError]: use
  /// [getSessionAsync] then.
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

  /// The request's session, as [getSession] gives it, for any repository,
  /// including those that answer with a `Future`.
  Future<HttpSession?> getSessionAsync({bool create = true}) async {
    final sessions = HttpSessionManager._of(this);
    if (sessions == null) {
      throw StateError('No sessions for this request');
    }
    return sessions.current() ?? (create ? await sessions.create() : null);
  }

  /// Gives the current session a new id, keeping its values, and sends the
  /// new id in the cookie; returns the new id. Call it after a login: the
  /// old id, which someone else may know, stops working. Throws a
  /// [StateError] when the request has no session.
  Future<String> changeSessionId() async {
    final sessions = HttpSessionManager._of(this);
    final current = sessions?.current();
    if (sessions == null || current == null) {
      throw StateError('The request has no session');
    }
    return await sessions.changeId(current);
  }

  /// The session id the client sent in its cookie, whether or not it
  /// names a live session; `null` without a cookie.
  String? get requestedSessionId => HttpSessionManager._of(this)?.requestedId;

  /// Whether the id the client sent names the session this request uses:
  /// `false` when the session is unknown, expired, invalidated, or got a
  /// new id during this request.
  bool get isRequestedSessionIdValid {
    final sessions = HttpSessionManager._of(this);
    final current = sessions?.current();
    return current != null && current.id == sessions!.requestedId;
  }
}

/// The filter that makes `request.getSession()` work: it looks up the
/// session of each request before the other filters run.
///
/// The starter declares it as the `httpSessionFilter` bean, at order
/// [filterOrder], so the session is known to every later filter,
/// the security filter chain included. Applications do not use it
/// directly.
final class HttpSessionFilter implements WebFilter, Ordered {
  /// A filter that looks up sessions through [manager].
  HttpSessionFilter(this.manager);

  /// The filter's order, `-1000`: before the security filter chain
  /// (`-100`).
  static const filterOrder = -1000;

  @override
  int get order => filterOrder;

  /// Finds the session of each request.
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
