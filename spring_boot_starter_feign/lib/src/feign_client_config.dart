import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How much a Feign client logs (Feign's `Logger.Level`), under the logger
/// `feign.<Interface>` at debug level.
enum FeignLoggerLevel {
  /// Nothing.
  none,

  /// Method, URL, status and time.
  basic,

  /// [basic] plus the headers.
  headers,

  /// [headers] plus the bodies.
  full;

  /// The level for a property value such as `basic` or `FULL`.
  static FeignLoggerLevel parse(String value) => values.firstWhere(
    (level) => level.name == value.trim().toLowerCase(),
    orElse: () => throw ArgumentError.value(
      value,
      'logger-level',
      'one of none, basic, headers, full',
    ),
  );
}

/// The settings of one Feign client from
/// `spring.cloud.openfeign.client.config.<name>.*`, falling back to
/// `spring.cloud.openfeign.client.config.default.*`, like Spring Cloud
/// OpenFeign's `FeignClientProperties`.
///
/// ```properties
/// spring.cloud.openfeign.client.config.default.read-timeout=10s
/// spring.cloud.openfeign.client.config.catalog.url=https://api.neon.books
/// spring.cloud.openfeign.client.config.catalog.logger-level=basic
/// spring.cloud.openfeign.client.config.catalog.dismiss404=true
/// spring.cloud.openfeign.client.config.catalog.default-request-headers.X-Shop=neon
/// spring.cloud.openfeign.client.config.orders.event-stream.reconnect-delay=1s
/// ```
///
/// The `event-stream.*` keys (reconnection of `EventStream<T>` methods)
/// are additions of this starter: Spring Cloud OpenFeign cannot stream.
final class FeignClientConfig {
  /// Settings with these values.
  const FeignClientConfig({
    this.url,
    this.readTimeout,
    this.loggerLevel = FeignLoggerLevel.none,
    this.dismiss404 = false,
    this.defaultRequestHeaders = const {},
    this.eventStreamReconnect = true,
    this.eventStreamReconnectDelay = const Duration(seconds: 3),
    this.eventStreamMaxAttempts,
  });

  /// The base URL (when `@FeignClient` has none).
  final String? url;

  /// The longest a call may take, reading the response included.
  final Duration? readTimeout;

  /// What is logged.
  final FeignLoggerLevel loggerLevel;

  /// Whether a 404 gives `null` (nullable or `void` results) instead of an
  /// exception.
  final bool dismiss404;

  /// Headers sent with every request.
  final Map<String, String> defaultRequestHeaders;

  /// Whether an event stream connects again after its connection ended or
  /// broke (`event-stream.reconnect`, default `true`).
  final bool eventStreamReconnect;

  /// The wait before reconnecting, until the server sends `retry:`
  /// (`event-stream.reconnect-delay`, default 3 s).
  final Duration eventStreamReconnectDelay;

  /// The connections in a row without an event before an event stream
  /// gives up (`event-stream.max-attempts`; default: no limit).
  final int? eventStreamMaxAttempts;

  static const _prefix = 'spring.cloud.openfeign.client.config.';

  /// The settings of client [name] from [environment].
  static FeignClientConfig of(Environment environment, String name) {
    String? get(String key) =>
        environment.getProperty('$_prefix$name.$key') ??
        environment.getProperty('${_prefix}default.$key');
    Duration? duration(String key) {
      final value = get(key);
      return value == null
          ? null
          : DefaultConversionService().convert<Duration>(value);
    }

    final level = get('logger-level');
    final headers = <String, String>{
      ..._headers(environment, '${_prefix}default.default-request-headers.'),
      ..._headers(environment, '$_prefix$name.default-request-headers.'),
    };
    return FeignClientConfig(
      url: get('url'),
      readTimeout: duration('read-timeout'),
      loggerLevel: level == null
          ? FeignLoggerLevel.none
          : FeignLoggerLevel.parse(level),
      dismiss404: get('dismiss404')?.trim().toLowerCase() == 'true',
      defaultRequestHeaders: headers,
      eventStreamReconnect:
          get('event-stream.reconnect')?.trim().toLowerCase() != 'false',
      eventStreamReconnectDelay:
          duration('event-stream.reconnect-delay') ??
          const Duration(seconds: 3),
      eventStreamMaxAttempts: switch (get('event-stream.max-attempts')) {
        final value? => int.parse(value.trim()),
        null => null,
      },
    );
  }

  /// The connection timeout of the default transport
  /// (`spring.cloud.openfeign.client.config.default.connect-timeout`).
  static Duration? connectTimeout(Environment environment) {
    final value = environment.getProperty('${_prefix}default.connect-timeout');
    return value == null
        ? null
        : DefaultConversionService().convert<Duration>(value);
  }

  static Map<String, String> _headers(Environment environment, String prefix) {
    final result = <String, String>{};
    if (environment is! ConfigurableEnvironment) {
      return result;
    }
    for (final source in environment.propertySources) {
      if (source is! EnumerablePropertySource) {
        continue;
      }
      for (final key in source.propertyNames) {
        if (key.startsWith(prefix) && key.length > prefix.length) {
          final header = key.substring(prefix.length);
          result.putIfAbsent(header, () => environment.getProperty(key) ?? '');
        }
      }
    }
    return result;
  }
}
