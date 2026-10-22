// Clients and models as an application writes them, with the code the
// generator writes for them (introspection and the interface
// implementations), so the starter is tested without code generation.
import 'dart:typed_data';

import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

class ChatMessage {
  const ChatMessage({required this.from, required this.text});
  final String from;
  final String text;
}

@WebSocketClient('chat', url: r'${chat.url}', protocols: ['chat.v1'])
abstract interface class ChatSocket {
  @OnMessage()
  Stream<ChatMessage> messages();

  @OnMessage()
  Stream<String> raw();

  @OnMessage()
  Stream<Uint8List> binary();

  @SendMessage()
  Future<void> send(ChatMessage message);

  @SendMessage()
  Future<void> sendText(String text);

  @SendMessage()
  Future<void> sendBytes(Uint8List bytes);

  Future<void> connect();

  Future<void> close();
}

@WebSocketClient('broken', url: 'http://broken.test')
abstract interface class BrokenSocket {
  @OnMessage()
  Future<String> notAStream();

  @SendMessage()
  Future<void> two(String a, String b);

  Future<String> other();
}

// ---- generated ----

final chatMessageIntrospection = BeanIntrospection<ChatMessage>(
  properties: [
    BeanProperty<ChatMessage>(
      'from',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (m) => m.from,
    ),
    BeanProperty<ChatMessage>(
      'text',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (m) => m.text,
    ),
  ],
  constructor: BeanConstructor<ChatMessage>(
    parameters: const [
      BeanParameter(
        'from',
        type: ClassType<String>(),
        symbol: #from,
        isRequired: true,
      ),
      BeanParameter(
        'text',
        type: ClassType<String>(),
        symbol: #text,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(ChatMessage.new, positional, named) as ChatMessage,
  ),
);

class ChatSocketImpl implements ChatSocket {
  ChatSocketImpl(this._handler, this._metadata);

  static ChatSocketImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<ChatSocket>(
      typeName: 'ChatSocket',
      annotations: const [
        WebSocketClient('chat', url: r'${chat.url}', protocols: ['chat.v1']),
      ],
      methods: [
        ProxyMethod(
          'messages',
          returnType: const GenericType<Stream<ChatMessage>>([
            ClassType<ChatMessage>(),
          ]),
          annotations: const [OnMessage()],
          call: (target, arguments) => (target as ChatSocket).messages(),
        ),
        ProxyMethod(
          'raw',
          returnType: const GenericType<Stream<String>>([ClassType<String>()]),
          annotations: const [OnMessage()],
          call: (target, arguments) => (target as ChatSocket).raw(),
        ),
        ProxyMethod(
          'binary',
          returnType: const GenericType<Stream<Uint8List>>([
            ClassType<Uint8List>(),
          ]),
          annotations: const [OnMessage()],
          call: (target, arguments) => (target as ChatSocket).binary(),
        ),
        ProxyMethod(
          'send',
          parameters: const [
            BeanParameter(
              'message',
              type: ClassType<ChatMessage>(),
              isRequired: true,
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [SendMessage()],
          call: (target, arguments) =>
              (target as ChatSocket).send(arguments[0]! as ChatMessage),
        ),
        ProxyMethod(
          'sendText',
          parameters: const [
            BeanParameter('text', type: ClassType<String>(), isRequired: true),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [SendMessage()],
          call: (target, arguments) =>
              (target as ChatSocket).sendText(arguments[0]! as String),
        ),
        ProxyMethod(
          'sendBytes',
          parameters: const [
            BeanParameter(
              'bytes',
              type: ClassType<Uint8List>(),
              isRequired: true,
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [SendMessage()],
          call: (target, arguments) =>
              (target as ChatSocket).sendBytes(arguments[0]! as Uint8List),
        ),
        ProxyMethod(
          'connect',
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          call: (target, arguments) => (target as ChatSocket).connect(),
        ),
        ProxyMethod(
          'close',
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          call: (target, arguments) => (target as ChatSocket).close(),
        ),
      ],
    );
    return ChatSocketImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<ChatSocket> _metadata;

  @override
  Stream<ChatMessage> messages() =>
      _handler.invoke(_metadata.methods[0], const []) as Stream<ChatMessage>;

  @override
  Stream<String> raw() =>
      _handler.invoke(_metadata.methods[1], const []) as Stream<String>;

  @override
  Stream<Uint8List> binary() =>
      _handler.invoke(_metadata.methods[2], const []) as Stream<Uint8List>;

  @override
  Future<void> send(ChatMessage message) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[3], [message]));

  @override
  Future<void> sendText(String text) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[4], [text]));

  @override
  Future<void> sendBytes(Uint8List bytes) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[5], [bytes]));

  @override
  Future<void> connect() =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[6], const []));

  @override
  Future<void> close() =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[7], const []));
}

class BrokenSocketImpl implements BrokenSocket {
  BrokenSocketImpl(this._handler, this._metadata);

  static BrokenSocketImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<BrokenSocket>(
      typeName: 'BrokenSocket',
      annotations: const [WebSocketClient('broken', url: 'http://broken.test')],
      methods: [
        ProxyMethod(
          'notAStream',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [OnMessage()],
          call: (target, arguments) => (target as BrokenSocket).notAStream(),
        ),
        ProxyMethod(
          'two',
          parameters: const [
            BeanParameter('a', type: ClassType<String>(), isRequired: true),
            BeanParameter('b', type: ClassType<String>(), isRequired: true),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [SendMessage()],
          call: (target, arguments) => (target as BrokenSocket).two(
            arguments[0]! as String,
            arguments[1]! as String,
          ),
        ),
        ProxyMethod(
          'other',
          returnType: const ClassType<String>(),
          isFuture: true,
          call: (target, arguments) => (target as BrokenSocket).other(),
        ),
      ],
    );
    return BrokenSocketImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<BrokenSocket> _metadata;

  @override
  Future<String> notAStream() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));

  @override
  Future<void> two(String a, String b) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[1], [a, b]));

  @override
  Future<String> other() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], const []));
}

/// The application module: the chat client (primary, like the generator
/// makes it).
final appModule = BeanModule(
  'app',
  [
    BeanDefinition<ChatSocket>(
      name: 'chatSocket',
      primary: true,
      create: ChatSocketImpl.$create,
    ),
  ],
  introspections: [chatMessageIntrospection],
);

/// A module with an invalid client.
final brokenModule = BeanModule('broken', [
  BeanDefinition<BrokenSocket>(
    name: 'brokenSocket',
    primary: true,
    create: BrokenSocketImpl.$create,
  ),
]);
