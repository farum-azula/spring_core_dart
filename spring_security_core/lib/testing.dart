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

/// Runs [body] as each of [usernames] at the same time, [rounds] times
/// each, and returns what every call gave, by user, in the order of the
/// rounds.
///
/// It is the test of "one user never sees another's": every call must
/// give what its own user may see, whatever the other calls do meanwhile.
/// The calls start a few turns of the event loop apart, in a pattern that
/// changes from call to call, so they overtake each other at their
/// `await`s the way requests of a busy server do. What it finds: a bean
/// that remembers the user in a field, a cache whose key has no user in
/// it, a result shared between callers, an authentication set outside
/// every scope.
///
/// ```dart
/// test('everybody gets their own orders', () async {
///   final found = await withMockUsersAtOnce(
///     ['ada', 'bob', 'eve'],
///     (username) => orders.mine(),
///   );
///   for (final MapEntry(key: username, value: results) in found.entries) {
///     for (final orders in results) {
///       expect(orders.map((o) => o.owner).toSet(), {username});
///     }
///   }
///   expect(programWideAuthentication(), isNull);
/// });
/// ```
///
/// Each call runs as [withMockUser] runs it, with [roles]. A call that
/// fails fails the whole: the error of the first one is thrown once all
/// have ended.
///
/// Differs from Spring: `spring-security-test` has nothing like it; a
/// thread per request hides the mistakes a single event loop shows.
Future<Map<String, List<T>>> withMockUsersAtOnce<T>(
  Iterable<String> usernames,
  FutureOr<T> Function(String username) body, {
  int rounds = 10,
  List<String> roles = const ['USER'],
}) async {
  final users = usernames.toList();
  if (users.toSet().length != users.length) {
    throw ArgumentError.value(usernames, 'usernames', 'A name twice');
  }
  final calls = <String, List<Future<T>>>{for (final user in users) user: []};
  var started = 0;
  for (var round = 0; round < rounds; round++) {
    for (final user in users) {
      // 0 to 3 turns of the event loop before the call, differently in
      // every round.
      final turns = (started++ * 7 + round) % 4;
      calls[user]!.add(() async {
        for (var turn = 0; turn < turns; turn++) {
          await Future<void>.delayed(Duration.zero);
        }
        return await withMockUser(
          () => body(user),
          username: user,
          roles: roles,
        );
      }());
    }
  }
  // All of them end before the first error is thrown: none is left
  // running into the next test.
  final all = [for (final list in calls.values) ...list];
  await Future.wait([
    for (final call in all) call.then<void>((_) {}, onError: (Object _) {}),
  ]);
  return {
    for (final MapEntry(key: user, value: list) in calls.entries)
      user: [for (final call in list) await call],
  };
}

/// The authentication outside every scope: who all the code that runs
/// outside a request (and outside [withMockUser]) acts as, or `null`.
///
/// On a server it is `null` unless the application means otherwise;
/// check it after a test that makes requests, or in a `tearDown`:
///
/// ```dart
/// tearDown(() => expect(programWideAuthentication(), isNull));
/// ```
///
/// With a strategy of the application's own (not the default
/// `ZoneSecurityContextHolderStrategy`) it is the authentication of the
/// current context.
Authentication? programWideAuthentication() =>
    switch (SecurityContextHolder.getContextHolderStrategy()) {
      final ZoneSecurityContextHolderStrategy zone =>
        zone.programWideAuthentication,
      final other => other.getContext().authentication,
    };
