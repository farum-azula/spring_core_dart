// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// An HTTP server that listens on a port and hands every request to an
/// [HttpHandler].
///
/// It is the boundary between the network and the rest of the starter:
/// routing, filters and controllers only see `ServerHttpRequest` and
/// `ServerHttpResponse`, so another server (another library, another
/// platform) needs only an implementation of this and its
/// [WebServerFactory]. Applications never start one themselves: the
/// starter's lifecycle bean starts it when the context is ready and stops
/// it when the context closes. The default is the `dart:io` server.
///
/// ```dart
/// // A server of another library, made usable by the starter.
/// final class ShelfWebServer implements WebServer {
///   ShelfWebServer(this.handler, this.settings);
///   final HttpHandler handler;
///   final ServerProperties settings;
///
///   @override
///   Future<void> start() async { ... }   // bind and forward requests
///
///   @override
///   Future<void> stop({Duration? timeout}) async { ... }
///
///   @override
///   int get port => ...;
/// }
/// ```
///
/// Spring Boot (Java) has the same interface:
/// ```java
/// public interface WebServer {
///   void start() throws WebServerException;
///   void stop() throws WebServerException;
///   int getPort();
/// }
/// ```
abstract interface class WebServer {
  /// Binds the socket and starts answering requests; completes once the
  /// server listens. Throws a [PortInUseException] when the port is
  /// taken, a [WebServerException] for other failures.
  Future<void> start();

  /// Stops the server. With `server.shutdown=graceful` it stops accepting
  /// connections and lets running requests finish for up to [timeout]
  /// (30 seconds when `null`), then closes what is left; open event
  /// streams and WebSocket sessions are closed at once.
  Future<void> stop({Duration? timeout});

  /// The port the server listens on (the real one when `server.port` is
  /// 0), or `-1` before it started.
  int get port;
}

/// Creates the [WebServer] of the application.
///
/// The starter asks the `webServerFactory` bean for a server when the
/// context starts. By default it is an `IoWebServerFactory`
/// (`dart:io`'s `HttpServer`). To run on another server, declare a bean
/// of this type, or add a starter that declares one: the default backs
/// off when one exists. To change only settings, a
/// [WebServerFactoryCustomizer] is simpler.
///
/// ```dart
/// @Configuration()
/// class ServerConfig {
///   // Requests go through a server of another library.
///   @Bean()
///   WebServerFactory webServerFactory() => ShelfWebServerFactory();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// ServletWebServerFactory webServerFactory() {
///   return new JettyServletWebServerFactory();
/// }
/// ```
abstract interface class WebServerFactory {
  /// A new, not yet started server that hands every request to
  /// [handler].
  WebServer getWebServer(HttpHandler handler);
}

/// A [WebServerFactory] whose server settings can be changed before the
/// server is created.
///
/// The starter gives the default factory the settings read from
/// `server.*`, then passes it to every [WebServerFactoryCustomizer] bean,
/// which may change them. A factory of your own that implements this gets
/// the same treatment only if you apply the settings yourself.
abstract interface class ConfigurableWebServerFactory
    implements WebServerFactory {
  /// The settings the next server starts with; replace them with a
  /// changed copy ([ServerProperties.copyWith]).
  ServerProperties get settings;
  set settings(ServerProperties value);
}

/// A bean that changes the server's settings in code before the server
/// is created.
///
/// Properties (`server.port`, ...) cover most needs. Use a customizer
/// when a setting is computed, for example a port chosen by the
/// platform, or a certificate path found at runtime. The starter calls
/// every customizer bean once, on the default factory, after it applied
/// `server.*`.
///
/// ```dart
/// // The hosting platform gives the port in the PORT variable.
/// @Component()
/// class PortCustomizer implements WebServerFactoryCustomizer {
///   @override
///   void customize(ConfigurableWebServerFactory factory) =>
///       factory.settings = factory.settings.copyWith(
///         port: int.parse(Platform.environment['PORT'] ?? '8080'),
///       );
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class PortCustomizer
///     implements WebServerFactoryCustomizer<ConfigurableWebServerFactory> {
///   public void customize(ConfigurableWebServerFactory factory) {
///     factory.setPort(Integer.parseInt(System.getenv("PORT")));
///   }
/// }
/// ```
abstract interface class WebServerFactoryCustomizer {
  /// Changes the settings of [factory], usually by assigning a changed
  /// copy to `factory.settings`.
  void customize(ConfigurableWebServerFactory factory);
}

