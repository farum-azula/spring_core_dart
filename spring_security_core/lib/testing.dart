/// Test support for method security, like Spring's `@WithMockUser`:
/// run code as a user.
///
/// ```dart
/// import 'package:spring_security_core/testing.dart';
///
/// test('admins cancel any order', () async {
///   await withMockUser(() => orders.cancel(order), roles: ['ADMIN']);
/// });
/// ```
library;

import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';

/// Runs [body] as a user named [username] (`user`) with [roles] (`USER`)
/// or [authorities], in its own security context scope, like Spring's
/// `@WithMockUser`. The principal is a `User`.
Future<T> withMockUser<T>(
  FutureOr<T> Function() body, {
  String username = 'user',
  List<String> roles = const ['USER'],
  List<String>? authorities,
}) {
  final builder = User.withUsername(username).password('password');
  final user = authorities == null
      ? builder.roles(roles).build()
      : builder.authorityNames(authorities).build();
  return withAuthentication(
    body,
    UsernamePasswordAuthenticationToken.authenticated(
      user,
      user.password,
      user.authorities,
    ),
  );
}

/// Runs [body] with [authentication] as the current user, like Spring's
/// `@WithSecurityContext`.
Future<T> withAuthentication<T>(
  FutureOr<T> Function() body,
  Authentication authentication,
) => SecurityContextHolder.runWithContext(
  () async => await body(),
  SecurityContextImpl(authentication),
);

/// Runs [body] as an anonymous user, like Spring's `@WithAnonymousUser`.
Future<T> withAnonymousUser<T>(FutureOr<T> Function() body) =>
    withAuthentication(
      body,
      AnonymousAuthenticationToken(
        'key',
        'anonymousUser',
        AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
      ),
    );
