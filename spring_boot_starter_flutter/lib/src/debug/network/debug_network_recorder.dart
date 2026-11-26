import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/recording_http_transport.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/recording_web_socket_transport.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/web_socket_frame_labeler.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/web_socket_ping_matcher.dart';
import 'package:spring_web_dart/spring_web_dart.dart'
    show HttpTransport, WebSocketTransport;

/// The debug network recorder (the `debugNetworkRecorder` bean): a
/// [BeanPostProcessor] that puts a recording decorator around each
/// transport bean, so every starter's client is recorded into the
/// [DebugNetworkJournal] without a line of it changing. The decorators
/// are asked in order, the first that supports a bean wraps it: the
/// `HttpTransport` beans ([RecordingHttpTransport]) and the
/// `WebSocketTransport` beans ([RecordingWebSocketTransport]).
///
/// A bean is wrapped only when it is registered as the transport type
/// alone (`BeanDefinition<HttpTransport>`, a `@Bean` method returning
/// `HttpTransport`): one injected by its own class as well
/// (`MockHttpTransport` in a test, a `@Component` transport) is left as it
/// is, so nothing that asks for that class breaks; the recorder says so in
/// the log at `debug`.
///
/// Spring has no counterpart; Spring Boot's actuator records HTTP
/// exchanges of the server (`HttpExchangesRepository`), not of clients.
final class DebugNetworkRecorder extends BeanPostProcessor
    implements BeanFactoryAware {
  /// The recorder writing into the journal [journal] gives when the first
  /// transport is wrapped; [decorators] asked in order.
  DebugNetworkRecorder(
    this._journal, {
    List<NetworkTransportDecorator>? decorators,
  }) : decorators = decorators ?? defaultDecorators();

  static const _log = SpringLog(
    'spring_boot_starter_flutter.DebugNetworkRecorder',
  );

  /// The built-in decorators: HTTP, then WebSocket, its frames labelled
  /// by [labelers] and its heartbeats found by [pingMatchers] (Phoenix's
  /// by default).
  static List<NetworkTransportDecorator> defaultDecorators({
    List<WebSocketFrameLabeler> labelers = const [PhoenixFrameLabeler()],
    List<WebSocketPingMatcher> pingMatchers = const [
      PhoenixHeartbeatMatcher(),
    ],
  }) => [
    const HttpTransportDecorator(),
    WebSocketTransportDecorator(labelers: labelers, pingMatchers: pingMatchers),
  ];

  final DebugNetworkJournal Function() _journal;

  /// The decorators, the first that supports a bean wraps it.
  final List<NetworkTransportDecorator> decorators;

  BeanFactory? _factory;

  @override
  void setBeanFactory(BeanFactory beanFactory) => _factory = beanFactory;

  @override
  Object postProcessAfterInitialization(Object bean, String beanName) {
    for (final decorator in decorators) {
      if (!decorator.supports(bean)) {
        continue;
      }
      final types = _declaredTypes(beanName);
      if (types != null && !types.every(decorator.covers)) {
        _log.debug(
          () =>
              "'$beanName' is not recorded: it is registered as "
              '${types.join(', ')}, and a recording decorator is '
              'only the transport type',
        );
        return bean;
      }
      return decorator.decorate(bean, _journal());
    }
    return bean;
  }

  List<Type>? _declaredTypes(String beanName) {
    final factory = _factory;
    if (factory is ConfigurableListableBeanFactory &&
        factory.containsBeanDefinition(beanName)) {
      return factory.getBeanDefinition(beanName).types;
    }
    return null;
  }
}

/// A recording decorator of one kind of transport, asked by the
/// [DebugNetworkRecorder] in order: the first that [supports] a bean
/// wraps it.
abstract interface class NetworkTransportDecorator {
  /// Whether it wraps [bean].
  bool supports(Object bean);

  /// Whether a bean registered as [type] can be its decorator instead: the
  /// transport type it implements, and `Object`.
  bool covers(Type type);

  /// [bean], recording into [journal].
  Object decorate(Object bean, DebugNetworkJournal journal);
}

/// Wraps an `HttpTransport` in a [RecordingHttpTransport].
final class HttpTransportDecorator implements NetworkTransportDecorator {
  /// The decorator.
  const HttpTransportDecorator();

  @override
  bool supports(Object bean) =>
      bean is HttpTransport && bean is! RecordingHttpTransport;

  @override
  bool covers(Type type) => type == HttpTransport || type == Object;

  @override
  Object decorate(Object bean, DebugNetworkJournal journal) =>
      RecordingHttpTransport(bean as HttpTransport, journal);
}

/// Wraps a `WebSocketTransport` in a [RecordingWebSocketTransport] whose
/// frames [labelers] name and whose heartbeats [pingMatchers] find.
final class WebSocketTransportDecorator implements NetworkTransportDecorator {
  /// The decorator, frames named by [labelers], heartbeats found by
  /// [pingMatchers].
  const WebSocketTransportDecorator({
    this.labelers = const [PhoenixFrameLabeler()],
    this.pingMatchers = const [PhoenixHeartbeatMatcher()],
  });

  /// What names a frame.
  final List<WebSocketFrameLabeler> labelers;

  /// What finds a heartbeat and its reply.
  final List<WebSocketPingMatcher> pingMatchers;

  @override
  bool supports(Object bean) =>
      bean is WebSocketTransport && bean is! RecordingWebSocketTransport;

  @override
  bool covers(Type type) => type == WebSocketTransport || type == Object;

  @override
  Object decorate(Object bean, DebugNetworkJournal journal) =>
      RecordingWebSocketTransport(
        bean as WebSocketTransport,
        journal,
        labelers: labelers,
        pingMatchers: pingMatchers,
      );
}
