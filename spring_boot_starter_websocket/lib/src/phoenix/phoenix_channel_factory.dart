import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel_invocation_handler.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_socket_factory.dart';

/// The bean that builds the implementation of every `@PhoenixChannel`
/// interface.
///
/// The starter registers it as `phoenixChannelFactory`; applications do
/// not use it directly. When the container creates a channel bean, the
/// factory makes its [PhoenixChannelInvocationHandler] with the
/// application's [ObjectMapper] and [PhoenixJoinInterceptor] beans, over
/// a socket of the [PhoenixSocketFactory], which also closes the sockets
/// when the application stops.
///
/// Differs from Spring: Spring has no Phoenix client, so no such
/// factory.
final class PhoenixChannelFactory implements InvocationHandlerFactory {
  /// A factory taking the sockets from [sockets], with the given
  /// [mapper] and [interceptors].
  PhoenixChannelFactory({
    required this.environment,
    required this.mapper,
    required this.sockets,
    this.interceptors = const [],
  });

  /// Where the `${...}` of the URLs and topics are resolved.
  final Environment environment;

  /// Reads and writes the JSON payloads.
  final ObjectMapper mapper;

  /// Makes and shares the sockets, one per client name and address.
  final PhoenixSocketFactory sockets;

  /// Called on every join of every topic, in this order.
  final List<PhoenixJoinInterceptor> interceptors;

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<PhoenixChannel>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) =>
      PhoenixChannelInvocationHandler(
        metadata: metadata,
        channel: metadata.annotation<PhoenixChannel>()!,
        environment: environment,
        mapper: mapper,
        sockets: sockets,
        interceptors: interceptors,
      );
}
