// An application whose @Retryable method returns an EventStream read by a
// RestClient: the generator writes the proxy (retried_events_app.spring.dart,
// from `dart run build_runner build`) with spring.resilience.enabled: true.
import 'dart:async';

import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

import '../../spring_gen/resilience/app/retried_events_app.spring.dart';

const _quick = Duration(milliseconds: 1);

/// The prices of a feed, read as server-sent events.
@Service()
class PriceFeed {
  PriceFeed(RestClientBuilder builder)
    : _rest = builder.baseUrl('http://prices.test').build();

  final RestClient _rest;

  /// How many times [prices] was called.
  int calls = 0;

  /// The feed's events; a failed connection calls the method again.
  @Retryable(delay: _quick, maxRetries: 2)
  EventStream<String> prices() {
    calls++;
    return _rest
        .get()
        .uri('/prices')
        .retrieve()
        .eventStream<String>(reconnect: SseReconnect.never);
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
