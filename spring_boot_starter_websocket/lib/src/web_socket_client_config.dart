import 'dart:math' as math;

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The settings of one WebSocket client from
/// `spring.websocket.client.config.<name>.*`, falling back to
/// `spring.websocket.client.config.default.*`.
///
/// ```properties
/// spring.websocket.client.config.default.connect-timeout=5s
/// spring.websocket.client.config.chat.url=wss://chat.neon.books/ws
/// spring.websocket.client.config.chat.reconnect.delay=500ms
/// spring.websocket.client.config.chat.reconnect.multiplier=1.5
/// spring.websocket.client.config.chat.reconnect.max-delay=1m
/// spring.websocket.client.config.chat.reconnect.jitter=200ms
/// spring.websocket.client.config.chat.reconnect.max-retries=10
/// spring.websocket.client.config.chat.default-request-headers.X-Shop=neon
/// ```
///
/// Differs from Spring: these keys are this project's own (shaped like
/// `spring.cloud.openfeign.client.config.*`); Spring Boot has no
/// properties for WebSocket clients.
final class WebSocketClientConfig {
  /// Settings with these values.
  const WebSocketClientConfig({
    this.url,
    this.connectTimeout = const Duration(seconds: 10),
    this.reconnect = const WebSocketReconnectPolicy(),
    this.defaultRequestHeaders = const {},
  });

  /// The address (when `@WebSocketClient` has none).
  final String? url;

  /// The longest the handshake may take (`null`: no limit).
  final Duration? connectTimeout;

  /// How a lost (or failed) connection is opened again while someone
  /// listens (`reconnect.*`).
  final WebSocketReconnectPolicy reconnect;

  /// Headers sent with every handshake (not possible in browsers); a
  /// comma-separated value or a list (`X-Tag[0]`, YAML) gives several
  /// values.
  final Map<String, List<String>> defaultRequestHeaders;

  static const _prefix = 'spring.websocket.client.config.';

  /// The settings of client [name] from [environment].
  static WebSocketClientConfig of(Environment environment, String name) {
    String? get(String key) =>
        environment.getProperty('$_prefix$name.$key') ??
        environment.getProperty('${_prefix}default.$key');
    Duration? duration(String key) {
      final value = get(key);
      return value == null
          ? null
          : DefaultConversionService().convert<Duration>(value);
    }

    const defaults = WebSocketClientConfig();
    const policy = WebSocketReconnectPolicy();
    final multiplier = get('reconnect.multiplier');
    final maxRetries = get('reconnect.max-retries');
    return WebSocketClientConfig(
      url: get('url'),
      connectTimeout: duration('connect-timeout') ?? defaults.connectTimeout,
      reconnect: WebSocketReconnectPolicy(
        enabled: _flag(get('reconnect.enabled'), '$name.reconnect.enabled'),
        delay: duration('reconnect.delay') ?? policy.delay,
        multiplier: multiplier == null
            ? policy.multiplier
            : double.parse(multiplier.trim()),
        maxDelay: duration('reconnect.max-delay') ?? policy.maxDelay,
        jitter: duration('reconnect.jitter') ?? policy.jitter,
        maxRetries: maxRetries == null ? null : int.parse(maxRetries.trim()),
      ),
      defaultRequestHeaders: _merge(
        _headers(environment, '${_prefix}default.default-request-headers'),
        _headers(environment, '$_prefix$name.default-request-headers'),
      ),
    );
  }

  // A boolean like Spring Boot's binding: true / false (also on / off,
  // yes / no, 1 / 0) in any case; anything else fails.
  static bool _flag(String? value, String key) =>
      switch (value?.trim().toLowerCase()) {
        null || '' => true,
        'true' || 'on' || 'yes' || '1' => true,
        'false' || 'off' || 'no' || '0' => false,
        _ => throw FormatException(
          '$_prefix$key: failed to convert to boolean (was "$value")',
          value,
        ),
      };

  // The client's headers replace those of `default` with the same name in
  // any case (header names are case-insensitive).
  static Map<String, List<String>> _merge(
    Map<String, List<String>> defaults,
    Map<String, List<String>> own,
  ) => {
    for (final MapEntry(:key, :value) in defaults.entries)
      if (!own.keys.any((name) => name.toLowerCase() == key.toLowerCase()))
        key: value,
    ...own,
  };

