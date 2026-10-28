import 'dart:async';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/request_cache.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web.access');

/// What a web access rule decides about: the request, and the path
/// variables of the rule's pattern.
///
/// A custom `AuthorizationManager` passed to `access(...)` receives it.
/// With the rule `/users/{name}/**`, a request to `/users/ada/orders` has
/// `variables['name'] == 'ada'`.
///
/// Spring (Java): `RequestAuthorizationContext`.
final class RequestAuthorizationContext {
  /// The context of [request], with the path [variables] of the matched
  /// rule.
  const RequestAuthorizationContext(this.request, [this.variables = const {}]);

  /// The request being checked.
  final ServerHttpRequest request;

  /// The path variables of the matched pattern by name, percent-decoded:
  /// `{id}` of `/users/{id}`.
  final Map<String, String> variables;
}

/// The access rules of `authorizeHttpRequests`, as one
/// [AuthorizationManager]: the first rule whose matcher matches decides.
///
/// Order matters: put specific rules before general ones. A request no
/// rule matches is denied, so a forgotten path is closed rather than open
/// (the default since Spring Security 6). `HttpSecurity` builds it;
/// applications do not.
///
/// Spring (Java): `RequestMatcherDelegatingAuthorizationManager`.
final class RequestMatcherDelegatingAuthorizationManager
    implements AuthorizationManager<ServerHttpRequest> {
  /// A manager over [rules], tried in order; each pairs a matcher with
  /// the manager that decides for it.
  RequestMatcherDelegatingAuthorizationManager(
    List<(RequestMatcher, AuthorizationManager<RequestAuthorizationContext>)>
    rules,
  ) : rules = List.unmodifiable(rules);

  /// The rules in order; cannot be modified.
  final List<
    (RequestMatcher, AuthorizationManager<RequestAuthorizationContext>)
  >
  rules;

  @override
  Future<AuthorizationResult?> authorize(
    Authentication? Function() authentication,
    ServerHttpRequest request,
  ) async {
    for (final (matcher, manager) in rules) {
      final match = matcher.matcher(request);
      if (match.isMatch) {
        _log.trace('Checking authorization on $request using $manager');
        return await manager.authorize(
          authentication,
          RequestAuthorizationContext(request, match.variables),
        );
      }
    }
    _log.trace('Denying request since no rule matched');
    return AuthorizationDecision.denied;
  }
}

/// The last filter of a chain: it checks the request against the access
/// rules and lets it on to the controller only when they grant it.
///
/// A denial, and an abstention too (fail closed), throws an
/// `AuthorizationDeniedException`, which the [ExceptionTranslationFilter]
/// turns into a login request or a 403. With no authentication at all
/// (anonymous users switched off), reading the user throws an
/// `AuthenticationCredentialsNotFoundException`, which asks to log in.
/// `authorizeHttpRequests` adds it; a chain without
/// `authorizeHttpRequests` has none, and lets every request through (a
/// warning is logged).
///
/// Spring (Java): `AuthorizationFilter`.
final class AuthorizationFilter implements WebFilter {
  /// A filter that asks [authorizationManager] about each request.
  const AuthorizationFilter(this.authorizationManager);

  /// Decides about each request, usually a
  /// [RequestMatcherDelegatingAuthorizationManager].
  final AuthorizationManager<ServerHttpRequest> authorizationManager;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    Authentication? current() {
      final authentication = SecurityContextHolder.getContext().authentication;
      if (authentication == null) {
        throw AuthenticationCredentialsNotFoundException();
      }
      return authentication;
    }

    final result = await authorizationManager.authorize(current, request);
    if (result == null || !result.isGranted) {
      throw AuthorizationDeniedException(
        'Access Denied',
        result ?? AuthorizationDecision.denied,
      );
    }
    await chain.doFilter(request, response);
  }
}

