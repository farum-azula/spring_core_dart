import 'dart:async';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/firewall.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web');

/// The filters of the requests [matches] accepts, like Spring's
/// `SecurityFilterChain`; built by `HttpSecurity`.
abstract interface class SecurityFilterChain {
  /// Whether this chain handles [request].
  bool matches(ServerHttpRequest request);

  /// The filters, in order.
  List<WebFilter> get filters;
}

/// A [SecurityFilterChain] from a matcher and filters, like Spring's
/// `DefaultSecurityFilterChain`.
final class DefaultSecurityFilterChain implements SecurityFilterChain {
  /// [filters] for requests [requestMatcher] matches.
  DefaultSecurityFilterChain(this.requestMatcher, List<WebFilter> filters)
    : filters = List.unmodifiable(filters);

  /// Which requests.
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

/// Answers a request the firewall refused, like Spring's
/// `RequestRejectedHandler`.
abstract interface class RequestRejectedHandler {
  /// Answers [request], refused with [exception].
  FutureOr<void> handle(
    ServerHttpRequest request,
    ServerHttpResponse response,
    RequestRejectedException exception,
  );
}

/// `400 Bad Request`, like Spring's `HttpStatusRequestRejectedHandler`.
final class HttpStatusRequestRejectedHandler implements RequestRejectedHandler {
  /// The handler.
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

/// The security filter of the web starter, like Spring's
/// `FilterChainProxy`: a `WebFilter` at `spring.security.filter.order`
/// (`-100`) that
///
/// 1. checks the request with the [firewall] (400 when refused);
/// 2. picks the first [chains] entry that matches;
/// 3. runs that chain's filters, then the rest of the web filters and the
///    controller, in a security context scope of their own — the user of
///    one request is never seen by another, and the scope ends with the
///    request.
///
/// A request no chain matches goes on without security, like Spring; the
/// starter's default chain (and `HttpSecurity` without `securityMatcher`)
/// matches every request.
///
/// An `AuthenticationException` or `AccessDeniedException` that no
/// chain's `ExceptionTranslationFilter` answered (a request outside every
/// chain calling a method with `@PreAuthorize`) is answered here: `401` or
/// `403` with a generic `ProblemDetail`, never the exception's message.
final class FilterChainProxy implements WebFilter, Ordered {
  /// The proxy over [chains], in order, at [order] among the web filters.
  FilterChainProxy(
    List<SecurityFilterChain> chains, {
    HttpFirewall? firewall,
    this.requestRejectedHandler = const HttpStatusRequestRejectedHandler(),
    this.order = defaultFilterOrder,
  }) : chains = List.unmodifiable(chains),
       firewall = firewall ?? StrictHttpFirewall();

  /// Spring Boot's `SecurityProperties.DEFAULT_FILTER_ORDER`.
  static const defaultFilterOrder = -100;

  @override
  final int order;

  /// The chains, in order.
  final List<SecurityFilterChain> chains;

  /// Refuses ambiguous requests.
  final HttpFirewall firewall;

  /// Answers refused requests.
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
      _log.debug('Rejecting request ${request.method.value}: ${e.reason}');
      await requestRejectedHandler.handle(request, response, e);
      return;
    }
    final selected = chains.where((c) => c.matches(request)).firstOrNull;
    await SecurityContextHolder.runWithContext(() async {
      try {
        if (selected == null || selected.filters.isEmpty) {
          return await chain.doFilter(request, response);
        }
        return await _VirtualChain(
          selected.filters,
          chain,
        ).doFilter(request, response);
      } on AuthenticationException catch (e) {
        _log.debug('Unauthenticated ${request.method.value}: $e');
        await writeSecurityProblem(
          request,
          response,
          HttpStatus.unauthorized,
          'Full authentication is required to access this resource',
        );
      } on AccessDeniedException catch (e) {
        _log.debug('Denied ${request.method.value}: $e');
        await writeSecurityProblem(
          request,
          response,
          HttpStatus.forbidden,
          'Access Denied',
        );
      }
    });
  }
}

