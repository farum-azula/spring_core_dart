// Realtime channels and models as an application writes them, with the
// code the generator writes for them (introspection and the interface
// implementations), so the declared layer is tested without code
// generation.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

import 'realtime_support.dart';

class Cursor {
  const Cursor({required this.x, required this.y});
  final int x;
  final int y;
}

class Member {
  const Member({required this.name, this.typing = false});
  final String name;
  final bool typing;
}

@RealtimeChannel(r'${rooms.prefix:room}:{id}', self: true)
abstract interface class Room {
  @Broadcast('cursor')
  Stream<Cursor> cursors(String id);

  @Broadcast('cursor')
  Stream<Map<String, Object?>> rawCursors(String id);

  @Broadcast('cursor')
  Future<void> moveCursor(String id, Cursor cursor);

  @Broadcast(r'${rooms.ping:ping}')
  Future<void> ping(String id);

  @Presence()
  Stream<List<Member>> members(String id);

  @Presence()
  Stream<List<RealtimePresence>> presences(String id);

  @Presence()
  Future<void> join(String id, Member me);

  @Presence()
  Future<void> leave(String id);

  @PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}')
  Stream<RealtimeRowChange> messages(String id);

  @PostgresChanges(
    schema: 'app',
    table: r'${rooms.table:messages}',
    filter: 'room_id=eq.{id},author=in.({authors})',
    kind: RealtimeChangeKind.insert,
  )
  Stream<RealtimeRowChange> messagesOf(String id, List<String> authors);
}

/// A method kind of the application's own.
class Typing {
  const Typing();
}

@RealtimeChannel(
  'desk:#{authentication.name}',
  private: true,
  ack: true,
  presenceKey: '#{authentication.name}',
)
abstract interface class Desk {
  @Broadcast('note')
  Stream<String> notes();

  @Broadcast('note')
  Future<void> note(@RequestBody() String text);

  @Presence()
  Future<void> sit(Map<String, Object?> state);

  @Typing()
  Future<void> typing();
}

@RealtimeChannel('room:{id}')
abstract interface class BrokenRoom {
  @Broadcast('a')
  Future<String> wrongReturn(String id);

  @Broadcast('b')
  Stream<String> extraParameter(String id, String extra);

  @Broadcast('c')
  Future<void> twoPayloads(String id, String a, String b);

  @Broadcast('d')
  Stream<String> noId();

  @Broadcast(r'${no.such.event}')
  Stream<String> noProperty(String id);

  @Presence()
  Stream<Member> notAList(String id);

  @Presence()
  Future<int> wrongPresence(String id);

  @PostgresChanges(table: 'x')
  Stream<Map<String, Object?>> wrongStream(String id);

  @PostgresChanges(table: 'x', filter: 'a=eq.{nope}')
  Stream<RealtimeRowChange> badFilter(String id);

  Future<void> unmarked(String id);
}

// ---- generated ----

