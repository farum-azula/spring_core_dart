import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

final Random _random = Random.secure();

/// A CSRF token: what a state-changing request must carry, in the header
/// [headerName] or the form field [parameterName], like Spring's
/// `CsrfToken`.
final class CsrfToken {
  /// A token [token].
  const CsrfToken(this.headerName, this.parameterName, this.token);

  /// `X-CSRF-TOKEN` (or `X-XSRF-TOKEN` with the cookie repository).
  final String headerName;

  /// `_csrf`.
  final String parameterName;

  /// The value.
  final String token;
}

/// The token is missing or wrong: 403, like Spring's `CsrfException`.
class CsrfException extends AccessDeniedException {
  /// Described by [message].
  CsrfException(super.message);
}

/// No token was expected (none saved), like Spring's
/// `MissingCsrfTokenException`.
class MissingCsrfTokenException extends CsrfException {
  /// No token for the request.
  MissingCsrfTokenException()
    : super(
        'Could not verify the provided CSRF token because no token was found '
        'to compare.',
      );
}

/// The token sent does not match, like Spring's `InvalidCsrfTokenException`.
class InvalidCsrfTokenException extends CsrfException {
  /// A wrong or missing token.
  InvalidCsrfTokenException()
    : super('Invalid CSRF Token was found on the request parameter or header.');
}

/// Keeps the expected token, like Spring's `CsrfTokenRepository`.
abstract interface class CsrfTokenRepository {
  /// A new token.
  CsrfToken generateToken(ServerHttpRequest request);

  /// Stores [token] (`null` removes the stored one).
  FutureOr<void> saveToken(
    CsrfToken? token,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// The stored token, or `null`.
  FutureOr<CsrfToken?> loadToken(ServerHttpRequest request);
}

String _randomToken() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The token in the session, like Spring's `HttpSessionCsrfTokenRepository`
/// (Spring's default): the server remembers what each session must send.
final class HttpSessionCsrfTokenRepository implements CsrfTokenRepository {
  /// The repository.
  const HttpSessionCsrfTokenRepository({
    this.headerName = 'X-CSRF-TOKEN',
    this.parameterName = '_csrf',
  });

  /// The header.
  final String headerName;

  /// The form field.
  final String parameterName;

  /// The session attribute (Spring's name).
  static const sessionAttributeName =
      'org.springframework.security.web.csrf.'
      'HttpSessionCsrfTokenRepository.CSRF_TOKEN';

  @override
  CsrfToken generateToken(ServerHttpRequest request) =>
      CsrfToken(headerName, parameterName, _randomToken());

  @override
  void saveToken(
    CsrfToken? token,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    if (token == null) {
      request.getSession(create: false)?.removeAttribute(sessionAttributeName);
    } else {
      request.getSession()!.setAttribute(sessionAttributeName, token);
    }
  }

  @override
  CsrfToken? loadToken(ServerHttpRequest request) =>
      request.getSession(create: false)?.getAttribute(sessionAttributeName)
          as CsrfToken?;
}

/// The token in a cookie (`XSRF-TOKEN`) that the page's script sends back
/// in `X-XSRF-TOKEN`, like Spring's `CookieCsrfTokenRepository` — the
/// pattern of Angular and other single-page apps. Use
/// [CookieCsrfTokenRepository.withHttpOnlyFalse] so scripts can read it.
final class CookieCsrfTokenRepository implements CsrfTokenRepository {
  /// A repository; [cookieHttpOnly] keeps scripts from reading the cookie.
  const CookieCsrfTokenRepository({
    this.cookieName = 'XSRF-TOKEN',
    this.headerName = 'X-XSRF-TOKEN',
    this.parameterName = '_csrf',
    this.cookieHttpOnly = true,
    this.cookiePath,
    this.cookieDomain,
    this.sameSite,
  });

  /// A repository whose cookie scripts can read (the usual SPA setup).
  const CookieCsrfTokenRepository.withHttpOnlyFalse({
    String cookieName = 'XSRF-TOKEN',
    String headerName = 'X-XSRF-TOKEN',
    String? sameSite,
  }) : this(
         cookieName: cookieName,
         headerName: headerName,
         cookieHttpOnly: false,
         sameSite: sameSite,
       );

  /// The cookie.
  final String cookieName;

  /// The header.
  final String headerName;

