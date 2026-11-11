import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_channel.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_message.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_socket.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_socket_factory.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_invocation_handler.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_url.dart';

/// The implementation behind one `@PhoenixChannel` interface: the
/// generated class passes every method call here, and this object answers
/// it over the channels of the client's [PhoenixSocket].
///
/// `@OnEvent` methods give typed streams of a topic's events, `@Push`
/// methods push and return the reply, `leave` leaves. Each topic the
/// calls name is one [PhoenixChannelSession], joined on its first
/// listener or push and left when its last listener cancels. The
/// `PhoenixChannelFactory` creates one handler per interface;
/// applications do not use it directly. Every method, the topic and the
/// URL are checked when the bean is created, so a method the starter
/// cannot implement stops the application at startup with the reason.
///
/// Differs from Spring: Spring has no Phoenix client (see
/// `PhoenixChannel`).
final class PhoenixChannelInvocationHandler implements InvocationHandler {
  /// The implementation of the interface described by [metadata], marked
  /// with [channel]. Throws a [StateError] listing every problem of the
  /// interface: no URL or a wrong one, an unknown `vsn`, a topic
  /// parameter a method lacks, a method of the wrong shape.
  PhoenixChannelInvocationHandler({
    required InterfaceMetadata<Object> metadata,
    required this.channel,
    required Environment environment,
    required this.mapper,
    required PhoenixSocketFactory sockets,
    this.interceptors = const [],
  }) : typeName = metadata.typeName {
    final problems = <String>[];
    final url = resolveClientUrl(
      environment,
      channel.url ?? sockets.configOf(channel.name).url,
      problems,
      missing:
          'no URL: set @PhoenixChannel(url: ...) or '
          'spring.websocket.client.config.${channel.name}.url',
    );
    final topic = _resolveTopic(environment, problems);
    final kinds = <_MethodKind>[
      _OnEventKind(this),
      _PushKind(this),
      _LeaveKind(this),
      const _UnknownKind(),
    ];
    for (final method in metadata.methods) {
      final signature = _Signature.of(this, method, topic, problems);
      final plan = kinds
          .firstWhere((kind) => kind.supports(method))
          .plan(signature, problems);
      if (plan != null) {
        _plans[method] = plan;
      }
    }
    PhoenixSocket? socket;
    if (url != null) {
      try {
        socket = sockets.socket(channel.name, url: url, vsn: channel.vsn);
      } on StateError catch (error) {
        problems.add(error.message);
      }
    }
    if (problems.isNotEmpty || socket == null) {
      throw StateError(
        'Invalid Phoenix channel $typeName:\n'
        '${problems.map((p) => '  - $p').join('\n')}',
      );
    }
    this.socket = socket;
  }

  static final _topicParameter = RegExp(r'\{(\w+)\}');

  /// The name of the interface, used in error messages.
  final String typeName;

  /// The `@PhoenixChannel` annotation on the interface.
  final PhoenixChannel channel;

  /// Reads and writes the JSON payloads.
  final ObjectMapper mapper;

  /// Called on every join of every topic, in this order.
  final List<PhoenixJoinInterceptor> interceptors;

  /// The client's socket, shared with the other interfaces of its name
  /// and address.
  late final PhoenixSocket socket;

  final _plans = Map<ProxyMethod, Object? Function(List<Object?>)>.identity();
  // The topics that are joined, by their resolved name.
  final _topics = <String, _Topic>{};

  String? _resolveTopic(Environment environment, List<String> problems) {
    if (channel.topic.trim().isEmpty) {
      problems.add('no topic: set @PhoenixChannel(topic: ...)');
      return null;
    }
    try {
      return environment.resolveRequiredPlaceholders(channel.topic.trim());
    } on Object catch (error) {
      problems.add('cannot resolve the topic "${channel.topic}": $error');
      return null;
    }
  }

  // The topic's session, made (not joined yet) on first use.
  _Topic _topic(String name, Map<String, Object?>? joinPayload) {
    final existing = _topics[name];
    // A closed one ended a moment ago: its entry is about to go.
    if (existing != null &&
        existing.session.state != PhoenixChannelState.closed) {
      return existing;
    }
    final session = socket.channel(
      name,
      payload: () => _join(name, joinPayload),
    );
    final topic = _topics[name] = _Topic(name, session);
    unawaited(session.done.whenComplete(() => _forget(topic)));
    return topic;
  }

