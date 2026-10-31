import 'dart:async';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/firewall.dart';
import 'package:spring_boot_starter_security/src/web/log_support.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web');
const _chainLog = SpringLog('spring.security.web.DefaultSecurityFilterChain');
const _proxyLog = SpringLog('spring.security.web.FilterChainProxy');
const _contextLog = SpringLog(
  'spring.security.web.context.HttpSessionSecurityContextRepository',
);

/// One security setup for a group of requests: which requests it covers,
/// and the filters (login, CSRF, access rules, ...) that run on them.
///
/// This is the type of the bean an application declares to configure web
/// security. It is built with `HttpSecurity`, never by hand. Without such
/// a bean the starter declares a default one: every request needs a
/// login. Several beans make several chains, for example one for `/api/**`
/// with tokens and one for the pages with form login; the first that
/// matches a request handles it.
///
/// ```dart
/// @Configuration()
/// class SecurityConfig {
///   @Bean()
///   SecurityFilterChain filterChain(HttpSecurity http) => http
///       .authorizeHttpRequests((auth) => auth
///           .requestMatchers('/public/**').permitAll()
///           .anyRequest().authenticated())
///       .formLogin()
///       .build();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
///   return http
///       .authorizeHttpRequests(auth -> auth
///           .requestMatchers("/public/**").permitAll()
///           .anyRequest().authenticated())
///       .formLogin(Customizer.withDefaults())
///       .build();
/// }
/// ```
abstract interface class SecurityFilterChain {
  /// Whether this chain handles [request]; checked in bean order, the
  /// first chain that matches wins.
  bool matches(ServerHttpRequest request);

  /// The filters run on a matching request, in order.
  List<WebFilter> get filters;
}

/// The [SecurityFilterChain] that `HttpSecurity.build` returns: a request
/// matcher and a fixed list of filters.
///
/// Build one by hand only for a chain `HttpSecurity` cannot describe.
///
/// Spring (Java): `DefaultSecurityFilterChain`.
final class DefaultSecurityFilterChain implements SecurityFilterChain {
  /// A chain running [filters] (copied, cannot be modified) on the
  /// requests [requestMatcher] matches.
  DefaultSecurityFilterChain(this.requestMatcher, List<WebFilter> filters)
    : filters = List.unmodifiable(filters) {
    _chainLog.debug(
      () =>
          'Will secure $requestMatcher with filters: '
          '${this.filters.map((f) => f.runtimeType).join(', ')}',
    );
  }

  /// Decides which requests this chain handles.
  final RequestMatcher requestMatcher;

  @override
  final List<WebFilter> filters;

  @override
  bool matches(ServerHttpRequest request) => requestMatcher.matches(request);

  @override
  String toString() =>
      'DefaultSecurityFilterChain [RequestMatcher=$requestMatcher, '
      'Filters=${[for (final f in filters) f.runtimeType]}]';
}

/// Writes the answer to a request the [HttpFirewall] refused.
///
/// The default, [HttpStatusRequestRejectedHandler], answers 400 with no
/// body. Implement it to answer differently, for example to log the
/// refused requests in a monitoring system.
///
/// Spring (Java): `RequestRejectedHandler`.
abstract interface class RequestRejectedHandler {
  /// Answers [request], which the firewall refused for the reason in
  /// [exception]; no rule or controller has seen it.
  FutureOr<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    RequestRejectedException exception,
  );
}

/// The default [RequestRejectedHandler]: an empty `400 Bad Request` with
/// `X-Frame-Options: DENY` and `X-Content-Type-Options: nosniff`.
///
/// Spring (Java): `HttpStatusRequestRejectedHandler`.
final class HttpStatusRequestRejectedHandler implements RequestRejectedHandler {
  /// The stateless handler.
  const HttpStatusRequestRejectedHandler();

  @override
  Future<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    RequestRejectedException exception,
  ) async {
    if (response.isCommitted) {
      return;
    }
    response
      ..statusCode = HttpStatus.badRequest
      // The same as the chain's headers (dart:io's default is SAMEORIGIN).
      ..headers.set('X-Frame-Options', 'DENY')
      ..headers.set('X-Content-Type-Options', 'nosniff');
    await response.close();
  }
}

