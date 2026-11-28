// The web starter's part in the retries: with the resilience module, the
// eventStreamRetryAdapter keeps a retried EventStream an EventStream; one
// declared by the application (or the RestClient starter) wins.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

void main() {
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootResilienceAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebResilienceAutoConfiguration);

  test('the adapter is a RetryStreamAdapter bean', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(
        context.getBean<RetryStreamAdapter>(),
        isA<EventStreamRetryAdapter>(),
      );
    });
  });

  test('one declared before it makes it back off', () {
    runner
        .withBean<EventStreamRetryAdapter>(
          () => const EventStreamRetryAdapter(),
        )
        .run((context) {
          expect(
            context.getBeanNamesForType<EventStreamRetryAdapter>(),
            hasLength(1),
          );
        });
  });
}
