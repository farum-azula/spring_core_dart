import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_starter_security/src/web/entry_points.dart';
import 'package:spring_boot_starter_security/src/web/log_support.dart';
import 'package:spring_boot_starter_security/src/web/request_matcher.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.security.web.csrf.CsrfFilter');

final Random _random = Random.secure();

/// A CSRF token: a random secret a page must send back with every request
/// that changes state, in the header [headerName] or the form field
/// [parameterName].
///
/// Cross-site request forgery is a page on another site making the user's
/// browser send a request to your application, with the user's cookies.
/// That page cannot read your pages, so it cannot know the token, and its
/// request fails. Pages get the current token with [csrfTokenOf].
///
/// Spring (Java): `CsrfToken`.
final class CsrfToken {
  /// A token whose value is [token], expected in the header [headerName]
  /// or the form field [parameterName].
  const CsrfToken(this.headerName, this.parameterName, this.token);

  /// The request header that carries the token: `X-CSRF-TOKEN`, or
  /// `X-XSRF-TOKEN` with the cookie repository.
  final String headerName;

  /// The form field that carries the token, `_csrf` by default.
  final String parameterName;

  /// The secret value.
  final String token;
}

/// A request that needed a CSRF token was refused because the token was
/// missing or wrong; the client gets 403.
///
/// Spring (Java): `CsrfException`.
class CsrfException extends AccessDeniedException {
  /// A refusal described by [message], for logs.
  CsrfException(super.message);
}

/// A request was refused because no token is stored for its client yet, so
/// there is nothing to compare with (a first request, or an expired
/// session).
///
/// A token is created for the next page at the same time.
///
/// Spring (Java): `MissingCsrfTokenException`.
class MissingCsrfTokenException extends CsrfException {
  /// The refusal, with Spring's message.
  MissingCsrfTokenException()
    : super(
        'Could not verify the provided CSRF token because no token was found '
        'to compare.',
      );
}

/// A request was refused because the token it sent is missing or does not
/// match the stored one.
///
/// Spring (Java): `InvalidCsrfTokenException`.
class InvalidCsrfTokenException extends CsrfException {
  /// The refusal, with Spring's message.
  InvalidCsrfTokenException()
    : super('Invalid CSRF Token was found on the request parameter or header.');
}

/// Where the token a client is expected to send back is kept between
/// requests.
///
/// The default, [HttpSessionCsrfTokenRepository], keeps it in the
/// session. [CookieCsrfTokenRepository] keeps it in a cookie, for
/// single-page apps. Set one with `csrf((c) => c.csrfTokenRepository(...))`.
///
/// Spring (Java): `CsrfTokenRepository`.
abstract interface class CsrfTokenRepository {
  /// A new random token for [request]; not stored yet.
  CsrfToken generateToken(ServerHttpRequest request);

  /// Stores [token] for the client of [request]; `null` removes the stored
  /// one (at logout, and after a login so the token changes).
  FutureOr<void> saveToken(
    CsrfToken? token,
    ServerHttpRequest request,
    ServerHttpResponse response,
  );

  /// The token stored for the client of [request], or `null` when there
  /// is none.
  FutureOr<CsrfToken?> loadToken(ServerHttpRequest request);
}

String _randomToken() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// The default [CsrfTokenRepository]: the token is kept in the HTTP
/// session, so the server remembers what each session must send.
///
/// Pages that render forms on the server use it as is. A session is
/// created when a token is first needed.
///
/// Spring (Java): `HttpSessionCsrfTokenRepository`, also the default
/// there.
final class HttpSessionCsrfTokenRepository implements CsrfTokenRepository {
  /// A repository naming [headerName] and [parameterName] in its tokens.
  const HttpSessionCsrfTokenRepository({
    this.headerName = 'X-CSRF-TOKEN',
    this.parameterName = '_csrf',
  });

  /// The request header that carries the token, `X-CSRF-TOKEN` by
  /// default.
  final String headerName;

  /// The form field that carries the token, `_csrf` by default.
  final String parameterName;

