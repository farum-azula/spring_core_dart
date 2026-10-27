/// Test support for the security starter, like `spring-security-test`:
/// request post-processors for `MockMvc`.
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

/// The request is made by [username] (password `password`, role `USER`
/// unless set), like Spring's `user("ada")`; skips the login itself.
UserRequestPostProcessor user(String username) =>
    UserRequestPostProcessor._(username);

/// A user for a request: change [roles], [authorities], [password].
final class UserRequestPostProcessor implements RequestPostProcessor {
  UserRequestPostProcessor._(this._username);

  final String _username;
  String _password = 'password';
  List<GrantedAuthority> _authorities = [SimpleGrantedAuthority('ROLE_USER')];

  /// The roles (without `ROLE_`).
  UserRequestPostProcessor roles(List<String> roles) {
    _authorities = User.withUsername('x').roles(roles).build().authorities;
    return this;
  }

  /// The authorities.
  UserRequestPostProcessor authorities(List<String> authorities) {
    _authorities = AuthorityUtils.createAuthorityList(authorities);
    return this;
  }

  /// The password.
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

/// The request is made by [user].
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

/// The request is made with [authentication].
RequestPostProcessor authentication(Authentication authentication) =>
    FunctionRequestPostProcessor(
      (request) => _withContext(request, authentication),
    );

/// The request is made by an anonymous user.
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

/// `Authorization: Basic` with [username] and [password] (the real login
/// runs).
RequestPostProcessor httpBasic(String username, String password) =>
    FunctionRequestPostProcessor((request) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Basic ${base64.encode(utf8.encode('$username:$password'))}',
      );
      return request;
    });

/// A valid CSRF token, like Spring's `csrf()`; `useInvalidToken` for a
/// wrong one.
CsrfRequestPostProcessor csrf() => CsrfRequestPostProcessor._();

/// A CSRF token for a request.
final class CsrfRequestPostProcessor implements RequestPostProcessor {
  CsrfRequestPostProcessor._();

  bool _valid = true;

  /// A wrong token (the request should be refused).
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

/// The request carries a verified JWT (no decoding), like Spring's
/// `jwt()`: subject `user`, scope `read` unless set.
JwtRequestPostProcessor jwt() => JwtRequestPostProcessor._();

/// A JWT for a request.
final class JwtRequestPostProcessor implements RequestPostProcessor {
  JwtRequestPostProcessor._();

  final _claims = <String, Object?>{'sub': 'user', 'scope': 'read'};
  List<GrantedAuthority>? _authorities;

  /// Sets the claim [name].
  JwtRequestPostProcessor claim(String name, Object? value) {
    _claims[name] = value;
    return this;
  }

  /// The subject.
  JwtRequestPostProcessor subject(String subject) => claim('sub', subject);

  /// The authorities (instead of those of the `scope` claim).
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
