import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_feign/src/feign_client_config.dart';

/// The `spring.feign.client.*` properties.
///
/// Spring Cloud OpenFeign's counterpart is `FeignClientProperties`.
@ConfigurationProperties('spring.feign.client')
class FeignProperties {
  /// `false` encodes `/` in path variables as `%2F`. One setting for all
  /// clients.
  bool decodeSlash = true;

  /// The settings of single clients, by the name of the `@FeignClient`
  /// (its `contextId`, or its name); `default` holds the ones every client
  /// falls back to, property by property.
  Map<String, FeignClientSettings> config = {};
}

/// The settings of one Feign client
/// (`spring.feign.client.config.<name>.*`). What a client leaves out comes
/// from `default`.
@Introspected()
class FeignClientSettings {
  /// The base URL when `@FeignClient(url:)` is empty; `http://` is added
  /// when the scheme is missing. `${...}` placeholders are allowed.
  String? url;

  /// **Under `default` only**: the connect timeout of the transport all
  /// clients share. Default: `10s` (`0`: none).
  Duration? connectTimeout;

  /// The longest wait for the response, then between two chunks of the
  /// body; not a limit for the whole call. Default: `60s` (`0`: none).
  Duration? readTimeout;

  /// The longest one call may take **in all**: every attempt, the pauses of
  /// the `Retryer` and the wait for the answer. Default: none (`0` or
  /// less: none).
  Duration? callTimeout;

  /// How much of each call is logged, under the logger `feign.<Interface>`
  /// at debug level. Default: `none`.
  FeignLoggerLevel? loggerLevel;

  /// A 404 gives `null` (or a `ResponseEntity`) instead of an exception;
  /// `void` methods still throw. Default: `false`.
  bool? dismiss404;

  /// Headers sent when the request has none of that name; `default`'s and
  /// the client's are merged, the client's winning for the same name. A
  /// comma list or an indexed list gives several values.
  Map<String, List<String>> defaultRequestHeaders = {};

  /// The same for query parameters. The URL with its query is in the log
  /// lines and in exception messages, so prefer a header for a secret.
  Map<String, List<String>> defaultQueryParameters = {};

  /// Follows redirects; with `false` a 3xx answer is an error. Default:
  /// `true`.
  bool? followRedirects;

  /// How `EventStream<T>` methods connect again.
  FeignEventStreamSettings eventStream = FeignEventStreamSettings();

  /// The client's `Retryer`: a bean name, or a class name matching the
  /// type of exactly one bean. Default: never retries.
  String? retryer;

  /// The client's `ErrorDecoder`: a bean name, or a class name matching the
  /// type of exactly one bean. Default: `DefaultErrorDecoder`.
  String? errorDecoder;

  /// More `RequestInterceptor` beans, by bean name or class name:
  /// `default`'s, then the client's, after those the client has anyway.
  List<String> requestInterceptors = [];

  /// More headers whose values the `headers` and `full` logs show as `***`
  /// (names in any case): `default`'s, then the client's. `Authorization`,
  /// `Proxy-Authorization`, `Cookie`, `Set-Cookie` and `DPoP` always are.
  List<String> sensitiveHeaders = [];
}

/// The `event-stream.*` settings of a Feign client.
@Introspected()
class FeignEventStreamSettings {
  /// An `EventStream<T>` method connects again when the connection ends.
  /// Default: `true`.
  bool? reconnect;

  /// The wait before connecting again. Default: `3s`, or the server's
  /// `retry:`.
  Duration? reconnectDelay;

  /// How many connections in a row may end without an event before the
  /// stream gives up. Default: no limit.
  int? maxAttempts;
}