  // The map of lists at [name], bound like a Spring Boot
  // `Map<String, List<String>>`: relaxed names
  // (`default-request-headers.X-Shop`, `defaultRequestHeaders.X-Shop`,
  // `default-request-headers[X.Shop]`), a comma list or indexed values
  // (`X-Shop[0]`, YAML lists) for several values.
  static Map<String, List<String>> _headers(
    Environment environment,
    String name,
  ) {
    if (environment is! ConfigurableEnvironment) {
      return const {};
    }
    final canonical = ConfigurationPropertyName.isValid(name)
        ? name
        : ConfigurationPropertyName.adapt(name, '.').toString();
    return Binder.get(environment)
        .bind(
          canonical,
          const MapType<String, List<String>>(
            ClassType<String>(),
            ListType<String>(ClassType<String>()),
          ),
        )
        .orElse(const {});
  }
}

/// How a `@WebSocketClient` opens its connection again after a loss or a
/// failed attempt, while someone listens: from
/// `spring.websocket.client.config.<name>.reconnect.*`, with the names of
/// Spring Framework 7's `RetryPolicy` (`delay`, `multiplier`,
/// `max-delay`, `jitter`, `max-retries`).
///
/// ```properties
/// spring.websocket.client.config.chat.reconnect.delay=500ms
/// spring.websocket.client.config.chat.reconnect.multiplier=2
/// spring.websocket.client.config.chat.reconnect.max-delay=30s
/// spring.websocket.client.config.chat.reconnect.jitter=100ms
/// spring.websocket.client.config.chat.reconnect.max-retries=10
/// spring.websocket.client.config.chat.reconnect.enabled=false
/// ```
///
/// Spring (Java):
/// ```java
/// RetryPolicy.builder().delay(Duration.ofMillis(500)).multiplier(2)
///     .maxDelay(Duration.ofSeconds(30)).jitter(Duration.ofMillis(100))
///     .maxRetries(10).build();
/// ```
///
/// Differs from Spring: the defaults suit reconnecting (a doubling delay
/// up to 30 s, no limit on retries) rather than `RetryPolicy`'s (a fixed
/// 1 s delay, 3 retries).
final class WebSocketReconnectPolicy {
  /// A policy with these values.
  const WebSocketReconnectPolicy({
    this.enabled = true,
    this.delay = const Duration(seconds: 1),
    this.multiplier = 2,
    this.maxDelay = const Duration(seconds: 30),
    this.jitter = Duration.zero,
    this.maxRetries,
  });

  /// Whether to reconnect at all (`reconnect.enabled`, default `true`).
  final bool enabled;

  /// The wait before the first attempt (`reconnect.delay`, default 1 s).
  final Duration delay;

  /// What each further wait is multiplied by (`reconnect.multiplier`,
  /// default 2; 1 for a fixed delay).
  final double multiplier;

  /// The longest wait (`reconnect.max-delay`, default 30 s).
  final Duration maxDelay;

  /// A random part added to or taken from each wait, scaled by the
  /// multiplier like the delay (`reconnect.jitter`, default none).
  final Duration jitter;

  /// The attempts in a row before giving up (`reconnect.max-retries`;
  /// default: no limit).
  final int? maxRetries;

  /// The wait before attempt [retry] (1 for the first), like Spring's
  /// `ExponentialBackOff`: [delay] × [multiplier]^(retry − 1), at most
  /// [maxDelay], then ± [jitter] × (that wait / [delay]), but never below
  /// [delay] nor above [maxDelay].
  Duration delayFor(int retry, [math.Random? random]) {
    final base = delay.inMicroseconds;
    final max = maxDelay.inMicroseconds;
    final grown = base * math.pow(multiplier, math.max(retry - 1, 0));
    final interval = math.min(grown, max.toDouble());
    if (jitter <= Duration.zero) {
      return Duration(microseconds: interval.round());
    }
    final applicable =
        jitter.inMicroseconds * (base == 0 ? 1 : interval / base);
    final low = math.max(interval - applicable, base.toDouble());
    final high = math.min(interval + applicable, max.toDouble());
    if (high <= low) {
      return Duration(microseconds: low.round());
    }
    final next = (random ?? _random).nextDouble();
    return Duration(microseconds: (low + next * (high - low)).round());
  }

  static final _random = math.Random();
}
