import 'package:spring_boot_starter_feign/src/config/feign_properties.dart';

/// How much a Feign client logs about its calls, set per client with the
/// `logger-level` property.
///
/// Turn it up to see what a client sends and receives while developing
/// or chasing a problem. The calls are logged under the logger
/// `feign.<Interface>` at debug level, so that level must be on too
/// (`logging.level.feign=debug`):
///
/// ```properties
/// spring.feign.client.config.catalog.logger-level=basic
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
  full,
}

/// The settings of one Feign client: its URL, timeouts, logging, default
/// headers and query parameters, redirects, event-stream reconnection,
/// and the beans that retry, decode errors and intercept requests.
///
/// They come from `spring.feign.client.config.<name>.*`, where
/// `<name>` is the client's name (or `contextId`); what a client does not
/// set falls back to `spring.feign.client.config.default.*`.
/// Applications set the properties; the starter reads them with [of] when
/// it creates each client.
///
/// ```properties
/// spring.feign.client.config.default.read-timeout=10s
/// spring.feign.client.config.default.call-timeout=15s
/// spring.feign.client.config.catalog.url=https://api.neon.books
/// spring.feign.client.config.catalog.logger-level=basic
/// spring.feign.client.config.catalog.dismiss404=true
/// spring.feign.client.config.catalog.default-request-headers.X-Shop=neon
/// spring.feign.client.config.catalog.default-query-parameters.lang=en,de
/// spring.feign.client.config.catalog.retryer=catalogRetryer
/// spring.feign.client.config.catalog.error-decoder=catalogErrors
/// spring.feign.client.config.catalog.request-interceptors[0]=audit
/// spring.feign.client.config.catalog.follow-redirects=false
/// spring.feign.client.config.catalog.sensitive-headers=X-Api-Key
/// spring.feign.client.config.orders.event-stream.reconnect-delay=1s
/// spring.feign.client.decode-slash=false
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
/// The `event-stream.*` keys (reconnection of `EventStream<T>` methods),
/// `sensitive-headers` and `call-timeout` (the total time of one call,
/// retries included; Spring Cloud OpenFeign has only the connect and read
/// timeouts) are additions of this starter: Spring Cloud OpenFeign cannot
/// stream, its logger masks no header and it limits no call as a whole.
/// Spring's counterpart is `FeignClientProperties`.
final class FeignClientConfig {
  /// Settings with these values; the defaults are those of a client
  /// without any property.
  const FeignClientConfig({
    this.url,
    this.readTimeout = defaultReadTimeout,
    this.callTimeout,
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

  /// The longest one call may take in all (`call-timeout`): from the first
  /// attempt through every retry and the pauses between them to the
  /// answer, read to its last byte. `null`, the default, for no limit; the
  /// property set to `0` or a negative duration means none too.
  ///
  /// Where [readTimeout] limits each wait for data, this limits the sum.
  /// It is also capped by what remains of the `RequestDeadline` the call
  /// runs under (a web request with `server.request-timeout`), so the
  /// earlier of the two ends the call; the connect and read timeouts of
  /// each attempt are capped by what remains too. When it passes, the call
  /// throws a `FeignCallTimeoutException` and is not retried, whatever the
  /// retryer says. For an event stream it limits establishing each
  /// connection (up to the status and headers), not the stream's life.
  ///
  /// Spring Cloud OpenFeign has no such setting (only `connect-timeout`
  /// and `read-timeout`): this is an extension of Spring for Dart.
  final Duration? callTimeout;

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
  /// `%2F` (`spring.feign.client.decode-slash`, one setting for
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

  /// Reads the settings of the client whose configuration key is [name]
  /// from the bound [properties], with `default` for what it does not set.
  static FeignClientConfig of(FeignProperties properties, String name) {
    // The name as written in the properties; environment variables are
    // lower case, so a client name matches in any case.
    final configs = properties.config;
    FeignClientSettings? settings(String wanted) =>
        configs[wanted] ??
        configs.entries
            .where((e) => e.key.toLowerCase() == wanted.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
    final own = settings(name);
    final fallback = settings('default');
    T? get<T>(T? Function(FeignClientSettings settings) read) =>
        (own == null ? null : read(own)) ??
        (fallback == null ? null : read(fallback));
    // The client's entries add to those of `default`.
    List<T> both<T>(List<T> Function(FeignClientSettings settings) read) => [
      ...?fallback == null ? null : read(fallback),
      ...?own == null ? null : read(own),
    ];
    String? bean(String? Function(FeignClientSettings settings) read) =>
        switch (get(read)?.trim()) {
          final value? when value.isNotEmpty => value,
          _ => null,
        };
    final readTimeout = get((s) => s.readTimeout) ?? defaultReadTimeout;
    return FeignClientConfig(
      url: get((s) => s.url),
      readTimeout: readTimeout == Duration.zero ? null : readTimeout,
      callTimeout: switch (get((s) => s.callTimeout)) {
        final timeout? when timeout > Duration.zero => timeout,
        _ => null,
      },
      loggerLevel: get((s) => s.loggerLevel) ?? FeignLoggerLevel.none,
      dismiss404: get((s) => s.dismiss404) ?? false,
      defaultRequestHeaders: {
        ...?fallback?.defaultRequestHeaders,
        ...?own?.defaultRequestHeaders,
      },
      defaultQueryParameters: {
        ...?fallback?.defaultQueryParameters,
        ...?own?.defaultQueryParameters,
      },
      followRedirects: get((s) => s.followRedirects) ?? true,
      decodeSlash: properties.decodeSlash,
      eventStreamReconnect: get((s) => s.eventStream.reconnect) ?? true,
      eventStreamReconnectDelay:
          get((s) => s.eventStream.reconnectDelay) ??
          const Duration(seconds: 3),
      eventStreamMaxAttempts: get((s) => s.eventStream.maxAttempts),
      retryer: bean((s) => s.retryer),
      errorDecoder: bean((s) => s.errorDecoder),
      requestInterceptors: both((s) => s.requestInterceptors),
      sensitiveHeaders: both((s) => s.sensitiveHeaders),
    );
  }

  /// The connection timeout of the default transport, one setting for all
  /// clients (`spring.feign.client.config.default.connect-timeout`):
  /// [defaultConnectTimeout] when it is not set, `null` (no timeout) when
  /// it is `0`.
  static Duration? connectTimeout(FeignProperties properties) {
    final timeout =
        properties.config['default']?.connectTimeout ?? defaultConnectTimeout;
    return timeout == Duration.zero ? null : timeout;
  }
}
