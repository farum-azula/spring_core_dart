// Phoenix channels and models as an application writes them, with the
// code the generator writes for them (introspection and the interface
// implementations), so the starter is tested without code generation.
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

import 'chat.dart';

class Ack {
  const Ack({required this.id});
  final int id;
}

class RoomJoin {
  const RoomJoin({required this.since});
  final int since;
}

@PhoenixChannel('chat', topic: 'room:{id}', url: r'${chat.url}')
abstract interface class Room {
  @OnEvent('new_msg')
  Stream<ChatMessage> messages(String id);

  @OnEvent('new_msg')
  Stream<Map<String, Object?>> raw(String id);

  @OnEvent('new_msg')
  Stream<ChatMessage> messagesSince(String id, @JoinPayload() RoomJoin join);

  @Push('new_msg')
  Future<Ack> send(String id, ChatMessage message);

  @Push('seen')
  Future<void> seen(String id, Map<String, Object?> what);

  @Push('typing', reply: false)
  Future<void> typing(String id);

  @Push('history')
  Future<List<ChatMessage>> history(String id);

  Future<void> leave(String id);
}

@PhoenixChannel('chat', topic: r'${lobby.topic}', url: r'${chat.url}')
abstract interface class Lobby {
  @OnEvent('tick')
  Stream<int> ticks();

  @Push('ping')
  Future<String> ping();
}

@PhoenixChannel('broken', topic: 'room:{id}', url: 'http://broken.test')
abstract interface class BrokenRoom {
  @OnEvent('a')
  Future<String> notAStream(String id);

  @OnEvent('b')
  Stream<String> noTopicParameter();

  @Push('c')
  Future<void> twoPayloads(String id, String a, String b);

  @Push('d', reply: false)
  Future<String> noReply(String id);

  @OnEvent('e')
  @Push('e')
  Stream<String> both(String id);

  Future<String> other(String id);

  Future<void> leave(String id, String extra);
}

@PhoenixChannel('odd', topic: 'lobby', url: 'ws://odd.test/ws', vsn: '9.9.9')
abstract interface class OddLobby {
  Future<void> leave();
}

// ---- generated ----

final ackIntrospection = BeanIntrospection<Ack>(
  properties: [
    BeanProperty<Ack>(
      'id',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (ack) => ack.id,
    ),
  ],
  constructor: BeanConstructor<Ack>(
    parameters: const [
      BeanParameter(
        'id',
        type: ClassType<int>(),
        symbol: #id,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Ack.new, positional, named) as Ack,
  ),
);

final roomJoinIntrospection = BeanIntrospection<RoomJoin>(
  properties: [
    BeanProperty<RoomJoin>(
      'since',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (join) => join.since,
    ),
  ],
  constructor: BeanConstructor<RoomJoin>(
    parameters: const [
      BeanParameter(
        'since',
        type: ClassType<int>(),
        symbol: #since,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(RoomJoin.new, positional, named) as RoomJoin,
  ),
);

const _id = BeanParameter('id', type: ClassType<String>(), isRequired: true);
const _messageStream = GenericType<Stream<ChatMessage>>([
  ClassType<ChatMessage>(),
]);
const _stringStream = GenericType<Stream<String>>([ClassType<String>()]);

class RoomImpl implements Room {
  RoomImpl(this._handler, this._metadata);

  static RoomImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<Room>(
      typeName: 'Room',
      annotations: const [
        PhoenixChannel('chat', topic: 'room:{id}', url: r'${chat.url}'),
      ],
      methods: [
        ProxyMethod(
          'messages',
          parameters: const [_id],
          returnType: _messageStream,
          annotations: const [OnEvent('new_msg')],
        ),
        ProxyMethod(
          'raw',
          parameters: const [_id],
          returnType: const GenericType<Stream<Map<String, Object?>>>([
            MapType<String, Object?>(ClassType<String>(), DynamicType()),
          ]),
          annotations: const [OnEvent('new_msg')],
        ),
        ProxyMethod(
          'messagesSince',
          parameters: const [
            _id,
            BeanParameter(
              'join',
              type: ClassType<RoomJoin>(),
              isRequired: true,
              annotations: [JoinPayload()],
            ),
          ],
          returnType: _messageStream,
          annotations: const [OnEvent('new_msg')],
        ),
        ProxyMethod(
          'send',
          parameters: const [
            _id,
            BeanParameter(
              'message',
              type: ClassType<ChatMessage>(),
              isRequired: true,
            ),
          ],
          returnType: const ClassType<Ack>(),
          isFuture: true,
          annotations: const [Push('new_msg')],
        ),
        ProxyMethod(
          'seen',
          parameters: const [
            _id,
            BeanParameter(
              'what',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [Push('seen')],
        ),
        ProxyMethod(
          'typing',
          parameters: const [_id],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [Push('typing', reply: false)],
        ),
        ProxyMethod(
          'history',
          parameters: const [_id],
          returnType: const ListType<ChatMessage>(ClassType<ChatMessage>()),
          isFuture: true,
          annotations: const [Push('history')],
        ),
        ProxyMethod(
          'leave',
          parameters: const [_id],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
        ),
      ],
    );
    return RoomImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<Room> _metadata;

  @override
  Stream<ChatMessage> messages(String id) =>
      _handler.invoke(_metadata.methods[0], [id])! as Stream<ChatMessage>;

  @override
  Stream<Map<String, Object?>> raw(String id) =>
      _handler.invoke(_metadata.methods[1], [id])!
          as Stream<Map<String, Object?>>;

  @override
  Stream<ChatMessage> messagesSince(String id, RoomJoin join) =>
      _handler.invoke(_metadata.methods[2], [id, join])! as Stream<ChatMessage>;

  @override
  Future<Ack> send(String id, ChatMessage message) =>
      retypeFuture<Ack>(_handler.invoke(_metadata.methods[3], [id, message]));

  @override
  Future<void> seen(String id, Map<String, Object?> what) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[4], [id, what]));

  @override
  Future<void> typing(String id) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[5], [id]));

  @override
  Future<List<ChatMessage>> history(String id) =>
      retypeFuture<List<ChatMessage>>(
        _handler.invoke(_metadata.methods[6], [id]),
      );

  @override
  Future<void> leave(String id) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[7], [id]));
}