/// The filter that turns security errors into HTTP answers: "log in
/// first" or "forbidden".
///
/// It catches what the rest of the chain throws: the access rules, and
/// method security in controllers and services.
///
/// - An `AuthenticationException`, or an `AccessDeniedException` for an
///   anonymous user (or no user): the request is saved in the
///   [requestCache] (to come back to after the login), the context is
///   emptied, and the [authenticationEntryPoint] asks to log in, with a
///   401 and a challenge or a redirect to the login page. When the
///   response has already been sent, it only logs a warning.
/// - An `AccessDeniedException` for a logged-in user: the
///   [accessDeniedHandler] answers, 403 by default.
///
/// Other errors pass through. `HttpSecurity` adds it to every chain and
/// picks the entry point from the login methods; change them with
/// `exceptionHandling`.
///
/// Spring (Java): `ExceptionTranslationFilter`.
final class ExceptionTranslationFilter implements WebFilter {
  /// A filter that asks to log in with [authenticationEntryPoint]; by
  /// default denials get a plain 403 and no request is saved.
  const ExceptionTranslationFilter(
    this.authenticationEntryPoint, {
    this.accessDeniedHandler = const AccessDeniedHandlerImpl(),
    this.requestCache = const NullRequestCache(),
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Answers a request that must log in first.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Answers a logged-in user who may not do what was asked.
  final AccessDeniedHandler accessDeniedHandler;

  /// Saves the request before asking to log in, so the login can go back
  /// to it.
  final RequestCache requestCache;

  /// Tells anonymous users from real logins.
  final AuthenticationTrustResolver trustResolver;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    try {
      await chain.doFilter(request, response);
    } on AuthenticationException catch (e) {
      await _startAuthentication(request, response, e);
    } on AccessDeniedException catch (e) {
      final authentication = SecurityContextHolder.getContext().authentication;
      if (authentication == null || trustResolver.isAnonymous(authentication)) {
        await _startAuthentication(
          request,
          response,
          InsufficientAuthenticationException(
            'Full authentication is required to access this resource',
            e,
          ),
        );
      } else {
        await accessDeniedHandler.handle(request, response, e);
      }
    }
  }

  Future<void> _startAuthentication(
    ServerHttpRequest request,
    ServerHttpResponse response,
    AuthenticationException reason,
  ) async {
    if (response.isCommitted) {
      _log.warning(
        'Cannot ask to authenticate, the response is already committed',
      );
      return;
    }
    SecurityContextHolder.setContext(
      SecurityContextHolder.createEmptyContext(),
    );
    await requestCache.saveRequest(request, response);
    await authenticationEntryPoint.commence(request, response, reason);
  }
}

/// The filter that gives a request with no login an anonymous user
/// (`anonymousUser`, with `ROLE_ANONYMOUS`).
///
/// Rules can then tell "not logged in" (`anonymous()`, `isAnonymous()`)
/// from "no security context", and `permitAll` methods with
/// `@PreAuthorize` work for visitors. A request that already has a user
/// keeps it. Switch it off with `anonymous((a) => a.disable())`.
///
/// Spring (Java): `AnonymousAuthenticationFilter`.
final class AnonymousAuthenticationFilter implements WebFilter {
  /// A filter giving anonymous users the principal [principal] and the
  /// authorities named in [authorities]; [key] marks the tokens it
  /// creates.
  AnonymousAuthenticationFilter({
    this.key = 'anonymousAuthenticationKey',
    this.principal = 'anonymousUser',
    List<String> authorities = const ['ROLE_ANONYMOUS'],
  }) : authorities = AuthorityUtils.createAuthorityList(authorities);

  /// The key the anonymous tokens are created with.
  final String key;

  /// The principal of anonymous users, `'anonymousUser'` by default.
  final Object principal;

  /// The authorities of anonymous users, `ROLE_ANONYMOUS` by default.
  final List<GrantedAuthority> authorities;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    SecurityContextHolder.getContext().authentication ??=
        AnonymousAuthenticationToken(key, principal, authorities);
    return chain.doFilter(request, response);
  }
}

/// The filter that makes `request.principal` return the current user, so
/// a controller parameter of type `Principal` receives the
/// `Authentication`.
///
/// It is `null` for anonymous users and when there is no user. A value
/// assigned to `request.principal` later wins.
///
/// Spring (Java): `SecurityContextHolderAwareRequestFilter`.
final class SecurityContextHolderAwareRequestFilter implements WebFilter {
  /// A filter using [trustResolver] to recognise anonymous users.
  const SecurityContextHolderAwareRequestFilter({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Tells anonymous users, who get no principal, from real logins.
  final AuthenticationTrustResolver trustResolver;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) => chain.doFilter(_AwareRequest(request, trustResolver), response);
}

final class _AwareRequest extends ServerHttpRequestDecorator {
  _AwareRequest(super.delegate, this._trustResolver);

  final AuthenticationTrustResolver _trustResolver;
  Principal? _set;
  bool _assigned = false;

  @override
  Principal? get principal {
    if (_assigned) {
      return _set;
    }
    final authentication = SecurityContextHolder.getContext().authentication;
    return authentication == null || _trustResolver.isAnonymous(authentication)
        ? null
        : authentication;
  }

  @override
  set principal(Principal? value) {
    _assigned = true;
    _set = value;
  }
}