/// How the server stops when the application closes
/// (`server.shutdown`).
enum Shutdown {
  /// Stop accepting connections and let running requests finish, for up
  /// to `spring.lifecycle.timeout-per-shutdown-phase` (30 seconds by
  /// default); then close what is left. The default.
  graceful,

  /// Close every connection right away, cutting running requests.
  immediate,
}

/// The TLS (HTTPS) settings of the server, read from `server.ssl.*`.
///
/// The certificate and key are PEM files given by path, as Spring Boot's
/// `server.ssl.certificate` and `server.ssl.certificate-private-key`
/// (there are no keystores, SSL bundles or `classpath:` locations).
/// Applications set the properties; this class is what
/// [ServerProperties.ssl] holds.
///
/// ```properties
/// server.ssl.certificate=/etc/shop/cert.pem
/// server.ssl.certificate-private-key=/etc/shop/key.pem
/// ```
final class SslSettings {
  /// TLS with the PEM [certificate] chain and [privateKey] files; no
  /// client certificate is asked for by default.
  const SslSettings({
    required this.certificate,
    required this.privateKey,
    this.privateKeyPassword,
    this.trustCertificate,
    this.clientAuth = ClientAuth.none,
  });

  /// The path of the server's certificate chain, a PEM file
  /// (`server.ssl.certificate`).
  final String certificate;

  /// The path of the private key, a PEM file
  /// (`server.ssl.certificate-private-key`).
  final String privateKey;

  /// The password of the private key when it is encrypted
  /// (`server.ssl.key-password`); `null` for a plain key.
  final String? privateKeyPassword;

  /// The path of a PEM file with the certificates that client
  /// certificates must be signed by (`server.ssl.trust-certificate`);
  /// used with [clientAuth]. `null` trusts the system's certificates.
  final String? trustCertificate;

  /// Whether clients are asked for a certificate
  /// (`server.ssl.client-auth`); [ClientAuth.none] by default.
  final ClientAuth clientAuth;
}

/// Whether the server asks HTTPS clients for a certificate of their own
/// (`server.ssl.client-auth`), to know which machine calls.
enum ClientAuth {
  /// No client certificate is asked for. The default.
  none,

  /// A client certificate is asked for; a client without one is served
  /// anyway.
  want,

  /// A client certificate is required; a request without one gets a 403.
  need,
}

/// The settings of the HTTP server, read from the `server.*` properties.
///
/// Applications set the properties; the starter reads them with
/// [ServerProperties.of] into the `webServerFactory` bean. Code meets
/// this class in a [WebServerFactoryCustomizer], to change a setting
/// with [copyWith].
///
/// | Property | Default |
/// |---|---|
/// | `server.port` | `8080` (`0`: a random free port) |
/// | `server.address` | all interfaces (`127.0.0.1` in Flutter apps) |
/// | `server.shutdown` | `graceful` |
/// | `server.ssl.enabled`, `server.ssl.certificate`, `server.ssl.certificate-private-key`, `server.ssl.key-password`, `server.ssl.trust-certificate`, `server.ssl.client-auth` | no TLS |
/// | `server.servlet.context-path` | none: a prefix of every mapping |
/// | `server.max-http-request-body-size` | `10MB` (`-1`: no limit) |
/// | `server.http2.enabled` | ignored (`dart:io` speaks HTTP/1.1) |
/// | `server.compression.enabled` | `false`; `true` gzips the responses of `mime-types` from `min-response-size` on, for clients that accept gzip |
/// | `server.compression.mime-types` | Spring Boot's: `text/html`, `text/xml`, `text/plain`, `text/css`, `text/javascript`, `application/javascript`, `application/json`, `application/xml` |
/// | `server.compression.min-response-size` | `2KB` |
/// | `server.forward-headers-strategy` | `none`; `native` or `framework` applies the headers of trusted proxies (`ForwardedHeaderFilter`) |
/// | `server.forward-headers.trusted-proxies` | loopback and private networks (addresses and CIDR ranges) |
/// | `server.connection-timeout` | `60s` (`-1`, `0` or less: none): a request body that sends nothing for this long is a 408; also how long an idle connection stays open |
/// | `server.websocket.max-text-message-size`, `server.websocket.max-binary-message-size` | `8KB` each (`-1`: no limit); a larger message closes the session with 1009 |
/// | `server.websocket.send-buffer-size-limit` | `512KB` (`-1`: no limit): more waiting to be sent drops the connection (4500) |
/// | `server.websocket.send-time-limit` | `10s` (`-1`: no limit): what was sent and has not left by then drops the connection (4500) |
final class ServerProperties {
  /// Settings with the defaults of the table above.
  const ServerProperties({
    this.port = 8080,
    this.address,
    this.shutdown = Shutdown.graceful,
    this.ssl,
    this.contextPath = '',
    this.maxRequestBodySize = 10 * 1024 * 1024,
    this.compression = false,
    this.compressionMimeTypes = defaultCompressionMimeTypes,
    this.compressionMinResponseSize = 2048,
    this.webSocketMaxTextMessageSize = 8192,
    this.webSocketMaxBinaryMessageSize = 8192,
    this.webSocketSendBufferSizeLimit = 512 * 1024,
    this.webSocketSendTimeLimit = const Duration(seconds: 10),
    this.connectionTimeout = const Duration(seconds: 60),
  });