  /// The form field.
  final String parameterName;

  /// Whether scripts cannot read the cookie.
  final bool cookieHttpOnly;

  /// The cookie's path (`/` when `null`).
  final String? cookiePath;

  /// The cookie's domain.
  final String? cookieDomain;

  /// The cookie's `SameSite`.
  final String? sameSite;

  @override
  CsrfToken generateToken(ServerHttpRequest request) =>
      CsrfToken(headerName, parameterName, _randomToken());

  @override
  void saveToken(
    CsrfToken? token,
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) {
    response.addCookie(
      ResponseCookie(
        cookieName,
        token?.token ?? '',
        path: cookiePath ?? '/',
        domain: cookieDomain,
        httpOnly: cookieHttpOnly,
        secure: request.isSecure,
        sameSite: sameSite,
        maxAge: token == null ? Duration.zero : null,
      ),
    );
  }

  @override
  CsrfToken? loadToken(ServerHttpRequest request) {
    final value = request.cookies[cookieName];
    if (value == null || value.isEmpty) {
      return null;
    }
    return CsrfToken(headerName, parameterName, value);
  }
}

/// Exposes the token to the request and reads the token a request sent,
/// like Spring's `CsrfTokenRequestHandler`.
abstract interface class CsrfTokenRequestHandler {
  /// Makes [token] available (request attributes `_csrf` and
  /// [CsrfToken]'s type name), loaded when first read.
  void handle(ServerHttpRequest request, CsrfToken Function() token);

  /// The token value [request] sent for [token] (header, then form
  /// field), unmasked; `null` when none.
  String? resolveCsrfTokenValue(
    ServerHttpRequest request,
    CsrfToken token,
    Map<String, List<String>>? form,
  );
}

/// Sends the token as it is, like Spring's
/// `CsrfTokenRequestAttributeHandler` (with the cookie repository, where
/// scripts read the cookie).
class CsrfTokenRequestAttributeHandler implements CsrfTokenRequestHandler {
  /// The handler.
  const CsrfTokenRequestAttributeHandler();

  /// The request attribute holding the [CsrfToken] (a function: the
  /// token is created when first read).
  static const attributeName = '_csrf';

  @override
  void handle(ServerHttpRequest request, CsrfToken Function() token) {
    CsrfToken? cached;
    CsrfToken read() => cached ??= present(token());
    request.attributes[attributeName] = read;
  }

  /// The token as pages get it.
  CsrfToken present(CsrfToken token) => token;

  @override
  String? resolveCsrfTokenValue(
    ServerHttpRequest request,
    CsrfToken token,
    Map<String, List<String>>? form,
  ) =>
      request.headers[token.headerName] ??
      form?[token.parameterName]?.firstOrNull;
}

/// Masks the token with fresh random bytes for each page, like Spring's
/// `XorCsrfTokenRequestAttributeHandler` (Spring 6's default): the page
/// never shows the same bytes twice, so compression attacks (BREACH)
/// cannot read it; checks unmask and compare in constant time.
final class XorCsrfTokenRequestAttributeHandler
    extends CsrfTokenRequestAttributeHandler {
  /// The handler.
  const XorCsrfTokenRequestAttributeHandler();

  @override
  CsrfToken present(CsrfToken token) =>
      CsrfToken(token.headerName, token.parameterName, _mask(token.token));

  @override
  String? resolveCsrfTokenValue(
    ServerHttpRequest request,
    CsrfToken token,
    Map<String, List<String>>? form,
  ) {
    final sent = super.resolveCsrfTokenValue(request, token, form);
    return sent == null ? null : _unmask(sent);
  }

  static String _mask(String token) {
    final tokenBytes = utf8.encode(token);
    final random = List<int>.generate(
      tokenBytes.length,
      (_) => _random.nextInt(256),
    );
    final xored = [
      for (var i = 0; i < tokenBytes.length; i++) tokenBytes[i] ^ random[i],
    ];
    return base64Url.encode([...random, ...xored]);
  }

  static String? _unmask(String masked) {
    final List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(masked));
    } on FormatException {
      return null;
    }
    if (bytes.length.isOdd || bytes.isEmpty) {
      return null;
    }
    final half = bytes.length ~/ 2;
    return utf8.decode([
      for (var i = 0; i < half; i++) bytes[i] ^ bytes[half + i],
    ], allowMalformed: true);
  }
}

