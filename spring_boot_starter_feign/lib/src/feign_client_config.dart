// The properties example in the documentation has lines that cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

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
/// spring.cloud.openfeign.client.config.catalog.default-query-parameters.lang=en,de
/// spring.cloud.openfeign.client.config.catalog.retryer=catalogRetryer
/// spring.cloud.openfeign.client.config.catalog.error-decoder=catalogErrors
/// spring.cloud.openfeign.client.config.catalog.request-interceptors[0]=audit
/// spring.cloud.openfeign.client.config.catalog.follow-redirects=false
/// spring.cloud.openfeign.client.config.orders.event-stream.reconnect-delay=1s
/// spring.cloud.openfeign.client.decode-slash=false
/// ```
///
/// `default-request-headers` and `default-query-parameters` are maps of
/// lists, like Spring's `Map<String, Collection<String>>`: `X: a,b` or a
/// YAML list (`X[0]`, `X[1]`) gives two values.
///
/// `retryer`, `error-decoder` and `request-interceptors` name beans (Spring
/// takes class names and creates the class when there is no bean of it):
/// a bean name, or a class name (`com.example.AuditInterceptor` or
/// `AuditInterceptor`) matching the type of exactly one bean.
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
    this.retryer,
    this.errorDecoder,
    this.requestInterceptors = const [],
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
  /// interceptors ran (`default-request-headers.<name>`; a comma-separated
  /// value or a list gives several values).
  final Map<String, List<String>> defaultRequestHeaders;

  /// Query parameters added to every request that has none of that name
  /// after the interceptors ran (`default-query-parameters.<name>`; a
  /// comma-separated value or a list gives several).
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

  /// The `Retryer` bean of the client (`retryer`: a bean or class name),
  /// instead of the one of its configuration classes or the application.
  final String? retryer;

  /// The `ErrorDecoder` bean of the client (`error-decoder`: a bean or
  /// class name).
  final String? errorDecoder;

  /// `RequestInterceptor` beans added for the client
  /// (`request-interceptors`: bean or class names; those of `default` and
  /// of the client).
  final List<String> requestInterceptors;

  static const _prefix = 'spring.cloud.openfeign.client.config.';

  // A boolean property like Boot's binding: true / false (also on / off,
  // yes / no, 1 / 0) in any case; anything else fails.
  static bool _flag(String? value, String key, {required bool defaultValue}) =>
      switch (value?.trim().toLowerCase()) {
        null || '' => defaultValue,
        'true' || 'on' || 'yes' || '1' => true,
        'false' || 'off' || 'no' || '0' => false,
        _ => throw FormatException(
          '$key: failed to convert to boolean (was "$value")',
          value,
        ),
      };

  /// The settings of client [name] from [environment].
  static FeignClientConfig of(Environment environment, String name) {
    String? get(String key) =>
        environment.getProperty('$_prefix$name.$key') ??
        environment.getProperty('${_prefix}default.$key');
    bool flag(String key, {required bool defaultValue}) {
      final own = environment.getProperty('$_prefix$name.$key');
      return _flag(
        own ?? environment.getProperty('${_prefix}default.$key'),
        own != null ? '$_prefix$name.$key' : '${_prefix}default.$key',
        defaultValue: defaultValue,
      );
    }

    Duration? duration(String key) {
      final value = get(key);
      return value == null
          ? null
          : DefaultConversionService().convert<Duration>(value);
    }

    final level = get('logger-level');
    final headers = <String, List<String>>{
      ..._lists(environment, '${_prefix}default.default-request-headers'),
      ..._lists(environment, '$_prefix$name.default-request-headers'),
    };
    final queries = <String, List<String>>{
      ..._lists(environment, '${_prefix}default.default-query-parameters'),
      ..._lists(environment, '$_prefix$name.default-query-parameters'),
    };
    String? bean(String key) => switch (get(key)?.trim()) {
      final value? when value.isNotEmpty => value,
      _ => null,
    };
    final readTimeout = duration('read-timeout') ?? defaultReadTimeout;
    return FeignClientConfig(
      url: get('url'),
      readTimeout: readTimeout == Duration.zero ? null : readTimeout,
      loggerLevel: level == null
          ? FeignLoggerLevel.none
          : FeignLoggerLevel.parse(level),
      dismiss404: flag('dismiss404', defaultValue: false),
      defaultRequestHeaders: headers,
      defaultQueryParameters: queries,
      followRedirects: flag('follow-redirects', defaultValue: true),
      decodeSlash: _flag(
        environment.getProperty('spring.cloud.openfeign.client.decode-slash'),
        'spring.cloud.openfeign.client.decode-slash',
        defaultValue: true,
      ),
      eventStreamReconnect: flag('event-stream.reconnect', defaultValue: true),
      eventStreamReconnectDelay:
          duration('event-stream.reconnect-delay') ??
          const Duration(seconds: 3),
      eventStreamMaxAttempts: switch (get('event-stream.max-attempts')) {
        final value? => int.parse(value.trim()),
        null => null,
      },
      retryer: bean('retryer'),
      errorDecoder: bean('error-decoder'),
      requestInterceptors: [
        ..._list(environment, '${_prefix}default.request-interceptors'),
        ..._list(environment, '$_prefix$name.request-interceptors'),
      ],
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

  // The map of lists at [name], bound like Spring Cloud OpenFeign's
  // `Map<String, Collection<String>>`: relaxed names
  // (`default-request-headers.X-Shop`, `defaultRequestHeaders.X-Shop`,
  // `default-request-headers[X.Shop]`), a comma list or indexed values
  // (`X-Shop[0]`, YAML lists) for several values.
  static Map<String, List<String>> _lists(
    Environment environment,
    String name,
  ) {
    if (environment is! ConfigurableEnvironment) {
      return const {};
    }
    return Binder.get(environment)
        .bind(
          _canonical(name),
          const MapType<String, List<String>>(
            ClassType<String>(),
            ListType<String>(ClassType<String>()),
          ),
        )
        .orElse(const {});
  }

  // The list at [name] (a comma list or indexed values).
  static List<String> _list(Environment environment, String name) {
    if (environment is! ConfigurableEnvironment) {
      return switch (environment.getProperty(name)) {
        final value? => [
          for (final item in value.split(','))
            if (item.trim().isNotEmpty) item.trim(),
        ],
        null => const [],
      };
    }
    return Binder.get(environment)
        .bind(_canonical(name), const ListType<String>(ClassType<String>()))
        .orElse(const []);
  }

  // [name] as a canonical property name (a client name may have upper
  // case letters).
  static String _canonical(String name) =>
      ConfigurationPropertyName.isValid(name)
      ? name
      : ConfigurationPropertyName.adapt(name, '.').toString();
}
