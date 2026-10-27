import 'dart:async';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/request_cache.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web.access');

/// What an [AuthorizationManager] of requests decides about: the request
/// and the path variables of the rule's pattern, like Spring's
/// `RequestAuthorizationContext`.
final class RequestAuthorizationContext {
  /// [request] with [variables].
  const RequestAuthorizationContext(this.request, [this.variables = const {}]);

  /// The request.
  final ServerHttpRequest request;

  /// `{id}` of `/users/{id}`, decoded.
  final Map<String, String> variables;
}

/// The rules of `authorizeHttpRequests`, like Spring's
/// `RequestMatcherDelegatingAuthorizationManager`: the first rule whose
/// matcher matches decides; when no rule matches, access is denied
/// (Spring 6's default, docs/security.md rule 1).
final class RequestMatcherDelegatingAuthorizationManager
    implements AuthorizationManager<ServerHttpRequest> {
  /// The [rules] in order.
  RequestMatcherDelegatingAuthorizationManager(
    List<(RequestMatcher, AuthorizationManager<RequestAuthorizationContext>)>
    rules,
  ) : rules = List.unmodifiable(rules);

  /// The rules.
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

/// Checks every request against the rules, like Spring's
/// `AuthorizationFilter`: a denial throws `AccessDeniedException`, which
/// the [ExceptionTranslationFilter] turns into a login challenge or a 403.
/// An abstention denies too (fail closed).
final class AuthorizationFilter implements WebFilter {
  /// Checks with [authorizationManager].
  const AuthorizationFilter(this.authorizationManager);

  /// Decides.
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

/// Turns security exceptions of the rest of the chain (the rules, the
/// controllers' method security) into answers, like Spring's
/// `ExceptionTranslationFilter`:
///
/// - an `AuthenticationException`, or an `AccessDeniedException` for an
///   anonymous user: the request is saved (to come back after the login),
///   the context cleared and the [authenticationEntryPoint] asks to log
///   in (401 with a challenge, or a redirect to the login page);
/// - an `AccessDeniedException` for a logged-in user: the
///   [accessDeniedHandler] (403).
final class ExceptionTranslationFilter implements WebFilter {
  /// A filter starting authentication with [authenticationEntryPoint].
  const ExceptionTranslationFilter(
    this.authenticationEntryPoint, {
    this.accessDeniedHandler = const AccessDeniedHandlerImpl(),
    this.requestCache = const NullRequestCache(),
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Asks to log in.
  final AuthenticationEntryPoint authenticationEntryPoint;

  /// Answers denials of logged-in users.
  final AccessDeniedHandler accessDeniedHandler;

  /// Saves the request before asking to log in.
  final RequestCache requestCache;

  /// Tells anonymous users apart.
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

/// Gives requests without a user the anonymous one, like Spring's
/// `AnonymousAuthenticationFilter`: rules can then tell "not logged in"
/// (`anonymous()`, `isAnonymous()`) from "no security context".
final class AnonymousAuthenticationFilter implements WebFilter {
  /// Anonymous users named [principal] with [authorities].
  AnonymousAuthenticationFilter({
    this.key = 'anonymousAuthenticationKey',
    this.principal = 'anonymousUser',
    List<String> authorities = const ['ROLE_ANONYMOUS'],
  }) : authorities = AuthorityUtils.createAuthorityList(authorities);

  /// Identifies tokens made here.
  final String key;

  /// The principal.
  final Object principal;

  /// The authorities.
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

/// Makes `request.principal` the current user (`null` for anonymous ones),
/// like Spring's `SecurityContextHolderAwareRequestFilter`, so a controller
/// taking `Principal` gets the `Authentication`.
final class SecurityContextHolderAwareRequestFilter implements WebFilter {
  /// The filter.
  const SecurityContextHolderAwareRequestFilter({
    this.trustResolver = const AuthenticationTrustResolverImpl(),
  });

  /// Tells anonymous users apart.
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
