import 'package:spring_boot_dart/spring_boot_dart.dart';

/// The `spring.websocket.client.*` properties.
///
/// Differs from Spring: these keys are this project's own (shaped like
/// `spring.feign.client.config.*`); Spring Boot has no properties for
/// WebSocket clients.
@ConfigurationProperties('spring.websocket.client')
class WebSocketProperties {
  /// The largest text message a client reads, in UTF-8 bytes (Tomcat counts
  /// characters); a larger one closes the connection with 1009 (message too
  /// big). `-1` for no limit.
  DataSize maxTextMessageSize = DataSize.ofKilobytes(8);

  /// The same for binary messages. `-1` for no limit.
  DataSize maxBinaryMessageSize = DataSize.ofKilobytes(8);

  /// The settings of single clients, by the name of the `@WebSocketClient`;
  /// `default` holds the ones every client falls back to, property by
  /// property.
  Map<String, WebSocketClientSettings> config = {};
}

/// The settings of one client (`spring.websocket.client.config.<name>.*`).
/// What a client leaves out comes from `default`, then from the default
/// named at each property.
@Introspected()
class WebSocketClientSettings {
  /// The address, when `@WebSocketClient(url:)` is not set. `${...}`
  /// placeholders are allowed.
  String? url;

  /// The longest a handshake may take. Default: `10s`.
  Duration? connectTimeout;

  /// Headers sent with the handshake, such as an API key (a comma list or
  /// an indexed list gives several values); not possible in browsers. A
  /// client's header replaces the `default` one of the same name.
  Map<String, List<String>> defaultRequestHeaders = {};

  /// How a lost connection, or a failed attempt, is opened again while
  /// someone listens.
  WebSocketReconnectSettings reconnect = WebSocketReconnectSettings();
}

/// The `reconnect.*` settings of a client, named as Spring Framework 7's
/// `RetryPolicy`.
@Introspected()
class WebSocketReconnectSettings {
  /// Reconnects while someone listens to the messages. With `false`, a lost
  /// connection ends the message streams. Default: `true`.
  bool? enabled;

  /// The first wait. Default: `1s`.
  Duration? delay;

  /// What each further wait is multiplied by; `1` for a fixed delay, not
  /// less. Default: `2`.
  double? multiplier;

  /// The longest wait; positive. Default: `30s`.
  Duration? maxDelay;

  /// A random part added or taken, scaled like the delay. Default: none.
  Duration? jitter;

  /// Attempts in a row before giving up. Default: no limit.
  int? maxRetries;
}