  /// The session attribute holding the token; Spring's name.
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

/// A [CsrfTokenRepository] that keeps the token in a cookie, `XSRF-TOKEN`,
/// which the page's script sends back in the `X-XSRF-TOKEN` header.
///
/// This is the pattern of Angular and other single-page apps: they render
/// no forms on the server, so they read the token from the cookie. A
/// page on another site cannot read your cookies, so it still cannot
/// send the token. Use [CookieCsrfTokenRepository.withHttpOnlyFalse] so
/// scripts can read the cookie, and the plain
/// [CsrfTokenRequestAttributeHandler]: the default handler expects a
/// masked token, not the raw cookie value.
///
/// ```dart
/// http.csrf((c) => c
///     .csrfTokenRepository(
///         const CookieCsrfTokenRepository.withHttpOnlyFalse())
///     .csrfTokenRequestHandler(const CsrfTokenRequestAttributeHandler()));
/// ```
///
/// Spring (Java):
/// ```java
/// http.csrf(c -> c
///     .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
///     .csrfTokenRequestHandler(new CsrfTokenRequestAttributeHandler()));
/// ```
final class CookieCsrfTokenRepository implements CsrfTokenRepository {
  /// A repository writing the cookie [cookieName]; with [cookieHttpOnly]
  /// (the default) scripts cannot read it, which suits server-rendered
  /// forms only.
  const CookieCsrfTokenRepository({
    this.cookieName = 'XSRF-TOKEN',
    this.headerName = 'X-XSRF-TOKEN',
    this.parameterName = '_csrf',
    this.cookieHttpOnly = true,
    this.cookiePath,
    this.cookieDomain,
    this.sameSite,
  });

  /// A repository whose cookie scripts can read: the usual setup of a
  /// single-page app.
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

  /// The cookie's name, `XSRF-TOKEN` by default.
  final String cookieName;

  /// The request header that carries the token, `X-XSRF-TOKEN` by
  /// default.
  final String headerName;

  /// The form field that carries the token, `_csrf` by default.
  final String parameterName;

  /// Whether the cookie is `HttpOnly`, hidden from scripts.
  final bool cookieHttpOnly;

  /// The cookie's `Path`; `/` when `null`.
  final String? cookiePath;

  /// The cookie's `Domain`; the current host only when `null`.
  final String? cookieDomain;

  /// The cookie's `SameSite` attribute (`Lax`, `Strict`, `None`); not
  /// sent when `null`.
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

/// The part of CSRF protection that hands the token to pages and reads the
/// token a request sent back.
///
/// The default, [XorCsrfTokenRequestAttributeHandler], masks the token
/// differently on every page. [CsrfTokenRequestAttributeHandler] hands it
/// over as it is, which the cookie pattern of single-page apps needs.
///
/// Spring (Java): `CsrfTokenRequestHandler`.
abstract interface class CsrfTokenRequestHandler {
  /// Makes the token available to the request's pages through
  /// [csrfTokenOf]; [token] is called, and a new token stored, only when
  /// a page first reads it.
  void handle(ServerHttpRequest request, CsrfToken Function() token);

  /// The token value [request] sent back for [token], read from the
  /// header, else from the [form] fields, and unmasked; `null` when the
  /// request sent none.
  String? resolveCsrfTokenValue(
    ServerHttpRequest request,
    CsrfToken token,
    Map<String, List<String>>? form,
  );
}

/// A [CsrfTokenRequestHandler] that hands the token to pages as it is
/// stored, without masking.
///
/// Use it with [CookieCsrfTokenRepository], where scripts read the raw
/// value from the cookie and send it back as it is.
///
/// Spring (Java): `CsrfTokenRequestAttributeHandler`.
class CsrfTokenRequestAttributeHandler implements CsrfTokenRequestHandler {
  /// The stateless handler.
  const CsrfTokenRequestAttributeHandler();

  /// The request attribute holding a function that returns the
  /// [CsrfToken]; the token is created when the function is first
  /// called. Read it with [csrfTokenOf].
  static const attributeName = '_csrf';

  @override
  void handle(ServerHttpRequest request, CsrfToken Function() token) {
    CsrfToken? cached;
    CsrfToken read() => cached ??= present(token());
    request.attributes[attributeName] = read;
  }