  /// Reads `server.*` from [environment]. [defaultAddress] applies when
  /// `server.address` is not set; the starter passes `127.0.0.1` in
  /// Flutter apps, so they open no port to the network by accident.
  ///
  /// TLS is on when `server.ssl.certificate` is set and
  /// `server.ssl.enabled` is not `false`. The legacy
  /// `server.context-path` is read when `server.servlet.context-path` is
  /// not set; a context path gets a leading `/` and loses a trailing
  /// one. Durations are written as `10s`, `500ms` (a bare number is
  /// milliseconds) or `PT10S`. Throws an
  /// [ArgumentError] for a port that is not a number, an unknown
  /// `server.shutdown` or `server.ssl.client-auth`, or a certificate
  /// without its private key.
  factory ServerProperties.of(
    PropertyResolver environment, {
    String? defaultAddress,
  }) {
    String? text(String name) {
      final value = environment.getProperty(name)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final port = switch (text('server.port')) {
      final value? =>
        int.tryParse(value) ??
            (throw ArgumentError.value(value, 'server.port', 'not a number')),
      null => 8080,
    };
    final shutdown = switch (text('server.shutdown')?.toLowerCase()) {
      null || 'graceful' => Shutdown.graceful,
      'immediate' => Shutdown.immediate,
      final other => throw ArgumentError.value(
        other,
        'server.shutdown',
        'expected graceful or immediate',
      ),
    };
    final sslEnabled = switch (text('server.ssl.enabled')?.toLowerCase()) {
      'false' => false,
      _ => true,
    };
    final certificate = text('server.ssl.certificate');
    final privateKey = text('server.ssl.certificate-private-key');
    final ssl = sslEnabled && certificate != null
        ? SslSettings(
            certificate: certificate,
            privateKey:
                privateKey ??
                (throw ArgumentError(
                  'server.ssl.certificate needs '
                  'server.ssl.certificate-private-key',
                )),
            privateKeyPassword: text('server.ssl.key-password'),
            trustCertificate: text('server.ssl.trust-certificate'),
            clientAuth: switch (text('server.ssl.client-auth')?.toLowerCase()) {
              null || 'none' => ClientAuth.none,
              'want' => ClientAuth.want,
              'need' => ClientAuth.need,
              final other => throw ArgumentError.value(
                other,
                'server.ssl.client-auth',
                'expected none, want or need',
              ),
            },
          )
        : null;
    var contextPath =
        text('server.servlet.context-path') ?? text('server.context-path');
    if (contextPath != null) {
      if (!contextPath.startsWith('/')) {
        contextPath = '/$contextPath';
      }
      while (contextPath!.endsWith('/')) {
        contextPath = contextPath.substring(0, contextPath.length - 1);
      }
    }
    int size(String name, int fallback) => switch (text(name)) {
      null => fallback,
      '-1' => -1,
      final value => DataSize.parse(value).toBytes(),
    };
    Duration? duration(String name, Duration fallback) => switch (text(name)) {
      null => fallback,
      '-1' => null,
      final value => DurationStyle.parse(value),
    };
    final mimeTypes = text('server.compression.mime-types');
    return ServerProperties(
      port: port,
      address: text('server.address') ?? defaultAddress,
      shutdown: shutdown,
      ssl: ssl,
      contextPath: contextPath ?? '',
      maxRequestBodySize: size(
        'server.max-http-request-body-size',
        10 * 1024 * 1024,
      ),
      compression: text('server.compression.enabled')?.toLowerCase() == 'true',
      compressionMimeTypes: mimeTypes == null
          ? defaultCompressionMimeTypes
          : [
              for (final type in mimeTypes.split(','))
                if (type.trim().isNotEmpty) type.trim().toLowerCase(),
            ],
      compressionMinResponseSize: size(
        'server.compression.min-response-size',
        2048,
      ),
      webSocketMaxTextMessageSize: size(
        'server.websocket.max-text-message-size',
        8192,
      ),
      webSocketMaxBinaryMessageSize: size(
        'server.websocket.max-binary-message-size',
        8192,
      ),
      webSocketSendBufferSizeLimit: size(
        'server.websocket.send-buffer-size-limit',
        512 * 1024,
      ),
      webSocketSendTimeLimit: duration(
        'server.websocket.send-time-limit',
        const Duration(seconds: 10),
      ),
      // As Tomcat, whose connectionTimeout is a timeout only above 0.
      connectionTimeout: switch (duration(
        'server.connection-timeout',
        const Duration(seconds: 60),
      )) {
        final timeout? when timeout > Duration.zero => timeout,
        _ => null,
      },
    );
  }

  /// The media types compressed by default (`server.compression.mime-types`),
  /// Spring Boot's list.
  static const defaultCompressionMimeTypes = [
    'text/html',
    'text/xml',
    'text/plain',
    'text/css',
    'text/javascript',
    'application/javascript',
    'application/json',
    'application/xml',
  ];

  /// The port to listen on; 8080 by default, `0` for a free port chosen
  /// by the system (read it from [WebServer.port] or the
  /// `local.server.port` property).
  final int port;

  /// The address to listen on, an IP address or a host name
  /// (`localhost` is `127.0.0.1`); `null` listens on every interface.
  final String? address;

  /// How the server stops; [Shutdown.graceful] by default.
  final Shutdown shutdown;

  /// The TLS settings, or `null` for plain HTTP.
  final SslSettings? ssl;

  /// A prefix every request path must have, such as `/shop`; it is
  /// removed before routing, so `@GetMapping('/books')` answers
  /// `/shop/books`. Empty for none.
  final String contextPath;

  /// The largest request body accepted, in bytes; 10 MB by default, `-1`
  /// for no limit. A larger body is a 413, whatever its `Content-Type`.
  /// Only the multipart resolver reads uploads with its own limit
  /// (`spring.servlet.multipart.max-request-size`), through
  /// [maxRequestBodySizeAttribute].
  final int maxRequestBodySize;

  /// Whether responses are gzip-compressed for clients that accept it
  /// (`Accept-Encoding: gzip`); `false` by default. Only responses of
  /// [compressionMimeTypes] and of at least [compressionMinResponseSize]
  /// bytes (or of unknown length) are compressed, never partial content
  /// or a response that already has a `Content-Encoding`.
  final bool compression;

  /// The media types compressed when [compression] is on, without
  /// parameters (`text/*` matches every text type);
  /// [defaultCompressionMimeTypes] by default. Event streams are not in
  /// it, as in Spring Boot; add `text/event-stream` to compress them too.
  final List<String> compressionMimeTypes;

  /// The smallest `Content-Length` compressed, in bytes; 2 KB by default.
  final int compressionMinResponseSize;

  /// The largest text message a WebSocket session accepts, in bytes; 8 KB
  /// by default (Tomcat's default in Spring), `-1` for no limit. A larger
  /// message is not read: the session is closed with 1009 (message too
  /// big). This starter's own key; Spring sets it on the container
  /// (`ServletServerContainerFactoryBean`).
  final int webSocketMaxTextMessageSize;

  /// The largest binary message a WebSocket session accepts, in bytes; as
  /// [webSocketMaxTextMessageSize].
  final int webSocketMaxBinaryMessageSize;

  /// How many bytes a WebSocket session may keep waiting to be sent, for
  /// a client that reads slowly or not at all; 512 KB by default, `-1`
  /// for no limit. Past it the connection is dropped and the session's
  /// close status is 4500 (`CloseStatus.sessionNotReliable`), as Spring's
  /// `ConcurrentWebSocketSessionDecorator` does with its
  /// `sendBufferSizeLimit`. This starter's own key
  /// (`server.websocket.send-buffer-size-limit`); Spring sets it in code.
  final int webSocketSendBufferSizeLimit;

  /// How long what a WebSocket session sent may take to leave; 10 seconds
  /// by default, `null` for no limit. Past it the connection is dropped,
  /// as for [webSocketSendBufferSizeLimit] (Spring's `sendTimeLimit`).
  final Duration? webSocketSendTimeLimit;

  /// How long a request body may send nothing before the request is
  /// answered with 408 (Request Timeout) and the connection closed; also
  /// how long an idle keep-alive connection stays open. 60 seconds by
  /// default, Tomcat's `connectionTimeout`; `null`, zero or a negative
  /// duration for no limit, as Tomcat takes `-1` and `0`
  /// (`server.connection-timeout`, the key Spring Boot 2.0 had).
  final Duration? connectionTimeout;

  /// [connectionTimeout] as the server applies it: `null` (no limit) for
  /// zero or a negative duration.
  Duration? get effectiveConnectionTimeout => switch (connectionTimeout) {
    final timeout? when timeout > Duration.zero => timeout,
    _ => null,
  };

  /// A copy with the given settings changed and the others kept. A
  /// `null` argument keeps the old value, so [address], [ssl],
  /// [webSocketSendTimeLimit] and [connectionTimeout] cannot be reset to
  /// `null` this way.
  ServerProperties copyWith({
    int? port,
    String? address,
    Shutdown? shutdown,
    SslSettings? ssl,
    String? contextPath,
    int? maxRequestBodySize,
    bool? compression,
    List<String>? compressionMimeTypes,
    int? compressionMinResponseSize,
    int? webSocketMaxTextMessageSize,
    int? webSocketMaxBinaryMessageSize,
    int? webSocketSendBufferSizeLimit,
    Duration? webSocketSendTimeLimit,
    Duration? connectionTimeout,
  }) => ServerProperties(
    port: port ?? this.port,
    address: address ?? this.address,
    shutdown: shutdown ?? this.shutdown,
    ssl: ssl ?? this.ssl,
    contextPath: contextPath ?? this.contextPath,
    maxRequestBodySize: maxRequestBodySize ?? this.maxRequestBodySize,
    compression: compression ?? this.compression,
    compressionMimeTypes: compressionMimeTypes ?? this.compressionMimeTypes,
    compressionMinResponseSize:
        compressionMinResponseSize ?? this.compressionMinResponseSize,
    webSocketMaxTextMessageSize:
        webSocketMaxTextMessageSize ?? this.webSocketMaxTextMessageSize,
    webSocketMaxBinaryMessageSize:
        webSocketMaxBinaryMessageSize ?? this.webSocketMaxBinaryMessageSize,
    webSocketSendBufferSizeLimit:
        webSocketSendBufferSizeLimit ?? this.webSocketSendBufferSizeLimit,
    webSocketSendTimeLimit:
        webSocketSendTimeLimit ?? this.webSocketSendTimeLimit,
    connectionTimeout: connectionTimeout ?? this.connectionTimeout,
  );
}

/// The name of a request attribute that replaces
/// `server.max-http-request-body-size` for one request: an `int`, the
/// largest body in bytes, `-1` for no limit. Set it before the body is
/// read.
///
/// The multipart resolver sets it to `spring.servlet.multipart.max-request-size`,
/// so uploads have their own limit while every other reader of a
/// `multipart/*` body keeps the server's. A handler that streams a large
/// body of its own can do the same:
///
/// ```dart
/// // Disk images up to 4 GB, read as a stream.
/// request.attributes[maxRequestBodySizeAttribute] = 4 << 30;
/// await request.body.pipe(file.openWrite());
/// ```
const maxRequestBodySizeAttribute = 'spring.web.maxRequestBodySize';

/// The name of a request attribute the dispatcher sets (to the error)
/// when a request fails after its response was committed: the status and
/// headers, perhaps part of the body, are already out, so no error
/// answer can follow.
///
/// A [WebServer] that finds it set once the handler returns drops the
/// connection instead of finishing the response, as Tomcat does, so the
/// client sees that the response broke off (a chunked body without its
/// final chunk, a body shorter than its `Content-Length`) and does not
/// take half a response for a whole one. The `dart:io` server does so; a
/// server of your own should too.
const responseFailedAttribute = 'spring.web.responseFailed';

/// Thrown when the server cannot start, for example because the address
/// cannot be bound or the certificate cannot be read.
///
/// It stops the application at startup. A port in use is the subtype
/// [PortInUseException], which gets a clearer report.
class WebServerException implements Exception {
  /// A failure described by [message], caused by [cause].
  WebServerException(this.message, [this.cause]);

