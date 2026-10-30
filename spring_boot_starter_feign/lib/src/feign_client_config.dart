// The properties example in the documentation has lines that cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// How much a Feign client logs about its calls, set per client with the
/// `logger-level` property.
///
/// Turn it up to see what a client sends and receives while developing
/// or chasing a problem. The calls are logged under the logger
/// `feign.<Interface>` at debug level, so that level must be on too
/// (`logging.level.feign=debug`):
///
/// ```properties
/// spring.cloud.openfeign.client.config.catalog.logger-level=basic
/// logging.level.feign=debug
/// ```
///
/// Feign's counterpart is `Logger.Level`.
enum FeignLoggerLevel {
  /// Nothing; the default. Failed connections and retries are not logged
  /// either.
  none,

  /// The method and URL of each request, the status and the time of each
  /// response, failed connections and retries.
  basic,

  /// [basic] plus the headers of requests and responses, with the values
  /// of credentials shown as `***`: `Authorization`,
  /// `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `DPoP` (a proof of
  /// possession) and those of the `sensitive-headers` property
  /// ([FeignClientConfig.sensitiveHeaders]).
  headers,

  /// [headers] plus the bodies.
  full;

  /// The level for a property value such as `basic` or `FULL` (any case).
  /// Throws an [ArgumentError] for another value.
  static FeignLoggerLevel parse(String value) => values.firstWhere(
    (level) => level.name == value.trim().toLowerCase(),
    orElse: () => throw ArgumentError.value(
      value,
      'logger-level',
      'one of none, basic, headers, full',
    ),
  );
}

/// The settings of one Feign client: its URL, timeouts, logging, default
/// headers and query parameters, redirects, event-stream reconnection,
/// and the beans that retry, decode errors and intercept requests.
///
/// They come from `spring.cloud.openfeign.client.config.<name>.*`, where
/// `<name>` is the client's name (or `contextId`); what a client does not
/// set falls back to `spring.cloud.openfeign.client.config.default.*`.
/// Applications set the properties; the starter reads them with [of] when
/// it creates each client.
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
/// spring.cloud.openfeign.client.config.catalog.sensitive-headers=X-Api-Key
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
/// and `sensitive-headers` are additions of this starter: Spring Cloud
/// OpenFeign cannot stream, and its logger masks no header.
/// Spring's counterpart is `FeignClientProperties`.
final class FeignClientConfig {
  /// Settings with these values; the defaults are those of a client
  /// without any property.
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
    this.sensitiveHeaders = const [],
  });

  /// The base URL of the client (`url`), used when `@FeignClient` has
  /// none; `null` when not set.
  final String? url;

  /// The `read-timeout` when none is set: 60 seconds, as in Feign's
  /// `Request.Options()`.
  static const defaultReadTimeout = Duration(seconds: 60);

  /// The `connect-timeout` when none is set: 10 seconds, as in Feign's
  /// `Request.Options()`.
  static const defaultConnectTimeout = Duration(seconds: 10);

  /// The longest wait for data (`read-timeout`): for the response after
  /// the request was sent, then between two chunks of the body. It is not
  /// a limit for the whole call, as in Feign. 60 seconds by default;
  /// `null` (the property set to `0`) waits forever. For an event stream
  /// it covers the wait for the response only.
  final Duration? readTimeout;

  /// How much the client logs (`logger-level`); nothing by default.
  final FeignLoggerLevel loggerLevel;

  /// Whether a 404 gives `null` (nullable results) or a `ResponseEntity`
  /// instead of an exception (`dismiss404`, `false` by default); `void`
  /// methods still throw, as in Feign. `@FeignClient(dismiss404: true)`
  /// turns it on too.
  final bool dismiss404;

  /// Headers sent with every request that has none of that name once the
  /// interceptors ran (`default-request-headers.<name>`), such as a shop
  /// id every call of a client carries. A comma-separated value or a list
  /// gives several values. The client's entries add to those of
  /// `default`, and win for the same name.
  final Map<String, List<String>> defaultRequestHeaders;

  /// Query parameters added to every request that has none of that name
  /// once the interceptors ran (`default-query-parameters.<name>`), such
  /// as a language or an API key. A comma-separated value or a list gives
  /// several. The client's entries add to those of `default`, and win for
  /// the same name.
  ///
  /// The URL with its query is in the log lines (`logger-level` `basic`
  /// and up) and in the messages of `FeignException`s and
  /// `RetryableException`s, so an API key sent here shows there: prefer a
  /// header named in [sensitiveHeaders] (through `default-request-headers`)
  /// for a secret.
  final Map<String, List<String>> defaultQueryParameters;

  /// Whether the transport follows redirects (`follow-redirects`); `true`
  /// by default. With `false`, a 3xx answer is an error status.
  final bool followRedirects;

  /// Whether a `/` in a `@PathVariable` value stays a `/` instead of
  /// `%2F` (`spring.cloud.openfeign.client.decode-slash`, one setting for
  /// all clients); `true` by default.
  final bool decodeSlash;

  /// Whether an event stream connects again after its connection ended or
  /// broke (`event-stream.reconnect`); `true` by default, as a browser's
  /// `EventSource` does.
  final bool eventStreamReconnect;

  /// The wait before connecting again (`event-stream.reconnect-delay`), 3
  /// seconds by default; a `retry:` field sent by the server replaces it.
  final Duration eventStreamReconnectDelay;

  /// How many connections in a row may end without an event before the
  /// stream gives up (`event-stream.max-attempts`); `null`, the default,
  /// for no limit.
  final int? eventStreamMaxAttempts;

  /// The `Retryer` bean of the client (`retryer`), named by bean name or
  /// class name; it wins over the one of the client's configuration
  /// classes and the application's. `null` when not set.
  final String? retryer;

  /// The `ErrorDecoder` bean of the client (`error-decoder`), named by
  /// bean name or class name; it wins over the others like [retryer].
  /// `null` when not set.
  final String? errorDecoder;

  /// More `RequestInterceptor` beans for the client
  /// (`request-interceptors`), by bean name or class name: those listed
  /// under `default`, then those of the client. They run after the
  /// interceptors the client has anyway.
  final List<String> requestInterceptors;

  /// More headers whose values the `headers` and `full` logs show as `***`
  /// (`sensitive-headers`, names in any case), such as an API key header:
  /// those listed under `default`, then those of the client. The headers
  /// of [alwaysSensitiveHeaders] always are.
  final List<String> sensitiveHeaders;

  /// The headers whose values the logs always show as `***`, in lower
  /// case: `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`
  /// and `DPoP`.
  static const alwaysSensitiveHeaders = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'dpop',
  };

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

  /// Reads the settings of the client whose configuration key is [name]
  /// from [environment], with `default` for what it does not set.
  ///
  /// Throws a [FormatException] for an on/off property that is not
  /// `true`/`false` (or `on`/`off`, `yes`/`no`, `1`/`0`) or a
  /// `max-attempts` that is not a number, and an [ArgumentError] for an
  /// unknown `logger-level`.
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
      sensitiveHeaders: [
        ..._list(environment, '${_prefix}default.sensitive-headers'),
        ..._list(environment, '$_prefix$name.sensitive-headers'),
      ],
    );
  }

  /// The connection timeout of the default transport, one setting for all
  /// clients (`spring.cloud.openfeign.client.config.default.connect-timeout`):
  /// [defaultConnectTimeout] when it is not set, `null` (no timeout) when
  /// it is `0`.
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