  /// The token as pages get it; this class returns [token] unchanged.
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

/// The default [CsrfTokenRequestHandler]: each page gets the token mixed
/// (XOR) with fresh random bytes, and a request's token is unmasked before
/// the check.
///
/// The page never shows the same bytes twice, so an attack that guesses
/// secrets from the size of compressed responses (BREACH) cannot read
/// it. The check compares in constant time. With the cookie pattern of
/// single-page apps, use [CsrfTokenRequestAttributeHandler] instead.
///
/// Spring (Java): `XorCsrfTokenRequestAttributeHandler`, the default
/// since Spring Security 6.
final class XorCsrfTokenRequestAttributeHandler
    extends CsrfTokenRequestAttributeHandler {
  /// The stateless handler.
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

/// The default rule of which requests need a CSRF token: every method but
/// GET, HEAD, TRACE and OPTIONS, which must not change state.
///
/// Spring (Java): `CsrfFilter.DEFAULT_CSRF_MATCHER`.
final class DefaultRequiresCsrfMatcher extends SimpleRequestMatcher {
  /// The stateless matcher.
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

/// The filter that refuses state-changing requests without the right CSRF
/// token.
///
/// It runs early in the chain, before logins and access rules. For a
/// request that needs a token (by default every method but GET, HEAD,
/// TRACE and OPTIONS):
///
/// - no token stored for the client yet: 403 with a
///   [MissingCsrfTokenException], and a new token is created for the
///   next page;
/// - a token sent that does not match the stored one, compared in
///   constant time, or no token sent: 403 with an
///   [InvalidCsrfTokenException].
///
/// The 403 comes from [accessDeniedHandler], also for anonymous users,
/// who are not asked to log in. A login form posted without a token is
/// refused too. The token is created only when a page reads it or a check
/// needs it. `HttpSecurity` adds it unless `csrf((c) => c.disable())`;
/// disable it only for APIs that authenticate with headers, never
/// cookies.
///
/// Spring (Java): `CsrfFilter`.
final class CsrfFilter implements WebFilter {
  /// A filter keeping tokens in [tokenRepository], by default masking them
  /// and checking every method but GET, HEAD, TRACE and OPTIONS.
  const CsrfFilter(
    this.tokenRepository, {
    this.requestHandler = const XorCsrfTokenRequestAttributeHandler(),
    this.requireCsrfProtectionMatcher = const DefaultRequiresCsrfMatcher(),
    this.accessDeniedHandler = const AccessDeniedHandlerImpl(),
  });

  /// Where the token each client must send back is kept.
  final CsrfTokenRepository tokenRepository;

  /// Hands tokens to pages and reads the tokens requests send.
  final CsrfTokenRequestHandler requestHandler;

  /// Decides which requests need a token.
  final RequestMatcher requireCsrfProtectionMatcher;

  /// Answers a refused request, with a 403 by default.
  final AccessDeniedHandler accessDeniedHandler;

  /// The request attribute that the test support's `csrf()` sets to `true`
  /// (act as if a valid token was sent) or `false` (an invalid one).
  ///
  /// Request attributes live on the server side only and no client can
  /// set them, so this is not a way around the check.
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
      _logInvalid(current);
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
      _log.trace(
        () =>
            'Did not protect against CSRF since request did not match '
            '$requireCsrfProtectionMatcher',
      );
      return await chain.doFilter(current, response);
    }
    if (loaded == null) {
      // Nothing to compare with: a token is created for the next page, and
      // this request fails.
      token();
      _logInvalid(current);
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
      _logInvalid(current);
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

/// The CSRF token the page being rendered must send back, or `null` when
/// CSRF protection is off for the request.
///
/// Every form that posts to the application needs it as a hidden field
/// named `token.parameterName`; a script sends it in the header
/// `token.headerName`. Reading it creates and stores the token if the
/// client has none yet.
///
/// ```dart
/// @GetMapping('/form')
/// String form(ServerHttpRequest request) {
///   final csrf = csrfTokenOf(request)!;
///   return '<input type="hidden" name="${csrf.parameterName}" '
///       'value="${csrf.token}">';
/// }
/// ```
///
/// Spring (Java): the `_csrf` request attribute (`${_csrf.token}` in a
/// template).
CsrfToken? csrfTokenOf(ServerHttpRequest request) => switch (request
    .attributes[CsrfTokenRequestAttributeHandler.attributeName]) {
  final CsrfToken Function() read => read(),
  _ => null,
};

// Never the token, the one sent or the stored one.
void _logInvalid(ServerHttpRequest request) =>
    _log.debug(() => 'Invalid CSRF token found for ${logText(request.path)}');