final cursorIntrospection = BeanIntrospection<Cursor>(
  properties: [
    BeanProperty<Cursor>(
      'x',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (cursor) => cursor.x,
    ),
    BeanProperty<Cursor>(
      'y',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (cursor) => cursor.y,
    ),
  ],
  constructor: BeanConstructor<Cursor>(
    parameters: const [
      BeanParameter('x', type: ClassType<int>(), symbol: #x, isRequired: true),
      BeanParameter('y', type: ClassType<int>(), symbol: #y, isRequired: true),
    ],
    create: (positional, named) =>
        Function.apply(Cursor.new, positional, named) as Cursor,
  ),
);

final memberIntrospection = BeanIntrospection<Member>(
  properties: [
    BeanProperty<Member>(
      'name',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (member) => member.name,
    ),
    BeanProperty<Member>(
      'typing',
      type: bool,
      typeInfo: const ClassType<bool>(),
      get: (member) => member.typing,
    ),
  ],
  constructor: BeanConstructor<Member>(
    parameters: const [
      BeanParameter(
        'name',
        type: ClassType<String>(),
        symbol: #name,
        isRequired: true,
      ),
      BeanParameter('typing', type: ClassType<bool>(), symbol: #typing),
    ],
    create: (positional, named) =>
        Function.apply(Member.new, positional, named) as Member,
  ),
);

const _id = BeanParameter('id', type: ClassType<String>(), isRequired: true);
const _void = DynamicType();
const _strings = GenericType<Stream<String>>([ClassType<String>()]);
const _changes = GenericType<Stream<RealtimeRowChange>>([
  ClassType<RealtimeRowChange>(),
]);
const _json = MapType<String, Object?>(ClassType<String>(), DynamicType());

class RoomImpl implements Room {
  RoomImpl(this._handler, this._metadata);

  static RoomImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<Room>(
      typeName: 'Room',
      annotations: const [
        RealtimeChannel(r'${rooms.prefix:room}:{id}', self: true),
      ],
      methods: [
        ProxyMethod(
          'cursors',
          parameters: const [_id],
          returnType: const GenericType<Stream<Cursor>>([ClassType<Cursor>()]),
          annotations: const [Broadcast('cursor')],
        ),
        ProxyMethod(
          'rawCursors',
          parameters: const [_id],
          returnType: const GenericType<Stream<Map<String, Object?>>>([_json]),
          annotations: const [Broadcast('cursor')],
        ),
        ProxyMethod(
          'moveCursor',
          parameters: const [
            _id,
            BeanParameter(
              'cursor',
              type: ClassType<Cursor>(),
              isRequired: true,
            ),
          ],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Broadcast('cursor')],
        ),
        ProxyMethod(
          'ping',
          parameters: const [_id],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Broadcast(r'${rooms.ping:ping}')],
        ),
        ProxyMethod(
          'members',
          parameters: const [_id],
          returnType: const GenericType<Stream<List<Member>>>([
            ListType<Member>(ClassType<Member>()),
          ]),
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'presences',
          parameters: const [_id],
          returnType: const GenericType<Stream<List<RealtimePresence>>>([
            ListType<RealtimePresence>(ClassType<RealtimePresence>()),
          ]),
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'join',
          parameters: const [
            _id,
            BeanParameter('me', type: ClassType<Member>(), isRequired: true),
          ],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'leave',
          parameters: const [_id],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'messages',
          parameters: const [_id],
          returnType: _changes,
          annotations: const [
            PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}'),
          ],
        ),
        ProxyMethod(
          'messagesOf',
          parameters: const [
            _id,
            BeanParameter(
              'authors',
              type: ListType<String>(ClassType<String>()),
              isRequired: true,
            ),
          ],
          returnType: _changes,
          annotations: const [
            PostgresChanges(
              schema: 'app',
              table: r'${rooms.table:messages}',
              filter: 'room_id=eq.{id},author=in.({authors})',
              kind: RealtimeChangeKind.insert,
            ),
          ],
        ),
      ],
    );
    return RoomImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<Room> _metadata;

  @override
  Stream<Cursor> cursors(String id) =>
      _handler.invoke(_metadata.methods[0], [id])! as Stream<Cursor>;

  @override
  Stream<Map<String, Object?>> rawCursors(String id) =>
      _handler.invoke(_metadata.methods[1], [id])!
          as Stream<Map<String, Object?>>;

  @override
  Future<void> moveCursor(String id, Cursor cursor) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[2], [id, cursor]));

  @override
  Future<void> ping(String id) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[3], [id]));

  @override
  Stream<List<Member>> members(String id) =>
      _handler.invoke(_metadata.methods[4], [id])! as Stream<List<Member>>;

  @override
  Stream<List<RealtimePresence>> presences(String id) =>
      _handler.invoke(_metadata.methods[5], [id])!
          as Stream<List<RealtimePresence>>;

  @override
  Future<void> join(String id, Member me) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[6], [id, me]));

  @override
  Future<void> leave(String id) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[7], [id]));

  @override
  Stream<RealtimeRowChange> messages(String id) =>
      _handler.invoke(_metadata.methods[8], [id])! as Stream<RealtimeRowChange>;

  @override
  Stream<RealtimeRowChange> messagesOf(String id, List<String> authors) =>
      _handler.invoke(_metadata.methods[9], [id, authors])!
          as Stream<RealtimeRowChange>;
}

class DeskImpl implements Desk {
  DeskImpl(this._handler, this._metadata);

