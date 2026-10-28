/// Helpers for `MockMvc` tests of a secured web application: make a test
/// request as a given user, with a JWT, or with a CSRF token, without
/// going through a real login.
///
/// Each helper is a request post-processor: add it to a
/// `MockRequestBuilder` with `with_`. The user helpers put the user in
/// the request's security context, so the request skips the login and
/// the access rules see that user. They rely on the chain reading the
/// request attribute repository, which every chain does unless it sets
/// its own `securityContextRepository`. This library also re-exports
/// `withMockUser` and its siblings from `spring_security_core`.
///
/// ```dart
/// import 'package:spring_boot_starter_security/testing.dart';
///
/// await app.mockMvc
///     .perform(MockRequestBuilder(HttpMethod.get, '/api/admin')
///       ..with_(user('ada').roles(['ADMIN'])))
///     .andExpect(status: 200);
/// await app.mockMvc
///     .perform(MockRequestBuilder(HttpMethod.post, '/api/books')
///       ..with_(user('ada'))
///       ..with_(csrf()))
///     .andExpect(status: 201);
/// ```
///
/// Spring (Java): `spring-security-test`'s
/// `SecurityMockMvcRequestPostProcessors` (`user`, `jwt`, `csrf`, ...).
library;

import 'dart:convert';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';

export 'package:spring_security_core/testing.dart';

MockServerHttpRequest _withContext(
  MockServerHttpRequest request,
  Authentication authentication,
) {
  request.attributes[RequestAttributeSecurityContextRepository.attributeName] =
      SecurityContextImpl(authentication);
  return request;
}

/// Makes the request as the user [username], already logged in: no
/// password is checked.
///
/// The user has the password `password` and the role `USER` unless
/// changed with the returned processor's methods.
///
/// ```dart
/// MockRequestBuilder(HttpMethod.get, '/api/admin')
///   ..with_(user('ada').roles(['ADMIN']));
/// ```
///
/// Spring (Java): `user("ada").roles("ADMIN")`.
UserRequestPostProcessor user(String username) =>
    UserRequestPostProcessor._(username);

/// The request post-processor [user] returns; its methods change the
/// user's [roles], [authorities] or [password].
final class UserRequestPostProcessor implements RequestPostProcessor {
  UserRequestPostProcessor._(this._username);

  final String _username;
  String _password = 'password';
  List<GrantedAuthority> _authorities = [SimpleGrantedAuthority('ROLE_USER')];

  /// Sets the roles, written without `ROLE_` (`['ADMIN']` gives
  /// `ROLE_ADMIN`); replaces the default `USER` and earlier authorities.
  ///
  /// Throws an [ArgumentError] for a role that starts with `ROLE_`.
  UserRequestPostProcessor roles(List<String> roles) {
    _authorities = User.withUsername('x').roles(roles).build().authorities;
    return this;
  }

  /// Sets the authorities by their full names (`SCOPE_read`), replacing
  /// the roles.
  UserRequestPostProcessor authorities(List<String> authorities) {
    _authorities = AuthorityUtils.createAuthorityList(authorities);
    return this;
  }

  /// Sets the user's password, which only matters to code that reads it;
  /// no login runs.
  UserRequestPostProcessor password(String password) {
    _password = password;
    return this;
  }

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) {
    final user = User.withUsername(_username)
        .password(_password)
        .authorities(_authorities)
        .build();
    return _withContext(
      request,
      UsernamePasswordAuthenticationToken.authenticated(
        user,
        user.password,
        user.authorities,
      ),
    );
  }
}

/// Makes the request as [user], already logged in, for tests that need
/// your own `UserDetails` class as the principal.
RequestPostProcessor userDetails(UserDetails user) =>
    FunctionRequestPostProcessor(
      (request) => _withContext(
        request,
        UsernamePasswordAuthenticationToken.authenticated(
          user,
          user.password,
          user.authorities,
        ),
      ),
    );

