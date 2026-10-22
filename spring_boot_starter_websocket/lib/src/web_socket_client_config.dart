import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The settings of one WebSocket client from
/// `spring.websocket.client.config.<name>.*`, falling back to
/// `spring.websocket.client.config.default.*`.
///
/// ```properties
/// spring.websocket.client.config.default.connect-timeout=5s
/// spring.websocket.client.config.chat.url=wss://chat.neon.books/ws
/// spring.websocket.client.config.chat.reconnect-delay=500ms
/// spring.websocket.client.config.chat.max-reconnect-delay=1m
/// spring.websocket.client.config.chat.max-attempts=10
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
    this.reconnect = true,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.maxAttempts,
    this.defaultRequestHeaders = const {},
  });

  /// The address (when `@WebSocketClient` has none).
  final String? url;

  /// The longest the handshake may take (`null`: no limit).
  final Duration? connectTimeout;

  /// Whether a lost connection is opened again while someone listens.
  final bool reconnect;

  /// The wait before the first reconnection; doubled after each failure.
  final Duration reconnectDelay;

  /// The longest wait between reconnections.
  final Duration maxReconnectDelay;

  /// Failed connection attempts in a row before giving up (`null`: never
  /// give up).
  final int? maxAttempts;

  /// Headers sent with every handshake (not possible in browsers).
  final Map<String, String> defaultRequestHeaders;

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
    final maxAttempts = get('max-attempts');
    return WebSocketClientConfig(
      url: get('url'),
      connectTimeout: duration('connect-timeout') ?? defaults.connectTimeout,
      reconnect: get('reconnect')?.trim().toLowerCase() != 'false',
      reconnectDelay: duration('reconnect-delay') ?? defaults.reconnectDelay,
      maxReconnectDelay:
          duration('max-reconnect-delay') ?? defaults.maxReconnectDelay,
      maxAttempts: maxAttempts == null ? null : int.parse(maxAttempts.trim()),
      defaultRequestHeaders: {
        ..._headers(environment, '${_prefix}default.default-request-headers.'),
        ..._headers(environment, '$_prefix$name.default-request-headers.'),
      },
    );
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
