// A @Retryable method that returns an EventStream, end to end through the
// generated proxy of app/retried_events_app.dart and the starter's
// eventStreamRetryAdapter: the caller gets an EventStream, a failed
// connection calls the method again, and the events come whole.
import 'package:spring_boot_starter_restclient/spring_auto_configuration.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../spring_gen/resilience/app/retried_events_app.spring.dart';
import 'app/retried_events_app.dart';

ApplicationContextRunner _runner(MockHttpTransport server) =>
    const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootResilienceAutoConfiguration)
        .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterRestclientResilienceAutoConfiguration,
        )
        .withBean<HttpTransport>(() => server);

void main() {
  test('the retried stream is an EventStream with the events of the call '
      'that succeeds', () async {
    final server = MockHttpTransport()
      ..when(HttpMethod.get, '/prices').respond(503)
      ..when(HttpMethod.get, '/prices').respond(503)
      ..when(HttpMethod.get, '/prices').respondEvents([
        const ServerSentEvent('41', id: '1', event: 'price'),
        const ServerSentEvent('42', id: '2', event: 'price'),
      ]);
    await _runner(server).runAsync((context) async {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<RetryStreamAdapter>());
      final feed = context.getBean<PriceFeed>();
      final prices = feed.prices();
      expect(prices, isA<EventStream<String>>());
      final events = await prices.events.toList();
      expect(
        [for (final event in events) (event.id, event.event, event.data)],
        [
          ('1', 'price', '41'),
          ('2', 'price', '42'),
        ],
      );
      expect(feed.calls, 3);
      expect(server.requests, hasLength(3));
    });
  });

  test('without the adapter bean the retried call cannot keep its type', () {
    final server = MockHttpTransport()
      ..when(HttpMethod.get, '/prices').respondEvents([
        const ServerSentEvent('41'),
      ]);
    return const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootResilienceAutoConfiguration)
        .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
        .withBean<HttpTransport>(() => server)
        .runAsync((context) async {
          expect(context, doesNotHaveBean<RetryStreamAdapter>());
          final feed = context.getBean<PriceFeed>();
          expect(feed.prices, throwsA(isA<TypeError>()));
        });
  });
}
