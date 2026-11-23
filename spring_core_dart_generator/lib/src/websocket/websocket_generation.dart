// spring_boot_starter_websocket's part of the module build: what an
// endpoint's handlers do with the classes of their messages, and the
// methods that send a value as JSON.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
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

const _clientLibrary =
    'package:spring_boot_starter_websocket/src/web_socket_client.dart';
const _phoenix =
    'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel.dart';
const _endpointAnnotation = TypeChecker.fromUrl('$_endpoint#WebSocketEndpoint');
const _client = TypeChecker.fromUrl('$_clientLibrary#WebSocketClient');
const _sendMessage = TypeChecker.fromUrl('$_clientLibrary#SendMessage');
const _phoenixChannel = TypeChecker.fromUrl('$_phoenix#PhoenixChannel');
const _onEvent = TypeChecker.fromUrl('$_phoenix#OnEvent');
const _push = TypeChecker.fromUrl('$_phoenix#Push');
const _joinPayload = TypeChecker.fromUrl('$_phoenix#JoinPayload');

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
// `@JoinPayload`: a parameter of an abstract method of a `@PhoenixChannel`
// interface, whose generated client sends it when it joins.
final class _JoinPayloadPlacement extends CheckedPlacement {
  const _JoinPayloadPlacement() : super(const [_joinPayload]);

  @override
  String? problem(AnnotationSite site) =>
      site.kind == PlaceKind.parameter && site.executable?.isAbstract == true
      ? null
      : '@JoinPayload on ${site.subject}: it goes on a parameter of an '
            'abstract method of a @PhoenixChannel interface, whose client '
            'sends it when joining.';

  @override
  PlacementOwner? owner(AnnotationSite site) =>
      const PredicateOwner(_isPhoenixChannel, abstractToo: true);

  @override
  String ownerProblem(AnnotationSite site) =>
      '@JoinPayload on ${site.subject}: ${site.ownerName} is no '
      '@PhoenixChannel interface, so it would never be sent.';
}

bool _isPhoenixChannel(ClassElement element, ModuleModel module) =>
    _phoenixChannel.hasAnnotationOf(element);

final class WebSocketGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const WebSocketGeneration();

  @override
  String get package => 'spring_boot_starter_websocket';

  // The handlers of an endpoint, and the methods of a client's interface:
  // elsewhere nothing reads them.
  @override
  List<AnnotationPlacement> get placements => const [
    MethodPlacement(
      [_onMessage],
      does: 'the messages of a connection reach it',
      methodOwner: AnnotatedOwner([_endpointAnnotation, _client]),
      ownerNoun: '@WebSocketEndpoint (or @WebSocketClient interface)',
      ownerFix: '@WebSocketEndpoint(...)',
    ),
    MethodPlacement(
      _events,
      does: 'the events of a connection reach it',
      methodOwner: AnnotatedOwner([_endpointAnnotation]),
      ownerNoun: '@WebSocketEndpoint',
      ownerFix: '@WebSocketEndpoint(...)',
    ),
    MethodPlacement(
      [_sendMessage, _onEvent, _push],
      does: 'the generated client sends or receives through it',
      methodOwner: AnnotatedOwner([_client, _phoenixChannel]),
      ownerNoun: '@WebSocketClient or @PhoenixChannel interface',
      ownerFix: 'an interface with @WebSocketClient(...)',
    ),
    _JoinPayloadPlacement(),
  ];

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