/// Makes the request with [authentication] as the current user, for any
/// kind of login, such as a custom token.
RequestPostProcessor authentication(Authentication authentication) =>
    FunctionRequestPostProcessor(
      (request) => _withContext(request, authentication),
    );

/// Makes the request as an anonymous user (`anonymousUser` with
/// `ROLE_ANONYMOUS`), what a visitor without a login is.
RequestPostProcessor anonymous() => FunctionRequestPostProcessor(
  (request) => _withContext(
    request,
    AnonymousAuthenticationToken(
      'key',
      'anonymousUser',
      AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
    ),
  ),
);

/// Adds an `Authorization: Basic` header with [username] and [password],
/// so the real Basic login runs and checks them against the application's
/// users.
///
/// Use it to test the login itself; [user] is shorter for everything
/// else.
RequestPostProcessor httpBasic(String username, String password) =>
    FunctionRequestPostProcessor((request) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64.encode(utf8.encode('$username:$password'))}',
      );
      return request;
    });

/// Makes the request pass the CSRF check as if it carried a valid token;
/// call `useInvalidToken()` on the result to test a refused one.
///
/// Requests other than GET, HEAD, TRACE and OPTIONS need it while CSRF
/// protection is on.
///
/// Spring (Java): `csrf()`.
CsrfRequestPostProcessor csrf() => CsrfRequestPostProcessor._();

/// The request post-processor [csrf] returns.
final class CsrfRequestPostProcessor implements RequestPostProcessor {
  CsrfRequestPostProcessor._();

  bool _valid = true;

  /// Makes the request act as if it carried a wrong token, so the CSRF
  /// check refuses it with 403.
  CsrfRequestPostProcessor useInvalidToken() {
    _valid = false;
    return this;
  }

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) {
    request.attributes[CsrfFilter.testTokenAttribute] = _valid;
    return request;
  }
}

/// Makes the request as if it carried a valid JWT bearer token: no token
/// is decoded or verified.
///
/// The token has the subject `user` and the scope `read` (the authority
/// `SCOPE_read`), is issued now and expires in 5 minutes, unless changed
/// with the returned processor's methods. The authorities come from the
/// default converter, not from the application's `jwt.*` properties.
///
/// ```dart
/// MockRequestBuilder(HttpMethod.get, '/api/orders')
///   ..with_(jwt().subject('ada').claim('scope', 'orders:read'));
/// ```
///
/// Spring (Java): `jwt().jwt(j -> j.subject("ada"))`.
JwtRequestPostProcessor jwt() => JwtRequestPostProcessor._();

/// The request post-processor [jwt] returns; its methods change the
/// token's claims and authorities.
final class JwtRequestPostProcessor implements RequestPostProcessor {
  JwtRequestPostProcessor._();

  final _claims = <String, Object?>{'sub': 'user', 'scope': 'read'};
  List<GrantedAuthority>? _authorities;

  /// Sets the claim [name] to [value], replacing the default one.
  JwtRequestPostProcessor claim(String name, Object? value) {
    _claims[name] = value;
    return this;
  }

  /// Sets the `sub` claim, which is also the user's name.
  JwtRequestPostProcessor subject(String subject) => claim('sub', subject);

  /// Sets the authorities by their full names, instead of those derived
  /// from the `scope` claim.
  JwtRequestPostProcessor authorities(List<String> authorities) {
    _authorities = AuthorityUtils.createAuthorityList(authorities);
    return this;
  }

  @override
  MockServerHttpRequest postProcessRequest(MockServerHttpRequest request) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final token = Jwt(
      'token',
      headers: const {'alg': 'none'},
      claims: {'iat': now, 'exp': now + 300, ..._claims},
    );
    return _withContext(
      request,
      JwtAuthenticationToken(
        token,
        _authorities ?? const JwtGrantedAuthoritiesConverter().convert(token),
      ),
    );
  }
}