  static DeskImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<Desk>(
      typeName: 'Desk',
      annotations: const [
        RealtimeChannel(
          'desk:#{authentication.name}',
          private: true,
          ack: true,
          presenceKey: '#{authentication.name}',
        ),
      ],
      methods: [
        ProxyMethod(
          'notes',
          returnType: _strings,
          annotations: const [Broadcast('note')],
        ),
        ProxyMethod(
          'note',
          parameters: const [
            BeanParameter(
              'text',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Broadcast('note')],
        ),
        ProxyMethod(
          'sit',
          parameters: const [
            BeanParameter('state', type: _json, isRequired: true),
          ],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'typing',
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Typing()],
        ),
      ],
    );
    return DeskImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<Desk> _metadata;

  @override
  Stream<String> notes() =>
      _handler.invoke(_metadata.methods[0], const [])! as Stream<String>;

  @override
  Future<void> note(String text) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[1], [text]));

  @override
  Future<void> sit(Map<String, Object?> state) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[2], [state]));

  @override
  Future<void> typing() =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[3], const []));
}

/// The handler of an invalid interface, which fails when it is made.
InvocationHandler brokenRoomHandler(DependencyResolver r) {
  const a = BeanParameter('a', type: ClassType<String>(), isRequired: true);
  const b = BeanParameter('b', type: ClassType<String>(), isRequired: true);
  return InterfaceProxies.handlerFor(
    r,
    InterfaceMetadata<BrokenRoom>(
      typeName: 'BrokenRoom',
      annotations: const [RealtimeChannel('room:{id}')],
      methods: [
        ProxyMethod(
          'wrongReturn',
          parameters: const [_id],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [Broadcast('a')],
        ),
        ProxyMethod(
          'extraParameter',
          parameters: const [
            _id,
            BeanParameter(
              'extra',
              type: ClassType<String>(),
              isRequired: true,
            ),
          ],
          returnType: _strings,
          annotations: const [Broadcast('b')],
        ),
        ProxyMethod(
          'twoPayloads',
          parameters: const [_id, a, b],
          returnType: _void,
          isFuture: true,
          isVoid: true,
          annotations: const [Broadcast('c')],
        ),
        ProxyMethod(
          'noId',
          returnType: _strings,
          annotations: const [Broadcast('d')],
        ),
        ProxyMethod(
          'noProperty',
          parameters: const [_id],
          returnType: _strings,
          annotations: const [Broadcast(r'${no.such.event}')],
        ),
        ProxyMethod(
          'notAList',
          parameters: const [_id],
          returnType: const GenericType<Stream<Member>>([ClassType<Member>()]),
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'wrongPresence',
          parameters: const [_id],
          returnType: const ClassType<int>(),
          isFuture: true,
          annotations: const [Presence()],
        ),
        ProxyMethod(
          'wrongStream',
          parameters: const [_id],
          returnType: const GenericType<Stream<Map<String, Object?>>>([_json]),
          annotations: const [PostgresChanges(table: 'x')],
        ),
        ProxyMethod(
          'badFilter',
          parameters: const [_id],
          returnType: _changes,
          annotations: const [
            PostgresChanges(table: 'x', filter: 'a=eq.{nope}'),
          ],
        ),
        ProxyMethod(
          'unmarked',
          parameters: const [_id],
          returnType: _void,
          isFuture: true,
          isVoid: true,
        ),
      ],
    ),
  );
}

/// The application's own method kind: `@Typing()` broadcasts `typing`.
final class TypingOperation implements RealtimeChannelOperation {
  @override
  Object? Function(List<Object?>)? plan(RealtimeChannelMethod method) {
    if (method.method.annotation<Typing>() == null) {
      return null;
    }
    return (arguments) => method.session(arguments).send('typing');
  }
}

/// The application module: the room and the desk (primary, like the
/// generator makes them), and the application's method kind.
final roomModule = BeanModule(
  'rooms',
  [
    BeanDefinition<Room>(name: 'room', primary: true, create: RoomImpl.$create),
    BeanDefinition<Desk>(name: 'desk', primary: true, create: DeskImpl.$create),
    BeanDefinition<TypingOperation>(
      name: 'typingOperation',
      types: const [TypingOperation, RealtimeChannelOperation],
      create: (_) => TypingOperation(),
    ),
  ],
  introspections: [cursorIntrospection, memberIntrospection],
);

/// A module with an invalid channel.
final brokenRoomModule = BeanModule('broken', [
  BeanDefinition<InvocationHandler>(
    name: 'brokenRoom',
    create: brokenRoomHandler,
  ),
]);
