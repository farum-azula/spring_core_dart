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
      )..validate('$_prefix$name.reconnect'),
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

  /// Checks the values like Spring 7's `RetryPolicy.Builder`: `delay` and
  /// `jitter` not negative, `multiplier` at least 1, `max-delay` positive,
  /// `max-retries` not negative (a `delay` above `max-delay` is accepted:
  /// the waits are then [maxDelay]); throws an [ArgumentError] naming the
  /// property under [prefix] otherwise.
  void validate([String prefix = 'reconnect']) {
    void check(bool valid, Object value, String key, String message) {
      if (!valid) {
        throw ArgumentError.value(value, '$prefix.$key', message);
      }
    }

    check(!delay.isNegative, _show(delay), 'delay', 'must not be negative');
    check(!jitter.isNegative, _show(jitter), 'jitter', 'must not be negative');
    check(
      multiplier >= 1,
      multiplier,
      'multiplier',
      'must be greater than or equal to 1 (1 is a fixed delay)',
    );
    check(
      maxDelay > Duration.zero,
      _show(maxDelay),
      'max-delay',
      'must be positive',
    );
    final maxRetries = this.maxRetries;
    if (maxRetries != null) {
      check(maxRetries >= 0, maxRetries, 'max-retries', 'must not be negative');
    }
  }

  // A duration as `1m` / `500ms` style text rather than 0:01:00.000000.
  static String _show(Duration value) {
    if (value == Duration.zero) return '0s';
    final micros = value.inMicroseconds;
    for (final (unit, size) in [
      ('d', Duration.microsecondsPerDay),
      ('h', Duration.microsecondsPerHour),
      ('m', Duration.microsecondsPerMinute),
      ('s', Duration.microsecondsPerSecond),
      ('ms', Duration.microsecondsPerMillisecond),
    ]) {
      if (micros % size == 0) return '${micros ~/ size}$unit';
    }
    return '${micros}us';
  }

  /// The wait before attempt [retry] (1 for the first), like Spring's
  /// `ExponentialBackOff`: [delay] × [multiplier]^(retry − 1), at most
  /// [maxDelay], then ± [jitter] × (that wait / [delay]), but never below
  /// [delay] nor above [maxDelay] (which wins when [delay] is above it).
  /// A zero [delay] gives zero waits (± [jitter]) on every attempt.
  Duration delayFor(int retry, [math.Random? random]) {
    final base = delay.inMicroseconds;
    final max = maxDelay.inMicroseconds;
    final double interval;
    if (base == 0) {
      // 0 × multiplier^n stays 0 (and 0 × Infinity would be NaN).
      interval = 0;
    } else {
      // Once the wait reaches max-delay it stays there, also when
      // multiplier^n overflows to Infinity.
      final grown = base * math.pow(multiplier, math.max(retry - 1, 0));
      interval = grown.isFinite && grown < max ? grown.toDouble() : max * 1.0;
    }
    if (jitter <= Duration.zero) {
      return Duration(microseconds: interval.round());
    }
    final applicable =
        jitter.inMicroseconds * (base == 0 ? 1 : interval / base);
    final low = math.max(interval - applicable, base.toDouble());
    final high = math.min(interval + applicable, max.toDouble());
    if (high <= low) {
      // Only when delay is above max-delay: the maximum wins.
      return Duration(microseconds: math.min(low, high).round());
    }
    final next = (random ?? _random).nextDouble();
    return Duration(microseconds: (low + next * (high - low)).round());
  }

  static final _random = math.Random();
}
