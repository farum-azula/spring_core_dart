import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// A running (or ready to run) HTTP server, like Spring Boot's `WebServer`.
/// Created by a [WebServerFactory] for the application's [HttpHandler];
/// started and stopped with the context by `WebServerStartStopLifecycle`.
abstract interface class WebServer {
  /// Binds the socket and starts answering requests. Throws a
  /// [PortInUseException] when the port is taken.
  Future<void> start();

  /// Stops the server: with `server.shutdown=graceful` it stops accepting
  /// connections and waits up to [timeout] for running requests (open
  /// streams are closed), then closes what is left.
  Future<void> stop({Duration? timeout});

  /// The port the server listens on (the real one for port 0), or `-1`
  /// before it started.
  int get port;
}

/// Creates the [WebServer], like Spring Boot's `WebServerFactory`. The web
/// starter registers `IoWebServerFactory` (`dart:io`'s `HttpServer`) unless
/// the application declares one: replacing the server means declaring a
/// `WebServerFactory` bean, or adding a starter whose auto-configuration
/// declares one first.
///
/// ```dart
/// @Configuration()
/// class ServerConfig {
///   @Bean()
///   WebServerFactory webServerFactory() => MyServerFactory();
/// }
/// ```
abstract interface class WebServerFactory {
  /// A server handing every request to [handler].
  WebServer getWebServer(HttpHandler handler);
}

/// A [WebServerFactory] with the settings of `server.*`, like Spring Boot's
/// `ConfigurableWebServerFactory`: the auto-configuration applies
/// [ServerProperties] to it, then every [WebServerFactoryCustomizer] bean.
abstract interface class ConfigurableWebServerFactory
    implements WebServerFactory {
  /// The settings the server starts with.
  ServerProperties get settings;
  set settings(ServerProperties value);
}

/// Changes the [WebServerFactory] before the server is created, like
/// Spring Boot's `WebServerFactoryCustomizer`.
///
/// ```dart
/// @Component()
/// class PortCustomizer implements WebServerFactoryCustomizer {
///   @override
///   void customize(ConfigurableWebServerFactory factory) =>
///       factory.settings = factory.settings.copyWith(port: 9090);
/// }
/// ```
abstract interface class WebServerFactoryCustomizer {
  /// Changes [factory].
  void customize(ConfigurableWebServerFactory factory);
}

/// How the server stops, like Spring Boot's `Shutdown`.
enum Shutdown {
  /// Stop accepting connections and wait for running requests (within
  /// `spring.lifecycle.timeout-per-shutdown-phase`).
  graceful,

  /// Close every connection right away.
  immediate,
}

/// TLS settings (`server.ssl.*`), with PEM files like Spring Boot's
/// `server.ssl.certificate` / `certificate-private-key`.
final class SslSettings {
  /// TLS with the PEM [certificate] chain and [privateKey] files.
  const SslSettings({
    required this.certificate,
    required this.privateKey,
    this.privateKeyPassword,
    this.trustCertificate,
    this.clientAuth = ClientAuth.none,
  });

  /// The certificate chain file (PEM).
  final String certificate;

  /// The private key file (PEM).
  final String privateKey;

  /// The private key's password, if encrypted.
  final String? privateKeyPassword;

  /// Certificates of trusted clients (PEM), for [clientAuth].
  final String? trustCertificate;

  /// Whether clients must present a certificate.
  final ClientAuth clientAuth;
}

/// Client certificate authentication (`server.ssl.client-auth`).
enum ClientAuth {
  /// No client certificate is asked for.
  none,

  /// A client certificate is asked for, not required.
  want,

  /// A client certificate is required.
  need,
}

/// The `server.*` properties, like Spring Boot's `ServerProperties`.
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
/// | `server.compression.enabled` | `false`: gzip for clients that accept it |
final class ServerProperties {
  /// The settings; see the table above for the defaults.
  const ServerProperties({
    this.port = 8080,
    this.address,
    this.shutdown = Shutdown.graceful,
    this.ssl,
    this.contextPath = '',
    this.maxRequestBodySize = 10 * 1024 * 1024,
    this.compression = false,
  });

  /// Reads `server.*` from [environment]; [defaultAddress] when
  /// `server.address` is not set (`127.0.0.1` for Flutter apps).
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
    final maxBody = switch (text('server.max-http-request-body-size')) {
      null => 10 * 1024 * 1024,
      '-1' => -1,
      final value => DataSize.parse(value).toBytes(),
    };
    return ServerProperties(
      port: port,
      address: text('server.address') ?? defaultAddress,
      shutdown: shutdown,
      ssl: ssl,
      contextPath: contextPath ?? '',
      maxRequestBodySize: maxBody,
      compression: text('server.compression.enabled')?.toLowerCase() == 'true',
    );
  }

  /// The port (`0`: random).
  final int port;

  /// The address to bind (`null`: every interface).
  final String? address;

  /// How the server stops.
  final Shutdown shutdown;

  /// TLS, or `null` for plain HTTP.
  final SslSettings? ssl;

  /// A prefix of every path (`/shop`), or empty.
  final String contextPath;

  /// The largest request body in bytes (`-1`: no limit).
  final int maxRequestBodySize;

  /// Whether responses are gzip-compressed for clients accepting it.
  final bool compression;

  /// A copy with the given settings changed.
  ServerProperties copyWith({
    int? port,
    String? address,
    Shutdown? shutdown,
    SslSettings? ssl,
    String? contextPath,
    int? maxRequestBodySize,
    bool? compression,
  }) => ServerProperties(
    port: port ?? this.port,
    address: address ?? this.address,
    shutdown: shutdown ?? this.shutdown,
    ssl: ssl ?? this.ssl,
    contextPath: contextPath ?? this.contextPath,
    maxRequestBodySize: maxRequestBodySize ?? this.maxRequestBodySize,
    compression: compression ?? this.compression,
  );
}

/// The server could not start.
class WebServerException implements Exception {
  /// A failure described by [message], caused by [cause].
  WebServerException(this.message, [this.cause]);

  /// What went wrong.
  final String message;

  /// The underlying error.
  final Object? cause;

  @override
  String toString() =>
      'WebServerException: $message${cause == null ? '' : ' ($cause)'}';
}

/// The port is used by another process, like Spring Boot's
/// `PortInUseException`.
class PortInUseException extends WebServerException {
  /// [port] is taken.
  PortInUseException(this.port, [Object? cause])
    : super('Port $port is already in use', cause);

  /// The port.
  final int port;
}

/// Explains a [PortInUseException] at startup, like Spring Boot's
/// `PortInUseFailureAnalyzer`.
final class PortInUseFailureAnalyzer implements FailureAnalyzer {
  /// The analyzer.
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

/// Published when the server listens, like Spring Boot's
/// `WebServerInitializedEvent`; [port] is also the `local.server.port`
/// property.
///
/// ```dart
/// @EventListener()
/// void onServer(WebServerInitializedEvent event) =>
///     print('listening on ${event.port}');
/// ```
class WebServerInitializedEvent extends ApplicationEvent {
  /// [server] listens on [port].
  WebServerInitializedEvent(super.source, this.server, this.port);

  /// The server.
  final WebServer server;

  /// The port it listens on.
  final int port;

  @override
  String toString() => 'WebServerInitializedEvent[port=$port]';
}
