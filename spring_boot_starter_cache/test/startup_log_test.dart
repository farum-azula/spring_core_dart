// The starter's own beans start quietly: the validator of the annotations
// (a BeanPostProcessor) asks for the interceptor only when it checks the
// first cached bean, so the interceptor is not created ahead of the other
// post-processors (which the context reports as "not eligible for getting
// processed by all BeanPostProcessors").
import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'books.dart';

void main() {
  final logs = captureLogs(level: SpringLogLevel.info);

  test('no bean of the starter is created too early', () async {
    await const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterCacheAutoConfiguration)
        .withUserConfiguration(
          BeanModule('app', [
            BeanDefinition<Books>(
              name: 'books',
              create: (_) => Books(),
              aopProxy: booksProxyFactory,
            ),
          ]),
        )
        .runAsync((context) async {
          expect(context.startupFailure, isNull);
          expect(
            logs.messages.where((m) => m.contains('not eligible')),
            isEmpty,
          );
          // The validator still checks, and the cache still works.
          final books = context.getBean<Books>()
            ..find('1')
            ..find('1');
          expect(books.count('find'), 1);
        });
  });

  test('the validator made with an interceptor still validates', () {
    final interceptor = CacheInterceptor();
    expect(
      identical(CacheOperationValidator(interceptor).interceptor, interceptor),
      isTrue,
    );
  });
}
