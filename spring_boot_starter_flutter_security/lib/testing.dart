/// Test helpers for the code of a Flutter app that runs as a user:
/// `withMockUser`, `withAuthentication` and `withAnonymousUser` of
/// `spring_security_core`, re-exported so that an app's tests need no
/// other dependency than this starter.
///
/// ```dart
/// import 'package:spring_boot_starter_flutter_security/testing.dart';
///
/// test('an admin sees the orders', () async {
///   await withMockUser(() async {
///     expect(await orders.all(), isNotEmpty);
///   }, roles: ['ADMIN']);
/// });
/// ```
///
/// Spring (Java): `spring-security-test`'s `@WithMockUser`.
library;

export 'package:spring_security_core/testing.dart';