class LobbyImpl implements Lobby {
  LobbyImpl(this._handler, this._metadata);

  static LobbyImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<Lobby>(
      typeName: 'Lobby',
      annotations: const [
        PhoenixChannel('chat', topic: r'${lobby.topic}', url: r'${chat.url}'),
      ],
      methods: [
        ProxyMethod(
          'ticks',
          returnType: const GenericType<Stream<int>>([ClassType<int>()]),
          annotations: const [OnEvent('tick')],
        ),
        ProxyMethod(
          'ping',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [Push('ping')],
        ),
      ],
    );
    return LobbyImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<Lobby> _metadata;

  @override
  Stream<int> ticks() =>
      _handler.invoke(_metadata.methods[0], const [])! as Stream<int>;

  @override
  Future<String> ping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], const []));
}

/// The handler of an invalid interface, which fails when it is made.
InvocationHandler brokenRoomHandler(DependencyResolver r) {
  const a = BeanParameter('a', type: ClassType<String>(), isRequired: true);
  const b = BeanParameter('b', type: ClassType<String>(), isRequired: true);
  return InterfaceProxies.handlerFor(
    r,
    InterfaceMetadata<BrokenRoom>(
      typeName: 'BrokenRoom',
      annotations: const [
        PhoenixChannel('broken', topic: 'room:{id}', url: 'http://broken.test'),
      ],
      methods: [
        ProxyMethod(
          'notAStream',
          parameters: const [_id],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [OnEvent('a')],
        ),
        ProxyMethod(
          'noTopicParameter',
          returnType: _stringStream,
          annotations: const [OnEvent('b')],
        ),
        ProxyMethod(
          'twoPayloads',
          parameters: const [_id, a, b],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [Push('c')],
        ),
        ProxyMethod(
          'noReply',
          parameters: const [_id],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [Push('d', reply: false)],
        ),
        ProxyMethod(
          'both',
          parameters: const [_id],
          returnType: _stringStream,
          annotations: const [OnEvent('e'), Push('e')],
        ),
        ProxyMethod(
          'other',
          parameters: const [_id],
          returnType: const ClassType<String>(),
          isFuture: true,
        ),
        ProxyMethod(
          'leave',
          parameters: const [
            _id,
            BeanParameter(
              'extra',
              type: ClassType<String>(),
              isRequired: true,
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
        ),
      ],
    ),
  );
}

/// The handler of an interface with a `vsn` nobody speaks.
InvocationHandler oddLobbyHandler(DependencyResolver r) =>
    InterfaceProxies.handlerFor(
      r,
      InterfaceMetadata<OddLobby>(
        typeName: 'OddLobby',
        annotations: const [
          PhoenixChannel(
            'odd',
            topic: 'lobby',
            url: 'ws://odd.test/ws',
            vsn: '9.9.9',
          ),
        ],
        methods: [
          ProxyMethod(
            'leave',
            returnType: const DynamicType(),
            isFuture: true,
            isVoid: true,
          ),
        ],
      ),
    );

/// The application module: the room and the lobby (primary, like the
/// generator makes them).
final roomModule = BeanModule(
  'rooms',
  [
    BeanDefinition<Room>(
      name: 'room',
      primary: true,
      create: RoomImpl.$create,
    ),
    BeanDefinition<Lobby>(
      name: 'lobby',
      primary: true,
      create: LobbyImpl.$create,
    ),
  ],
  introspections: [
    chatMessageIntrospection,
    ackIntrospection,
    roomJoinIntrospection,
  ],
);

/// A module with an invalid channel, made by [handler].
BeanModule brokenRoomModule(
  InvocationHandler Function(DependencyResolver r) handler,
) => BeanModule('broken', [
  BeanDefinition<InvocationHandler>(name: 'brokenRoom', create: handler),
]);
