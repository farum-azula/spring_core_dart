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
/// spring.cloud.openfeign.client.config.catalog.default-query-parameters.lang=en
/// spring.cloud.openfeign.client.config.catalog.follow-redirects=false
/// spring.cloud.openfeign.client.config.orders.event-stream.reconnect-delay=1s
/// spring.cloud.openfeign.client.decode-slash=false
/// ```
///
/// The `event-stream.*` keys (reconnection of `EventStream<T>` methods)
/// are additions of this starter: Spring Cloud OpenFeign cannot stream.
final class FeignClientConfig {
  /// Settings with these values.
  const FeignClientConfig({
    this.url,
    this.readTimeout = defaultReadTimeout,
    this.loggerLevel = FeignLoggerLevel.none,
    this.dismiss404 = false,
    this.defaultRequestHeaders = const {},
    this.defaultQueryParameters = const {},
    this.followRedirects = true,
    this.decodeSlash = true,
    this.eventStreamReconnect = true,
    this.eventStreamReconnectDelay = const Duration(seconds: 3),
    this.eventStreamMaxAttempts,
  });

  /// The base URL (when `@FeignClient` has none).
  final String? url;

  /// The default `read-timeout`: 60 s, like Feign's `Request.Options()`.
  static const defaultReadTimeout = Duration(seconds: 60);

  /// The default `connect-timeout`: 10 s, like Feign's `Request.Options()`.
  static const defaultConnectTimeout = Duration(seconds: 10);

  /// The longest wait for data: for the response after the request was
  /// sent, then between two chunks of the body — not a limit for the whole
  /// call, like Feign's read timeout (`read-timeout`, default 60 s; `0`:
  /// none). For an event stream it covers the wait for the response only.
  final Duration? readTimeout;

  /// What is logged.
  final FeignLoggerLevel loggerLevel;

  /// Whether a 404 gives `null` (nullable results) or a `ResponseEntity`
  /// instead of an exception; `void` methods still throw, like Feign.
  /// `@FeignClient(dismiss404: true)` turns it on too.
  final bool dismiss404;

  /// Headers sent with every request that has none of that name after the
  /// interceptors ran.
  final Map<String, String> defaultRequestHeaders;

  /// Query parameters added to every request that has none of that name
  /// after the interceptors ran (`default-query-parameters.<name>`; a
  /// comma-separated value gives several).
  final Map<String, List<String>> defaultQueryParameters;

  /// Whether redirects are followed (`follow-redirects`, default `true`).
  final bool followRedirects;

  /// Whether a `/` in a `@PathVariable` value stays a `/` instead of
  /// `%2F` (`spring.cloud.openfeign.client.decode-slash`, for all clients;
  /// default `true`).
  final bool decodeSlash;

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
    final queries = <String, String>{
      ..._headers(environment, '${_prefix}default.default-query-parameters.'),
      ..._headers(environment, '$_prefix$name.default-query-parameters.'),
    };
    final readTimeout = duration('read-timeout') ?? defaultReadTimeout;
    return FeignClientConfig(
      url: get('url'),
      readTimeout: readTimeout == Duration.zero ? null : readTimeout,
      loggerLevel: level == null
          ? FeignLoggerLevel.none
          : FeignLoggerLevel.parse(level),
      dismiss404: get('dismiss404')?.trim().toLowerCase() == 'true',
      defaultRequestHeaders: headers,
      defaultQueryParameters: {
        for (final MapEntry(:key, :value) in queries.entries)
          key: [for (final item in value.split(',')) item.trim()],
      },
      followRedirects: get('follow-redirects')?.trim().toLowerCase() != 'false',
      decodeSlash:
          environment
              .getProperty('spring.cloud.openfeign.client.decode-slash')
              ?.trim()
              .toLowerCase() !=
          'false',
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
  /// (`spring.cloud.openfeign.client.config.default.connect-timeout`;
  /// [defaultConnectTimeout] when it is not set, `0` for none).
  static Duration? connectTimeout(Environment environment) {
    final value = environment.getProperty('${_prefix}default.connect-timeout');
    final timeout = value == null
        ? defaultConnectTimeout
        : DefaultConversionService().convert<Duration>(value);
    return timeout == Duration.zero ? null : timeout;
  }

  // The entries under [prefix] with relaxed names, like Boot's map
  // binding: `default-request-headers.X-Shop`,
  // `defaultRequestHeaders.X-Shop` or `default-request-headers[X.Shop]`;
  // the first source with an entry wins.
  static Map<String, String> _headers(Environment environment, String prefix) {
    final result = <String, String>{};
    if (environment is! ConfigurableEnvironment) {
      return result;
    }
    final parent = ConfigurationPropertyName.adapt(prefix, '.');
    for (final source in environment.propertySources) {
      if (source is! EnumerablePropertySource<Object>) {
        continue;
      }
      final names = ConfigurationPropertySources.propertyNames(source);
      for (final MapEntry(key: name, value: keys) in names.entries) {
        if (parent.isAncestorOf(name)) {
          final header = [
            for (
              var i = parent.numberOfElements;
              i < name.numberOfElements;
              i++
            )
              name.getElement(i),
          ].join('.');
          result.putIfAbsent(
            header,
            () => environment.getProperty(keys.first) ?? '',
          );
        }
      }
    }
    return result;
  }
}