/// The one web filter through which security enters the web starter: it
/// sends each request through the right [SecurityFilterChain].
///
/// The auto-configuration registers it with all `SecurityFilterChain`
/// beans; applications do not create it. For each request, once:
///
/// 1. It checks the request with the [firewall]. A refused request gets
///    the [requestRejectedHandler]'s answer (400) and goes no further.
/// 2. It picks the first of the [chains] that matches.
/// 3. It runs that chain's filters, then the rest of the web filters and
///    the controller, in a security context scope of their own: the user
///    of one request is never seen by another, and the scope ends with the
///    request.
///
/// A request no chain matches goes on without any security filter, as in
/// Spring; the starter's default chain, and any `HttpSecurity` without
/// `securityMatcher`, matches every request.
///
/// An `AuthenticationException` or `AccessDeniedException` that no chain
/// answered (for example a request outside every chain calling a method
/// with `@PreAuthorize`) is answered here: `401` or `403` with a generic
/// `ProblemDetail`, never the exception's message.
///
/// Spring (Java): `FilterChainProxy`.
final class FilterChainProxy implements WebFilter, Ordered {
  /// A filter over [chains], tried in order, placed at [order] among the
  /// web filters; [firewall] defaults to a [StrictHttpFirewall].
  FilterChainProxy(
    List<SecurityFilterChain> chains, {
    HttpFirewall? firewall,
    this.requestRejectedHandler = const HttpStatusRequestRejectedHandler(),
    this.order = defaultFilterOrder,
  }) : chains = List.unmodifiable(chains),
       firewall = firewall ?? StrictHttpFirewall();

  /// `-100`, Spring Boot's `SecurityProperties.DEFAULT_FILTER_ORDER`: early
  /// among the web filters, so most of them run for authorized requests
  /// only.
  static const defaultFilterOrder = -100;

  @override
  final int order;

  /// The chains, in the order they are tried; cannot be modified.
  final List<SecurityFilterChain> chains;

  /// Refuses requests whose path could be read two ways, before any chain
  /// is chosen.
  final HttpFirewall firewall;

  /// Writes the answer to a request the [firewall] refused.
  final RequestRejectedHandler requestRejectedHandler;

  static const _applied = 'spring.security.filterChainProxy.applied';

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (request.attributes.containsKey(_applied)) {
      return await chain.doFilter(request, response);
    }
    request.attributes[_applied] = true;
    try {
      firewall.check(request);
    } on RequestRejectedException catch (e) {
      _proxyLog.debug(
        () => 'Rejecting request ${request.method.value}: ${logText(e.reason)}',
      );
      await requestRejectedHandler.handle(request, response, e);
      return;
    }
    final selected = chains.where((c) => c.matches(request)).firstOrNull;
    await SecurityContextHolder.runWithContext(() async {
      try {
        if (selected == null || selected.filters.isEmpty) {
          _proxyLog.trace(() => 'No security for ${requestLine(request)}');
          return await chain.doFilter(request, response);
        }
        _proxyLog.debug(() => 'Securing ${requestLine(request)}');
        return await _VirtualChain(
          selected.filters,
          chain,
          request,
        ).doFilter(request, response);
      } on AuthenticationException catch (e) {
        _proxyLog.debug(
          () => 'Unauthenticated ${requestLine(request)}: ${logText(e)}',
        );
        await writeSecurityProblem(
          request,
          response,
          HttpStatus.unauthorized,
          'Full authentication is required to access this resource',
        );
      } on AccessDeniedException catch (e) {
        _proxyLog.debug(() => 'Denied ${requestLine(request)}: ${logText(e)}');
        await writeSecurityProblem(
          request,
          response,
          HttpStatus.forbidden,
          'Access Denied',
        );
      } on PasswordChecksBusyException catch (e) {
        // The credentials were not checked: no failed login, no event; the
        // client may try again in a moment.
        _warnBusy(e);
        response.headers.set('Retry-After', '1');
        await writeSecurityProblem(
          request,
          response,
          HttpStatus.serviceUnavailable,
          'Too many logins at once, try again in a moment',
        );
      }
    });
  }
}

DateTime? _lastBusyWarning;

