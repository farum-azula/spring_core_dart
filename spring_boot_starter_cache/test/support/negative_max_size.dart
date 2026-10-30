// Run by caches_test.dart without assertions, as a released app runs: a
// negative max size (or time to live) must be refused when the cache is
// created. Before, the first put looped for ever (a negative time to live
// kept nothing). Exits with 1 if a cache accepts one.
import 'dart:io';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';

void main() {
  // Not a constant, so the analyzer cannot refuse it.
  final negative = int.parse('-1');
  final attempts = <String, void Function()>{
    'InMemoryCache': () =>
        InMemoryCache('books', spec: CacheSpec(maxSize: negative)),
    'defaultSpec': () =>
        InMemoryCacheManager(defaultSpec: CacheSpec(maxSize: negative)),
    'specFor': () => InMemoryCacheManager(
      specFor: (_) => CacheSpec(maxSize: negative),
    ).getCache('prices'),
    // A negative time to live kept nothing; Caffeine refuses one too.
    'InMemoryCache timeToLive': () => InMemoryCache(
      'books',
      spec: CacheSpec(timeToLive: Duration(seconds: negative)),
    ),
    'specFor timeToLive': () => InMemoryCacheManager(
      specFor: (_) => CacheSpec(timeToLive: Duration(seconds: negative)),
    ).getCache('prices'),
  };
  for (final MapEntry(key: what, value: attempt) in attempts.entries) {
    try {
      attempt();
    } on ArgumentError catch (error) {
      stdout.writeln('$what: $error');
      continue;
    }
    stdout.writeln('$what accepted a negative limit');
    exit(1);
  }
}