  /// What went wrong, such as `cannot listen on *:8080`.
  final String message;

  /// The error that caused it, usually a `SocketException`; `null` when
  /// none.
  final Object? cause;

  @override
  String toString() =>
      'WebServerException: $message${cause == null ? '' : ' ($cause)'}';
}

/// Thrown when the server cannot start because another process (or
/// another server of this one) already listens on its port.
///
/// The [PortInUseFailureAnalyzer] turns it into a short report at
/// startup that says what to do.
class PortInUseException extends WebServerException {
  /// The [port] is taken; [cause] is the socket error.
  PortInUseException(this.port, [Object? cause])
    : super('Port $port is already in use', cause);

  /// The port the server tried to listen on.
  final int port;
}

/// Turns a [PortInUseException] at startup into a report that says what
/// happened and what to do, instead of a stack trace:
///
/// ```text
/// Web server failed to start. Port 8080 was already in use.
///
/// Action: Identify and stop the process that is listening on port 8080,
/// or configure this application to listen on another port (server.port;
/// 0 picks a free one).
/// ```
///
/// The starter declares it as a bean; applications do not use it.
final class PortInUseFailureAnalyzer implements FailureAnalyzer {
  /// The analyzer; it has no state.
  const PortInUseFailureAnalyzer();

  @override
  FailureAnalysis? analyze(Object failure) => switch (failure) {
    PortInUseException(:final port) => FailureAnalysis(
      'Web server failed to start. Port $port was already in use.',
      'Identify and stop the process that is listening on port $port, or '
          'configure this application to listen on another port '
          '(server.port; 0 picks a free one).',
      failure,
    ),
    _ => null,
  };
}

/// The event published once the server listens, with the port it got.
///
/// Listen to it when code needs the real port, which is only known then
/// when `server.port=0` picks a free one: to register the service with a
/// discovery server, or to log a URL. The same port is also in the
/// `local.server.port` property from then on.
///
/// ```dart
/// // Tell the developer where the application answers.
/// @EventListener()
/// void onServer(WebServerInitializedEvent event) =>
///     log.info('Open http://localhost:${event.port}/');
/// ```
///
/// Spring (Java):
/// ```java
/// @EventListener
/// void onServer(WebServerInitializedEvent event) {
///   log.info("Open http://localhost:"
///       + event.getWebServer().getPort() + "/");
/// }
/// ```
class WebServerInitializedEvent extends ApplicationEvent {
  /// The event that [server] listens on [port]; [source] is the
  /// application context.
  WebServerInitializedEvent(super.source, this.server, this.port);

  /// The server that started.
  final WebServer server;

  /// The port the server listens on.
  final int port;

  @override
  String toString() => 'WebServerInitializedEvent[port=$port]';
}