// At most once a minute: a flood would fill the log otherwise.
void _warnBusy(PasswordChecksBusyException e) {
  final now = DateTime.now();
  final last = _lastBusyWarning;
  if (last != null && now.difference(last) < const Duration(minutes: 1)) {
    return;
  }
  _lastBusyWarning = now;
  _log.warning(
    'Logins refused with 503: ${e.maxConcurrent} password checks running '
    'and ${e.maxQueued} waiting (a flood of logins? limit them in front)',
  );
}

final class _VirtualChain implements WebFilterChain {
  _VirtualChain(this.filters, this.original, this.logged, [this.index = 0]);

  final List<WebFilter> filters;
  final WebFilterChain original;
  final ServerHttpRequest logged;
  final int index;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    if (index == filters.length) {
      _proxyLog.debug(() => 'Secured ${requestLine(logged)}');
      return original.doFilter(request, response);
    }
    _proxyLog.trace(
      () =>
          'Invoking ${filters[index].runtimeType} '
          '(${index + 1}/${filters.length})',
    );
    return filters[index].doFilter(
      request,
      response,
      _VirtualChain(filters, original, logged, index + 1),
    );
  }
}

/// Where a logged-in user is kept from one request to the next.
///
/// HTTP forgets everything between requests. After a form login the
/// context is saved in the session, so the next request of the same
/// browser starts logged in. A stateless API keeps nothing: each request
/// carries its credentials. Applications choose a repository through
/// `HttpSecurity.securityContext` or the session creation policy; they
/// implement one only to keep logins somewhere else, such as a signed
/// cookie.
///
/// Spring (Java): `SecurityContextRepository`.
abstract interface class SecurityContextRepository {
  /// The context stored for [request], or `null` when there is none (the
  /// request then starts without a user).
  FutureOr<SecurityContext?> loadContext(ServerHttpRequest request);

  /// Stores [context] so the next requests of the same client find it.
  ///
  /// Login filters call it after a successful login; code that changes
  /// the user itself must call it too, since nothing is saved
  /// automatically.
  FutureOr<void> saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// Whether a context is stored for [request].
  bool containsContext(ServerHttpRequest request);
}

