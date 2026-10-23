// Server-sent events from a real public stream: every edit on Wikipedia,
// Wikimedia Commons, Wikidata, ... as it happens
// (https://stream.wikimedia.org, no key needed).
//
// EventStream<T> is a Stream<T> of the decoded events: listen to it or
// `await for` over it; cancelling closes the connection. A lost connection
// is opened again with Last-Event-ID, so no event is missed.
//
// Spring (Java): no Feign counterpart (OpenFeign cannot stream); Spring
// reads events as Flux<ServerSentEvent<RecentChange>> from WebClient.
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@FeignClient('wikimedia', url: r'${wikimedia.url}')
abstract interface class WikimediaStreams {
  /// Wikimedia asks every client to say who it is (User-Agent).
  @GetMapping.of(
    path: '/v2/stream/recentchange',
    headers: [r'User-Agent=${wikimedia.user-agent}'],
  )
  EventStream<RecentChange> recentChanges();
}