  void _forget(_Topic topic) {
    if (identical(_topics[topic.name], topic)) {
      _topics.remove(topic.name);
    }
  }

  // What one join of [topic] sends: the @JoinPayload argument, then the
  // interceptors.
  Future<Map<String, Object?>> _join(
    String topic,
    Map<String, Object?>? payload,
  ) async {
    final join = PhoenixJoin(
      clientName: channel.name,
      topic: topic,
      payload: payload,
    );
    for (final interceptor in interceptors) {
      await interceptor.apply(join);
    }
    return join.payload;
  }

  // The events named [event] of [topic] as a Stream<T>; listening joins
  // the topic, the last cancel leaves it.
  Stream<T> _events<T>(
    _Payloads<T> payloads,
    String topic,
    String event,
    Map<String, Object?>? joinPayload,
  ) {
    late final StreamController<T> controller;
    _Topic? joined;
    StreamSubscription<PhoenixMessage>? subscription;
    controller = StreamController<T>(
      onListen: () {
        final current = joined = _topic(topic, joinPayload);
        current.listeners++;
        subscription = current.session.messages.listen(
          (message) {
            if (message.event == event) {
              payloads.deliver(message.payload, controller);
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        unawaited(
          current.session.join().then(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              // A channel that ended has nothing more to say: its
              // streams are done.
              final ended = current.session.state == PhoenixChannelState.closed;
              if (!ended && !controller.isClosed) {
                controller.addError(error, stackTrace);
              }
            },
          ),
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        unawaited(subscription?.cancel());
        final current = joined;
        joined = null;
        if (current != null && --current.listeners == 0) {
          _forget(current);
          current.session.leave().ignore();
        }
      },
    );
    return controller.stream;
  }

  // Pushes [event] on [topic], joining it first, and gives the reply's
  // response as [result] reads it.
  Future<Object?> _push(
    String topic,
    Push push,
    Object? payload,
    Map<String, Object?>? joinPayload,
    _Payloads<Object?>? result,
  ) async {
    final tree = _write(payload, 'the payload of ${push.event}');
    final session = _topic(topic, joinPayload).session;
    await session.join();
    if (!push.reply) {
      await session.send(push.event, tree);
      return null;
    }
    final reply = await session.push(push.event, tree);
    return result?.read(reply.response);
  }

  Future<void> _leave(String topic) async {
    await _topics.remove(topic)?.session.leave();
  }

  // [value] as JSON: null as an empty object, a String and a Map of JSON
  // as they are, anything else through the mapper.
  Object? _write(Object? value, String what) {
    if (value == null) {
      return const <String, Object?>{};
    }
    try {
      return mapper.valueToTree(value);
    } on Object catch (error) {
      throw MessageConversionException(
        'cannot write $what of $typeName: $error',
        cause: error,
      );
    }
  }

  // The @JoinPayload argument as a JSON object.
  Map<String, Object?>? _joinObject(Object? value) {
    if (value == null) {
      return null;
    }
    final tree = _write(value, 'the @JoinPayload');
    if (tree is! Map) {
      throw MessageConversionException(
        'the @JoinPayload of $typeName must be a JSON object, not '
        '${tree.runtimeType}',
      );
    }
    return {
      for (final MapEntry(:key, :value) in tree.entries) '$key': value,
    };
  }

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) =>
      _plans[method]!(arguments);
}

/// One topic the calls of an interface joined, and how many streams
/// listen to it.
final class _Topic {
  _Topic(this.name, this.session);

  final String name;
  final PhoenixChannelSession session;
  int listeners = 0;
}

/// What a method's parameters mean: which fill the topic, which is the
/// join payload, and which are left for the method's kind.
final class _Signature {
  _Signature._(
    this.name,
    this.method,
    this._handler,
    this._template,
    this._topicParameters,
    this._joinPayload,
    this.rest,
  );

  factory _Signature.of(
    PhoenixChannelInvocationHandler handler,
    ProxyMethod method,
    String? topic,
    List<String> problems,
  ) {
    final name = '${handler.typeName}.${method.name}';
    final parameters = method.parameters;
    final topicParameters = <String, int>{};
    final matches = PhoenixChannelInvocationHandler._topicParameter.allMatches(
      topic ?? '',
    );
    for (final match in matches) {
      final parameter = match[1]!;
      final index = parameters.indexWhere((p) => p.name == parameter);
      if (index < 0) {
        problems.add(
          '$name: the topic "$topic" needs a parameter named $parameter',
        );
      } else {
        topicParameters[parameter] = index;
      }
    }
    final joinPayloads = [
      for (final (index, parameter) in parameters.indexed)
        if (parameter.annotations.whereType<JoinPayload>().isNotEmpty) index,
    ];
    if (joinPayloads.length > 1) {
      problems.add('$name has more than one @JoinPayload parameter');
    }
    for (final index in joinPayloads) {
      if (topicParameters.containsValue(index)) {
        problems.add(
          '$name: the parameter ${parameters[index].name} is both a part of '
          'the topic and the @JoinPayload',
        );
      }
    }
    return _Signature._(
      name,
      method,
      handler,
      topic ?? '',
      topicParameters,
      joinPayloads.firstOrNull,
      [
        for (var index = 0; index < parameters.length; index++)
          if (!topicParameters.containsValue(index) &&
              !joinPayloads.contains(index))
            index,
      ],
    );
  }

  /// `Type.method`, for messages.
  final String name;
  final ProxyMethod method;

  /// The parameters that are neither of the topic nor the join payload.
  final List<int> rest;

  final PhoenixChannelInvocationHandler _handler;
  final String _template;
  final Map<String, int> _topicParameters;
  final int? _joinPayload;

  bool get hasJoinPayload => _joinPayload != null;

  /// The topic of a call with [arguments].
  String topic(List<Object?> arguments) => _template.replaceAllMapped(
    PhoenixChannelInvocationHandler._topicParameter,
    (match) => '${arguments[_topicParameters[match[1]!]!]}',
  );

  /// The join payload of a call with [arguments], or `null`.
  Map<String, Object?>? joinPayload(List<Object?> arguments) =>
      switch (_joinPayload) {
        final index? => _handler._joinObject(arguments[index]),
        null => null,
      };
}

/// One kind of method a `@PhoenixChannel` interface may have: it knows
/// its methods and turns one into what a call does. The first kind that
/// supports a method takes it.
abstract interface class _MethodKind {
  bool supports(ProxyMethod method);

  /// What a call of the method does, or `null` after adding what is
  /// wrong with it to [problems].
  Object? Function(List<Object?> arguments)? plan(
    _Signature signature,
    List<String> problems,
  );
}

/// `@OnEvent('name') Stream<T> name(...)`.
final class _OnEventKind implements _MethodKind {
  _OnEventKind(this._handler);

  final PhoenixChannelInvocationHandler _handler;

  @override
  bool supports(ProxyMethod method) => method.annotation<OnEvent>() != null;

  @override
  Object? Function(List<Object?> arguments)? plan(
    _Signature signature,
    List<String> problems,
  ) {
    final method = signature.method;
    final type = method.returnType;
    final isStream =
        !method.isFuture &&
        type is GenericType<Object?> &&
        type.isSubtypeOf<Stream<Object?>>() &&
        type.arguments.length == 1;
    if (method.annotation<Push>() != null) {
      problems.add('${signature.name} has both @OnEvent and @Push');
      return null;
    }
    if (!isStream || signature.rest.isNotEmpty) {
      problems.add(
        '${signature.name}: an @OnEvent method returns Stream<T> and takes '
        'only the parameters of the topic (and a @JoinPayload)',
      );
      return null;
    }
    final event = method.annotation<OnEvent>()!.event;
    final payloads = type.arguments.single.accept(
      _PayloadTypes(_handler, 'an ${signature.name} event'),
    );
    return (arguments) => payloads.events(
      signature.topic(arguments),
      event,
      signature.joinPayload(arguments),
    );
  }
}

/// `@Push('name') Future<T> name(..., payload)`.
final class _PushKind implements _MethodKind {
  _PushKind(this._handler);

  final PhoenixChannelInvocationHandler _handler;

  @override
  bool supports(ProxyMethod method) => method.annotation<Push>() != null;

  @override
  Object? Function(List<Object?> arguments)? plan(
    _Signature signature,
    List<String> problems,
  ) {
    final method = signature.method;
    final push = method.annotation<Push>()!;
    if (!method.isFuture || signature.rest.length > 1) {
      problems.add(
        '${signature.name}: a @Push method returns a Future and takes the '
        'parameters of the topic and at most one payload (and a '
        '@JoinPayload)',
      );
      return null;
    }
    if (!push.reply && !method.isVoid) {
      problems.add(
        '${signature.name}: a @Push(reply: false) method returns '
        'Future<void>, as there is no reply to read',
      );
      return null;
    }
    final result = method.isVoid
        ? null
        : method.returnType.accept(
            _PayloadTypes(_handler, 'the reply to ${signature.name}'),
          );
    final payload = signature.rest.firstOrNull;
    return (arguments) => _handler._push(
      signature.topic(arguments),
      push,
      payload == null ? null : arguments[payload],
      signature.joinPayload(arguments),
      result,
    );
  }
}

/// `Future<void> leave(...)`, without an annotation.
final class _LeaveKind implements _MethodKind {
  _LeaveKind(this._handler);

  final PhoenixChannelInvocationHandler _handler;

  @override
  bool supports(ProxyMethod method) =>
      method.name == 'leave' && method.isFuture && method.isVoid;

  @override
  Object? Function(List<Object?> arguments)? plan(
    _Signature signature,
    List<String> problems,
  ) {
    if (signature.rest.isNotEmpty || signature.hasJoinPayload) {
      problems.add(
        '${signature.name}: leave takes only the parameters of the topic',
      );
      return null;
    }
    return (arguments) => _handler._leave(signature.topic(arguments));
  }
}

/// Any other method: a problem.
final class _UnknownKind implements _MethodKind {
  const _UnknownKind();

  @override
  bool supports(ProxyMethod method) => true;

  @override
  Object? Function(List<Object?> arguments)? plan(
    _Signature signature,
    List<String> problems,
  ) {
    problems.add(
      '${signature.name}: mark it @OnEvent (Stream<T> name(...)) or @Push '
      '(Future<T> name(..., payload)); only Future<void> leave(...) needs '
      'no annotation',
    );
    return null;
  }
}

/// Reads payloads as [T], with the type argument in scope, so a stream
/// has the declared runtime type.
final class _Payloads<T> {
  _Payloads(this._handler, this._type, this._what);

  final PhoenixChannelInvocationHandler _handler;
  final TypeInfo<T> _type;
  final String _what;

  /// [payload] (decoded JSON) as a [T]: as it is when it is one already,
  /// through the mapper otherwise.
  T read(Object? payload) {
    if (payload is T) {
      return payload;
    }
    try {
      return _handler.mapper.treeToValue<T>(payload, _type);
    } on Object catch (error) {
      throw MessageConversionException(
        'cannot read $_what as $_type: $error',
        message: _text(payload),
        cause: error,
      );
    }
  }

  /// Adds [payload] to [sink], or the error of reading it.
  void deliver(Object? payload, EventSink<T> sink) {
    final T value;
    try {
      value = read(payload);
    } on MessageConversionException catch (error, stackTrace) {
      sink.addError(error, stackTrace);
      return;
    }
    sink.add(value);
  }

  Stream<T> events(
    String topic,
    String event,
    Map<String, Object?>? joinPayload,
  ) => _handler._events<T>(this, topic, event, joinPayload);

  static String? _text(Object? payload) {
    try {
      return jsonEncode(payload);
    } on Object {
      return null;
    }
  }
}

/// Makes the [_Payloads] of a declared type.
final class _PayloadTypes implements TypeInfoVisitor<_Payloads<Object?>> {
  _PayloadTypes(this._handler, this._what);

  final PhoenixChannelInvocationHandler _handler;
  final String _what;

  @override
  _Payloads<Object?> visitClass<T>(ClassType<T> type) =>
      _Payloads<T>(_handler, type, _what);

  @override
  _Payloads<Object?> visitList<E>(ListType<E> type) =>
      _Payloads<List<E>>(_handler, type, _what);

  @override
  _Payloads<Object?> visitSet<E>(SetType<E> type) =>
      _Payloads<Set<E>>(_handler, type, _what);

  @override
  _Payloads<Object?> visitMap<K, V>(MapType<K, V> type) =>
      _Payloads<Map<K, V>>(_handler, type, _what);

  @override
  _Payloads<Object?> visitEnum<E extends Enum>(EnumType<E> type) =>
      _Payloads<E>(_handler, type, _what);

  @override
  _Payloads<Object?> visitGeneric<T>(GenericType<T> type) =>
      _Payloads<T>(_handler, type, _what);

  @override
  _Payloads<Object?> visitDynamic(DynamicType type) =>
      _Payloads<Object?>(_handler, type, _what);
}