/// The methods that need a token: all but GET, HEAD, TRACE and OPTIONS,
/// like Spring's `CsrfFilter.DEFAULT_CSRF_MATCHER`.
final class DefaultRequiresCsrfMatcher extends SimpleRequestMatcher {
  /// The matcher.
  const DefaultRequiresCsrfMatcher();

  @override
  bool matches(ServerHttpRequest request) => !const {
    HttpMethod.get,
    HttpMethod.head,
    HttpMethod.trace,
    HttpMethod.options,
  }.contains(request.method);

  @override
  String toString() => 'CsrfNotRequired [GET, HEAD, TRACE, OPTIONS]';
}

/// Checks the CSRF token of state-changing requests, like Spring's
/// `CsrfFilter`: the token is created only when a page reads it (or a
/// check needs it); a missing or wrong token is a 403 (also for anonymous
/// users: CSRF is checked before anything else).
final class CsrfFilter implements WebFilter {
  /// A filter keeping tokens in [tokenRepository].
  const CsrfFilter(
    this.tokenRepository, {
    this.requestHandler = const XorCsrfTokenRequestAttributeHandler(),
    this.requireCsrfProtectionMatcher = const DefaultRequiresCsrfMatcher(),
    this.accessDeniedHandler = const AccessDeniedHandlerImpl(),
  });

  /// Where the expected token is kept.
  final CsrfTokenRepository tokenRepository;

  /// Exposes and reads tokens.
  final CsrfTokenRequestHandler requestHandler;

  /// Which requests need a token.
  final RequestMatcher requireCsrfProtectionMatcher;

  /// Answers a failed check.
  final AccessDeniedHandler accessDeniedHandler;

  /// The request attribute the test support (`csrf()`) sets to `true` (a
  /// valid token) or `false` (an invalid one). Clients cannot set request
  /// attributes: it is not a way around the check.
  static const testTokenAttribute = 'spring.security.test.csrfToken';

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    var current = request;
    if (current.attributes[testTokenAttribute] case final bool valid) {
      if (valid) {
        return await chain.doFilter(current, response);
      }
      await accessDeniedHandler.handle(
        current,
        response,
        InvalidCsrfTokenException(),
      );
      return;
    }
    final loaded = await tokenRepository.loadToken(current);
    CsrfToken? generated;
    CsrfToken token() {
      if (loaded != null) {
        return loaded;
      }
      if (generated == null) {
        final created = generated = tokenRepository.generateToken(current);
        // The token is read synchronously (a supplier), so the save cannot
        // be awaited here; the repositories write a cookie or a session.
        // ignore: discarded_futures
        tokenRepository.saveToken(created, current, response);
      }
      return generated!;
    }

    requestHandler.handle(current, token);
    if (!requireCsrfProtectionMatcher.matches(current)) {
      return await chain.doFilter(current, response);
    }
    if (loaded == null) {
      // Nothing to compare with: a token is created for the next page, and
      // this request fails.
      token();
      await accessDeniedHandler.handle(
        current,
        response,
        MissingCsrfTokenException(),
      );
      return;
    }
    Map<String, List<String>>? form;
    if (current.headers[loaded.headerName] == null) {
      (current, form) = await readFormParameters(current);
    }
    final sent = requestHandler.resolveCsrfTokenValue(current, loaded, form);
    if (sent == null ||
        !constantTimeEquals(utf8.encode(sent), utf8.encode(loaded.token))) {
      await accessDeniedHandler.handle(
        current,
        response,
        InvalidCsrfTokenException(),
      );
      return;
    }
    await chain.doFilter(current, response);
  }
}

/// Reads the token a page should send, from the request attributes
/// (`HttpSecurity.csrf` puts it there): render it in a form as the hidden
/// field `token.parameterName`, or send it in the header `token.headerName`.
///
/// ```dart
/// @GetMapping('/form')
/// String form(ServerHttpRequest request) {
///   final csrf = csrfTokenOf(request)!;
///   return '<input type="hidden" name="${csrf.parameterName}" '
///       'value="${csrf.token}">';
/// }
/// ```
CsrfToken? csrfTokenOf(ServerHttpRequest request) => switch (request
    .attributes[CsrfTokenRequestAttributeHandler.attributeName]) {
  final CsrfToken Function() read => read(),
  _ => null,
};
