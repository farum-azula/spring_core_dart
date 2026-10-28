/// Helpers for tests of secured code: run a piece of code as a given user,
/// so `@PreAuthorize` and its siblings see that user.
///
/// Import it in tests only. Each helper opens its own security context
/// scope, so tests running at the same time do not see each other's user,
/// and the user is gone when the helper's `Future` completes.
///
/// ```dart
/// import 'package:spring_security_core/testing.dart';
///
/// test('admins cancel any order', () async {
///   await withMockUser(() => orders.cancel(order), roles: ['ADMIN']);
/// });
///
/// test('users cannot cancel orders of others', () async {
///   await expectLater(
///     withMockUser(() => orders.cancel(othersOrder)),
///     throwsA(isA<AccessDeniedException>()),
///   );
/// });
/// ```
///
/// Spring (Java): `@WithMockUser`, `@WithAnonymousUser` and
/// `@WithSecurityContext` annotations on test methods.
library;

import 'dart:async';

import 'package:spring_security_core/spring_security_core.dart';

/// Runs [body] as a logged-in user and returns its result.
///
/// The user is named [username] (`user` by default), with the password
/// `password`, and has the roles [roles] (`USER` by default, giving
/// `ROLE_USER`). Pass [authorities] instead to give full authority names
/// (`SCOPE_read`); then [roles] is ignored. The principal is a `User`, so
/// `principal.username` works in expressions.
///
/// Spring (Java): `@WithMockUser(username = "ada", roles = "ADMIN")`.
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

/// Runs [body] with [authentication] as the current user and returns its
/// result.
///
/// Use it when the test needs a specific principal, such as your own
/// `UserDetails` class or a JWT token.
///
/// Spring (Java): `@WithSecurityContext`.
Future<T> withAuthentication<T>(
  FutureOr<T> Function() body,
  Authentication authentication,
) => SecurityContextHolder.runWithContext(
  () async => await body(),
  SecurityContextImpl(authentication),
);

/// Runs [body] as an anonymous user (`anonymousUser` with
/// `ROLE_ANONYMOUS`), as the web starter sets for a request without a
/// login, and returns its result.
///
/// Spring (Java): `@WithAnonymousUser`.
Future<T> withAnonymousUser<T>(FutureOr<T> Function() body) =>
    withAuthentication(
      body,
      AnonymousAuthenticationToken(
        'key',
        'anonymousUser',
        AuthorityUtils.createAuthorityList(['ROLE_ANONYMOUS']),
      ),
    );
