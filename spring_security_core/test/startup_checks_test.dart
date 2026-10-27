// What the context checks at startup and by default: every security
// expression of a bean is parsed before the application runs, a bean is
// recognized as secured even when its methods carry other annotations too,
// and password checks leave the caller's isolate unless told not to.
import 'dart:isolate';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_security_core/spring_auto_configuration.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:test/test.dart';

ApplicationContextRunner _runner() => const ApplicationContextRunner()
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springSecurityCoreAutoConfiguration)
    .withPropertyValues(['logging.level.root=warn']);

class _Service {
  void delete() {}
}

const _otherAnnotation = Deprecated('another annotation on the method');

MethodSignature _signature(List<Object> annotations) => MethodSignature(
  name: 'delete',
  declaringType: '_Service',
  targetType: '_Service',
  annotations: annotations,
);

/// An encoder that matches only off the isolate that made it.
final class _OffIsolateOnly implements PasswordEncoder {
  _OffIsolateOnly() : home = Isolate.current.controlPort;

  final SendPort home;

  @override
  String encode(String rawPassword) => rawPassword;

  @override
  bool matches(String rawPassword, String? encodedPassword) =>
      Isolate.current.controlPort != home && rawPassword == encodedPassword;

  @override
  bool upgradeEncoding(String? encodedPassword) => false;
}

void main() {
  test('a broken expression fails the startup, before any call', () async {
    const broken = PreAuthorize('hasRole(');
    await _runner()
        .withUserConfiguration(
          BeanModule('broken', [
            BeanDefinition<_Service>(
              name: 'service',
              create: (_) => _Service(),
              annotatedMethods: [
                BeanMethod<_Service>(
                  'delete',
                  invoke: (bean, _) => bean.delete(),
                  annotations: const [broken],
                ),
              ],
              aopProxy: AopProxyFactory.unavailable(
                signatures: [
                  _signature(const [broken]),
                ],
                reason: 'not reached: the expression fails first',
              ),
            ),
          ]),
        )
        .runAsync((context) async {
          final failure = '${context.startupFailure}';
          expect(context.startupFailure, isNotNull);
          expect(failure, isNot(contains('not reached')));
          expect(failure, isNot(contains('no proxy')));
        });
  });

  test('a method with method security and other annotations is secured: '
      'without a proxy the startup fails', () async {
    await _runner()
        .withUserConfiguration(
          BeanModule('unproxied', [
            BeanDefinition<_Service>(
              name: 'service',
              create: (_) => _Service(),
              annotatedMethods: [
                BeanMethod<_Service>(
                  'delete',
                  invoke: (bean, _) => bean.delete(),
                  annotations: const [
                    _otherAnnotation,
                    PreAuthorize("hasRole('ADMIN')"),
                  ],
                ),
              ],
            ),
          ]),
        )
        .runAsync((context) async {
          expect(
            '${context.startupFailure}',
            contains('has method security annotations but no proxy'),
          );
        });
  });

  test('by default the password is checked on another isolate', () async {
    final provider = DaoAuthenticationProvider(
      InMemoryUserDetailsManager([
        User.withUsername('ada').password('secret').build(),
      ]),
      passwordEncoder: _OffIsolateOnly(),
    );
    final result = await provider.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
    );
    expect(result!.isAuthenticated, isTrue);

    final local = DaoAuthenticationProvider(
      InMemoryUserDetailsManager([
        User.withUsername('ada').password('secret').build(),
      ]),
      passwordEncoder: _OffIsolateOnly(),
      offloadPasswordChecks: false,
    );
    await expectLater(
      local.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
      ),
      throwsA(isA<BadCredentialsException>()),
    );
  });
}