/// The [SecurityContextRepository] of browser logins: the context is kept
/// in the HTTP session, under `SPRING_SECURITY_CONTEXT`.
///
/// A session is created only to store a real (not anonymous) user;
/// saving an empty or anonymous context removes the stored one. Loading
/// gives a copy, so two requests of one session never change each other's
/// context. It is the default, behind the request attribute, unless the
/// session creation policy is `stateless`.
///
/// Only a login creates the session: nothing else of the chain keeps
/// state in it before (the CSRF token, the page to come back to and the
/// OAuth 2.0 authorization request are signed cookies by default), so
/// clients that are not logged in cannot fill the session store. When the
/// store is full, the login is refused with a 503
/// ([TooManyActiveSessionsException]).
///
/// Spring (Java): `HttpSessionSecurityContextRepository`.
final class HttpSessionSecurityContextRepository
    implements SecurityContextRepository {
  /// A repository using [trustResolver] to recognise anonymous users.
  const HttpSessionSecurityContextRepository({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// The session attribute holding the context.
  static const springSecurityContextKey = 'SPRING_SECURITY_CONTEXT';

  /// Tells anonymous users, who are never stored, from real logins.
  final AuthenticationTrustResolver trustResolver;

  @override
  SecurityContext? loadContext(ServerHttpRequest request) {
    final stored = request
        .getSession(create: false)
        ?.getAttribute(springSecurityContextKey);
    if (stored is! SecurityContext) {
      _contextLog.trace(
        'No SecurityContext was available from the HttpSession',
      );
      return null;
    }
    final copy = SecurityContextImpl(stored.authentication);
    _contextLog.trace(
      () =>
          'Retrieved SecurityContextImpl [Authentication='
          '${_describe(copy.authentication)}]',
    );
    return copy;
  }

  @override
  void saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final authentication = context.authentication;
    if (authentication == null || trustResolver.isAnonymous(authentication)) {
      final session = request.getSession(create: false);
      if (session?.getAttribute(springSecurityContextKey) != null) {
        _contextLog.trace('Removed SecurityContext stored in HttpSession');
      } else {
        _contextLog.trace(
          authentication == null
              ? 'Did not store empty SecurityContext'
              : 'Did not store anonymous SecurityContext',
        );
      }
      session?.removeAttribute(springSecurityContextKey);
      return;
    }
    request.getSession()!.setAttribute(
      springSecurityContextKey,
      SecurityContextImpl(authentication),
    );
    _contextLog.trace(
      () =>
          'Stored SecurityContextImpl [Authentication='
          '${describeAuthentication(authentication)}] to HttpSession',
    );
  }

  @override
  bool containsContext(ServerHttpRequest request) =>
      request
          .getSession(create: false)
          ?.getAttribute(springSecurityContextKey) !=
      null;
}

/// A [SecurityContextRepository] that keeps the context for the rest of
/// the current request only, in a request attribute.
///
/// It lets a forward or an error page inside the same request see the
/// user, without any session. It is the whole repository of a `stateless`
/// chain, and the first of the default ones. The test support also puts
/// mock users here.
///
/// Spring (Java): `RequestAttributeSecurityContextRepository`.
final class RequestAttributeSecurityContextRepository
    implements SecurityContextRepository {
  /// The stateless repository.
  const RequestAttributeSecurityContextRepository();

  /// The name of the request attribute holding the context; the test
  /// support puts mock users there.
  static const attributeName =
      'spring.security.RequestAttributeSecurityContextRepository';

  static const String _attribute = attributeName;

  @override
  SecurityContext? loadContext(ServerHttpRequest request) =>
      request.attributes[_attribute] as SecurityContext?;

  @override
  void saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => request.attributes[_attribute] = context;

  @override
  bool containsContext(ServerHttpRequest request) =>
      request.attributes.containsKey(_attribute);
}

/// A [SecurityContextRepository] made of several: it loads from the first
/// one that has a context and saves to all of them.
///
/// Unless the session creation policy is `stateless`, every chain uses one
/// over the request attribute, then the session.
///
/// Spring (Java): `DelegatingSecurityContextRepository`.
final class DelegatingSecurityContextRepository
    implements SecurityContextRepository {
  /// A repository over [repositories], asked in order.
  DelegatingSecurityContextRepository(
    List<SecurityContextRepository> repositories,
  ) : repositories = List.unmodifiable(repositories);

  /// The repositories, in order; cannot be modified.
  final List<SecurityContextRepository> repositories;

  @override
  Future<SecurityContext?> loadContext(ServerHttpRequest request) async {
    for (final repository in repositories) {
      final context = await repository.loadContext(request);
      if (context != null) {
        return context;
      }
    }
    return null;
  }

  @override
  Future<void> saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) async {
    for (final repository in repositories) {
      await repository.saveContext(context, request, response);
    }
  }

  @override
  bool containsContext(ServerHttpRequest request) =>
      repositories.any((r) => r.containsContext(request));
}

/// A [SecurityContextRepository] that keeps nothing, so every request
/// starts without a user, even within one request's forwards.
///
/// For APIs where every request carries its own credentials. A
/// `stateless` chain uses [RequestAttributeSecurityContextRepository]
/// rather than this one.
///
/// Spring (Java): `NullSecurityContextRepository`.
final class NullSecurityContextRepository implements SecurityContextRepository {
  /// The stateless repository.
  const NullSecurityContextRepository();

  @override
  SecurityContext? loadContext(ServerHttpRequest request) => null;

  @override
  void saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {}

  @override
  bool containsContext(ServerHttpRequest request) => false;
}

/// The first filter of every chain: it loads the user stored for the
/// request (in the session, say) and makes it current in the
/// `SecurityContextHolder`.
///
/// The scope of the context comes from [FilterChainProxy] and ends with
/// the request. Changes are not saved automatically: login filters save
/// the new context themselves, as in Spring Security 6 and later.
///
/// Spring (Java): `SecurityContextHolderFilter`.
final class SecurityContextHolderFilter implements WebFilter {
  /// A filter loading the context from [repository].
  const SecurityContextHolderFilter(this.repository);

  /// Where the contexts are kept between requests.
  final SecurityContextRepository repository;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    final context = await repository.loadContext(request);
    if (context != null) {
      SecurityContextHolder.setContext(context);
    }
    await chain.doFilter(request, response);
  }
}

String _describe(Authentication? authentication) =>
    authentication == null ? 'null' : describeAuthentication(authentication);
