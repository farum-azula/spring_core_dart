// spring_boot_starter_websocket's part of the module build: what an
// endpoint's handlers do with the classes of their messages, and the
// methods that send a value as JSON.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// The WebSocket annotations and methods, matched by URL (the generator
// does not depend on the starter).
const _endpoint =
    'package:spring_boot_starter_websocket/src/server/web_socket_endpoint.dart';
const _handler =
    'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart';

// The server's message handler: the message is read in, the reply written.
const _onMessage = TypeChecker.fromUrl(
  'package:spring_boot_starter_websocket/src/web_socket_client.dart#OnMessage',
);

// Handlers that get the connection, the status or the error: none of their
// types is read from or written to JSON.
const _events = [
  TypeChecker.fromUrl('$_endpoint#OnOpen'),
  TypeChecker.fromUrl('$_endpoint#OnClose'),
  TypeChecker.fromUrl('$_endpoint#OnError'),
];

/// The part of `spring_boot_starter_websocket` in the module build: what
/// an endpoint's handlers do with their values, and the session's and the
/// registry's methods that write a value out as JSON (`sendJson(value)`,
/// `broadcast(pattern, value)`), whose arguments' classes the build
/// describes as it does those of the `ObjectMapper`'s calls. It writes
/// nothing of its own.
///
/// ```dart
/// @OnMessage()
/// Future<Reply> onMessage(Question question) => ...
/// // Question: read in (constructor and setters); Reply: written out.
/// session.sendJson(Score(3)); // Score: written out
/// ```
final class WebSocketGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const WebSocketGeneration();

  @override
  String get package => 'spring_boot_starter_websocket';

  @override
  List<JsonWriter> get jsonWriters => const [
    JsonWriter(_handler, 'sendJson', 0),
    JsonWriter(_handler, 'broadcast', 1),
  ];

  @override
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) {
    // A message handler of an endpoint: the message (a parameter that is no
    // path variable or session; of other packages' types nothing is
    // described) is read in, the reply written out.
    if (_onMessage.isExactlyType(annotation)) {
      return (
        result: IntrospectionNeed.read,
        parameters: [
          for (final _ in method.formalParameters) IntrospectionNeed.write,
        ],
      );
    }
    if (_events.any((event) => event.isExactlyType(annotation))) {
      return (
        result: IntrospectionNeed.none,
        parameters: [
          for (final _ in method.formalParameters) IntrospectionNeed.none,
        ],
      );
    }
    return null;
  }
}