final class _VirtualChain implements WebFilterChain {
  _VirtualChain(this.filters, this.original, [this.index = 0]);

  final List<WebFilter> filters;
  final WebFilterChain original;
  final int index;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    if (index == filters.length) {
      return original.doFilter(request, response);
    }
    return filters[index].doFilter(
      request,
      response,
      _VirtualChain(filters, original, index + 1),
    );
  }
}

/// Keeps the security context between requests, like Spring's
/// `SecurityContextRepository`.
abstract interface class SecurityContextRepository {
  /// The stored context of [request], or `null`.
  FutureOr<SecurityContext?> loadContext(ServerHttpRequest request);

  /// Stores [context] for the next requests.
  FutureOr<void> saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// Whether [request] has a stored context.
  bool containsContext(ServerHttpRequest request);
}

/// The context in the session (`SPRING_SECURITY_CONTEXT`), like Spring's
/// `HttpSessionSecurityContextRepository`. A session is created only to
/// store an authenticated (not anonymous) user. Loading gives a copy, so
/// two requests of one session never change each other's context.
final class HttpSessionSecurityContextRepository
    implements SecurityContextRepository {
  /// The repository.
  const HttpSessionSecurityContextRepository({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// The session attribute.
  static const springSecurityContextKey = 'SPRING_SECURITY_CONTEXT';

  /// Tells anonymous users (never stored) from authenticated ones.
  final AuthenticationTrustResolver trustResolver;

  @override
  SecurityContext? loadContext(ServerHttpRequest request) {
    final stored = request
        .getSession(create: false)
        ?.getAttribute(springSecurityContextKey);
    return stored is SecurityContext
        ? SecurityContextImpl(stored.authentication)
        : null;
  }

  @override
  void saveContext(
    SecurityContext context,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    final authentication = context.authentication;
    if (authentication == null || trustResolver.isAnonymous(authentication)) {
      request
          .getSession(create: false)
          ?.removeAttribute(springSecurityContextKey);
      return;
    }
    request.getSession()!.setAttribute(
      springSecurityContextKey,
      SecurityContextImpl(authentication),
    );
  }

  @override
  bool containsContext(ServerHttpRequest request) =>
      request
          .getSession(create: false)
          ?.getAttribute(springSecurityContextKey) !=
      null;
}

/// The context for the rest of this request only, like Spring's
/// `RequestAttributeSecurityContextRepository`.
final class RequestAttributeSecurityContextRepository
    implements SecurityContextRepository {
  /// The repository.
  const RequestAttributeSecurityContextRepository();

  /// The request attribute holding the context (also where the test
  /// support puts a mock user).
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

/// Several repositories: loads from the first that has a context, saves to
/// all, like Spring's `DelegatingSecurityContextRepository` (by default
/// the request attribute, then the session).
final class DelegatingSecurityContextRepository
    implements SecurityContextRepository {
  /// Over [repositories], in order.
  DelegatingSecurityContextRepository(
    List<SecurityContextRepository> repositories,
  ) : repositories = List.unmodifiable(repositories);

  /// The repositories.
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

/// Keeps nothing (stateless APIs), like Spring's
/// `NullSecurityContextRepository`.
final class NullSecurityContextRepository implements SecurityContextRepository {
  /// The repository.
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

/// Puts the stored context of the request in the `SecurityContextHolder`,
/// like Spring's `SecurityContextHolderFilter` (the holder's scope comes
/// from [FilterChainProxy] and ends with the request). Changes are not
/// saved automatically: login filters save explicitly, as in Spring 6.
final class SecurityContextHolderFilter implements WebFilter {
  /// Loads from [repository].
  const SecurityContextHolderFilter(this.repository);

  /// Where contexts are kept.
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
