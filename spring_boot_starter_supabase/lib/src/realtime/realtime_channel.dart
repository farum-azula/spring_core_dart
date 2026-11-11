import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/expression/call_template.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';
import 'package:spring_boot_starter_supabase/src/realtime/supabase_realtime.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';

/// Marks an interface whose methods are the streams and messages of one
/// channel of Supabase Realtime; the generator writes the bean.
///
/// ```dart
/// @RealtimeChannel('room:{id}', presenceKey: '#{authentication.name}')
/// abstract interface class Room {
///   @Broadcast('cursor')
///   Stream<Cursor> cursors(String id);
///
///   @Broadcast('cursor')
///   Future<void> moveCursor(String id, Cursor cursor);
///
///   @Presence()
///   Stream<List<Member>> members(String id);
///
///   @Presence()
///   Future<void> join(String id, Member me);
///
///   @PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}')
///   Stream<RealtimeRowChange> messages(String id);
/// }
/// ```
///
/// The channels of the application are in one place with what travels on
/// them, typed, and the bean takes AOP like any other (`@PreAuthorize`).
///
/// The [name] takes `${property}` from the configuration, `{name}` from
/// the method's parameter of that name, and SpEL in `#{...}` (the
/// parameters as `#name`, `authentication` and `principal` as in
/// `@PreAuthorize`, beans as `@name`), so one interface serves every
/// room. Each name that comes out is one channel: joined when one of its
/// methods is first used, and left when its last stream is cancelled and
/// nothing is tracked.
///
/// For a channel whose name or use is not known when the application is
/// built, use `SupabaseRealtime.channel`.
///
/// Supabase (JavaScript): `supabase.channel(name, {config})`.
@InterfaceProxy(primary: true)
class RealtimeChannel {
  /// Marks the interface of the channel [name] (the topic
  /// `realtime:<name>`).
  const RealtimeChannel(
    this.name, {
    this.private = false,
    this.self = false,
    this.ack = false,
    this.presenceKey,
    this.qualifiers = const [],
    this.primary = true,
  });

  /// The name of the channel, such as `lobby` or `room:{id}`.
  final String name;

  /// Whether the channel is private: its members are authorized by the
  /// policies of row-level security on `realtime.messages`.
  final bool private;

  /// Whether this client receives its own broadcasts.
  final bool self;

  /// Whether a `@Broadcast` method that sends waits until the server
  /// took the message.
  final bool ack;

  /// The key this client is present under, with the same placeholders as
  /// the [name]: `#{authentication.name}` makes the devices of one user
  /// one member. Without it the server makes one up per connection.
  final String? presenceKey;

  /// Qualifiers of the bean, as `@Qualifier` gives them.
  final List<String> qualifiers;

  /// Whether the bean is primary among the beans of its interface.
  final bool primary;
}

/// On a method of a [RealtimeChannel] interface: the broadcasts named
/// [event], received or sent.
///
/// - `Stream<T> name(...)`: the broadcasts of the other clients, each
///   payload read as `T` with the `ObjectMapper` (a `Map<String,
///   Object?>` as it is). A payload that cannot be read is an error event
///   (`MessageConversionException`), and the stream goes on.
/// - `Future<void> name(..., payload)`: sends one. The payload is the
///   parameter the channel's name does not use (or the one marked
///   `@RequestBody()`), written as JSON; without one, `{}` is sent.
///
/// ```dart
/// @Broadcast('cursor')
/// Stream<Cursor> cursors(String id);
///
/// @Broadcast('cursor')
/// Future<void> moveCursor(String id, Cursor cursor);
/// ```
///
/// Supabase (JavaScript): `channel.on('broadcast', {event}, fn)` and
/// `channel.send({type: 'broadcast', event, payload})`.
@BeanMethodAnnotation()
class Broadcast {
  /// The broadcasts named [event] (`${...}` allowed).
  const Broadcast(this.event);

  /// The name of the event.
  final String event;
}

/// On a method of a [RealtimeChannel] interface: who is present on the
/// channel, or this client's own presence.
///
/// - `Stream<List<T>> name(...)`: everyone present, now and after each
///   change; what each tracked is read as `T` with the `ObjectMapper`
///   (`RealtimePresence` gives the key and the reference too).
/// - `Future<void> name(..., state)`: makes this client present with the
///   state, the parameter the channel's name does not use, written as a
///   JSON object.
/// - `Future<void> name(...)` without such a parameter: ends this
///   client's presence.
///
/// ```dart
/// @Presence()
/// Stream<List<Member>> members(String id);
///
/// @Presence()
/// Future<void> join(String id, Member me);
///
/// @Presence()
/// Future<void> leave(String id);
/// ```
///
/// Supabase (JavaScript): `channel.on('presence', {event: 'sync'}, fn)`,
/// `channel.track(state)` and `channel.untrack()`.
@BeanMethodAnnotation()
class Presence {
  /// Marks a presence method.
  const Presence();
}

/// On a method of a [RealtimeChannel] interface that returns
/// `Stream<RealtimeRowChange>`: the changes of the rows of a table.
///
/// The [filter] takes the placeholders of the channel's name; what a
/// parameter or an expression gives is one value of the filter, never a
/// part of it (see [PostgresFilterEncoder]).
///
/// ```dart
/// @PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}')
/// Stream<RealtimeRowChange> messages(String id);
///
/// @PostgresChanges(table: 'messages', kind: RealtimeChangeKind.insert)
/// Stream<RealtimeRowChange> newMessages();
/// ```
///
/// Supabase (JavaScript):
/// `channel.on('postgres_changes', {event, schema, table, filter}, fn)`.
@BeanMethodAnnotation()
class PostgresChanges {
  /// The changes of [schema].[table] (`${...}` allowed in both).
  const PostgresChanges({
    required this.table,
    this.schema = 'public',
    this.filter,
    this.kind,
  });

  /// The table; it must be in the publication `supabase_realtime`.
  final String table;

  /// The schema of the table.
  final String schema;

  /// Narrows the rows on the server, such as `room_id=eq.{id}`; see
  /// `RealtimeChannelSession.postgresChanges`.
  final String? filter;

  /// Only inserts, updates or deletes; every change without it.
  final RealtimeChangeKind? kind;
}

/// Values of a Postgres Changes filter: a value cannot add a condition
/// or close a list. One with a `,`, `(`, `)`, `{`, `}`, `"` or `\` in
/// it, a blank at an end, or the word `null` is put in double quotes,
/// as PostgREST writes it: Realtime reads the values of `in.(…)` as an
/// array of PostgreSQL, where a brace ends the array and `null` is no
/// value. A list gives its values separated by commas, for
/// `in.({ids})`. No value at all, an empty one (Realtime's filter has
/// no way to write it: `""` matches no row) and control characters are
/// refused.
///
/// ```dart
/// // 'title=eq.{title}' with title = 'a,b' gives title=eq."a,b"
/// // 'id=in.({ids})' with ids = [1, 2] gives id=in.(1,2)
/// ```
final class PostgresFilterEncoder implements TemplateEncoder {
  /// The encoder.
  const PostgresFilterEncoder();

  static final _reserved = RegExp(r'[,(){}"\\]');

  @override
  String literal(String text) => text;

  @override
  String value(Object? value, String expression) => switch (value) {
    final Iterable<Object?> values =>
      values.map((value) => _one(value, expression)).join(','),
    _ => _one(value, expression),
  };

  String _one(Object? value, String expression) {
    final text = switch (value) {
      null => throw ArgumentError('$expression gave no value for a filter'),
      final Enum value => value.name,
      _ => '$value',
    };
    if (text.isEmpty) {
      throw ArgumentError(
        '$expression gave an empty value, which a filter of Realtime cannot '
        'say: subscribe without the filter and test the rows',
      );
    }
    if (text.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
      throw ArgumentError('$expression gave a value with a control character');
    }
    if (text == text.trim() &&
        !_reserved.hasMatch(text) &&
        text.toLowerCase() != 'null') {
      return text;
    }
    return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}

/// One kind of method of a [RealtimeChannel] interface: it says whether a
/// method is its own and how a call of it is carried out.
///
/// The starter has one for [Broadcast], [Presence] and
/// [PostgresChanges]; a bean implementing this interface adds another
/// (asked before the starter's own, so it may also replace one).
///
/// ```dart
/// @Component()
/// class TypingOperation implements RealtimeChannelOperation {
///   @override
///   Object? Function(List<Object?>)? plan(RealtimeChannelMethod method) {
///     if (method.method.annotation<Typing>() == null) {
///       return null;
///     }
///     return (arguments) =>
///         method.session(arguments).send('typing', const {});
///   }
/// }
/// ```
abstract interface class RealtimeChannelOperation {
  /// How a call of [method] is carried out: what it returns for the
  /// arguments of a call (a `Stream`, or a `Future`). `null` when the
  /// method is not of this kind; a method of this kind that is declared
  /// wrongly is reported with [RealtimeChannelMethod.problem].
  Object? Function(List<Object?> arguments)? plan(
    RealtimeChannelMethod method,
  );
}

/// One method of a [RealtimeChannel] interface, as a
/// [RealtimeChannelOperation] sees it when the bean is made.
final class RealtimeChannelMethod {
  RealtimeChannelMethod._(
    this.typeName,
    this.channel,
    this.method,
    this.realtime,
    this.mapper,
    this._templates,
    this._problems,
  ) {
    _name = template(channel.name);
    _presenceKey = switch (channel.presenceKey) {
      final key? => template(key),
      null => null,
    };
  }

  /// The interface's name, for messages.
  final String typeName;

  /// The interface's annotation.
  final RealtimeChannel channel;

  /// The method.
  final ProxyMethod method;

  /// Where the channels come from.
  final SupabaseRealtime realtime;

  /// Reads and writes the JSON of the payloads.
  final ObjectMapper mapper;

  final CallTemplates _templates;
  final List<String> _problems;
  final _used = <String>{};
  late final CallTemplate? _name;
  late final CallTemplate? _presenceKey;

  /// Reports that the method is declared wrongly; the application then
  /// does not start, and the message names every problem.
  void problem(String text) => _problems.add('$typeName.${method.name}: $text');

  /// Reads [text], an annotation's text with `${property}`, `{parameter}`
  /// and `#{SpEL}`, whose values go through [encoder]; `null`, with the
  /// problem reported, when it cannot be read. The parameters it uses are
  /// not the method's payload.
  CallTemplate? template(
    String text, {
    TemplateEncoder encoder = const NameEncoder(),
  }) {
    try {
      final template = _templates.parse(
        text,
        method: method,
        encoder: encoder,
      );
      _used.addAll(template.parameters);
      // A parameter an expression names (#id) is used too.
      for (final parameter in method.parameters) {
        if (RegExp('#${RegExp.escape(parameter.name)}\\b').hasMatch(text)) {
          _used.add(parameter.name);
        }
      }
      return template;
    } on ArgumentError catch (error) {
      problem('${error.message}');
      return null;
    }
  }

  /// [text] with its `${property}` resolved, for an annotation's text
  /// that is the same for every call; `null`, with the problem reported,
  /// when a property is not set.
  String? constant(String text) {
    try {
      return _templates.environment.resolveRequiredPlaceholders(text);
    } on Object catch (error) {
      problem('"$text": $error');
      return null;
    }
  }

  /// The channel of a call with [arguments]: its name (and presence key)
  /// filled from them, with the options of the interface's annotation.
  ///
  /// Throws an [ArgumentError] when a value is refused (nothing, a
  /// control character) or an expression cannot be evaluated.
  RealtimeChannelSession session(List<Object?> arguments) => realtime.channel(
    _name!.expand(method, arguments),
    private: channel.private,
    self: channel.self,
    ack: channel.ack,
    presenceKey: _presenceKey?.expand(method, arguments),
  );

  /// The indexes of the parameters no template of the method uses: the
  /// candidates for its payload.
  List<int> get free => [
    for (final (index, parameter) in method.parameters.indexed)
      if (!_used.contains(parameter.name)) index,
  ];

  /// The index of the parameter that is the payload of the call: the one
  /// marked `@RequestBody()`, else the only one no template uses; `null`
  /// without one. More than one candidate is reported as a problem.
  int? get payload {
    final marked = [
      for (final (index, parameter) in method.parameters.indexed)
        if (parameter.annotations.whereType<RequestBody>().isNotEmpty) index,
    ];
    if (marked.length == 1) {
      return marked.single;
    }
    final candidates = free;
    if (marked.isEmpty && candidates.length <= 1) {
      return candidates.firstOrNull;
    }
    problem(
      'takes one payload at most: mark it @RequestBody() (the parameters '
      "the channel's name uses are not it)",
    );
    return null;
  }

  /// The `T` of a method that returns `Stream<T>`; `null` when it
  /// returns something else.
  TypeInfo<Object?>? get streamOf => switch (method.returnType) {
    final GenericType<Object?> type
        when !method.isFuture &&
            type.isSubtypeOf<Stream<Object?>>() &&
            type.arguments.length == 1 =>
      type.arguments.single,
    _ => null,
  };

  /// Whether the method returns `Future<void>`.
  bool get returnsFutureOfVoid => method.isFuture && method.isVoid;

  /// [value] as JSON, through the `ObjectMapper`; `null` as an empty
  /// object. Throws a `MessageConversionException` when it cannot be
  /// written.
  Object? write(Object? value) {
    if (value == null) {
      return const <String, Object?>{};
    }
    try {
      return mapper.valueToTree(value);
    } on Object catch (error) {
      throw MessageConversionException(
        'cannot write the payload of $typeName.${method.name}: $error',
        cause: error,
      );
    }
  }
}

/// Makes the beans of the [RealtimeChannel] interfaces (the bean
/// `realtimeChannelFactory`); applications do not use it directly.
///
/// When the container creates such a bean, the factory asks each
/// [RealtimeChannelOperation] in turn how every method is carried out,
/// over the channels of [realtime]. An interface that is declared
/// wrongly stops the application at startup, with every problem in one
/// message.
final class RealtimeChannelFactory implements InvocationHandlerFactory {
  /// A factory over the channels of [realtime]; [operations] come before
  /// the starter's own.
  RealtimeChannelFactory({
    required this.realtime,
    required this.templates,
    required this.mapper,
    List<RealtimeChannelOperation> operations = const [],
  }) : operations = List.unmodifiable([...operations, ..._builtIn]);

  /// Where the channels come from.
  final SupabaseRealtime realtime;

  /// Reads the names, presence keys and filters.
  final CallTemplates templates;

  /// Reads and writes the JSON of the payloads.
  final ObjectMapper mapper;

  /// The kinds of methods, asked in this order: the application's
  /// [RealtimeChannelOperation] beans, then the starter's.
  final List<RealtimeChannelOperation> operations;

  static const List<RealtimeChannelOperation> _builtIn = [
    _BroadcastOperation(),
    _PresenceOperation(),
    _PostgresChangesOperation(),
  ];

  @override
  bool supports(InterfaceMetadata<Object> metadata) =>
      metadata.annotation<RealtimeChannel>() != null;

  @override
  InvocationHandler create(InterfaceMetadata<Object> metadata) {
    final annotation = metadata.annotation<RealtimeChannel>()!;
    final problems = <String>[];
    if (annotation.name.trim().isEmpty) {
      problems.add('@RealtimeChannel(""): the channel needs a name');
    }
    final plans = <String, Object? Function(List<Object?>)>{};
    for (final method in metadata.methods) {
      final before = problems.length;
      final described = RealtimeChannelMethod._(
        metadata.typeName,
        annotation,
        method,
        realtime,
        mapper,
        templates,
        problems,
      );
      final plan = operations
          .map((operation) => operation.plan(described))
          .firstWhere((plan) => plan != null, orElse: () => null);
      if (plan != null) {
        plans[method.name] = plan;
      } else if (problems.length == before) {
        described.problem(
          'needs @Broadcast, @Presence or @PostgresChanges',
        );
      }
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Invalid @RealtimeChannel interface ${metadata.typeName}:\n'
        '${problems.map((problem) => '  - $problem').join('\n')}',
      );
    }
    return _RealtimeChannelHandler(plans);
  }
}

final class _RealtimeChannelHandler implements InvocationHandler {
  _RealtimeChannelHandler(this.plans);

  final Map<String, Object? Function(List<Object?>)> plans;

  @override
  Object? invoke(ProxyMethod method, List<Object?> arguments) {
    final plan = plans[method.name]!;
    if (!method.isFuture) {
      return plan(arguments);
    }
    // A refused name fails the returned future, like any other failure
    // of the call.
    return Future<Object?>.sync(() => plan(arguments));
  }
}

final class _BroadcastOperation implements RealtimeChannelOperation {
  const _BroadcastOperation();

  @override
  Object? Function(List<Object?>)? plan(RealtimeChannelMethod method) {
    final broadcast = method.method.annotation<Broadcast>();
    if (broadcast == null) {
      return null;
    }
    final event = method.constant(broadcast.event);
    final element = method.streamOf;
    if (element != null) {
      if (method.free.isNotEmpty) {
        method.problem(
          'a @Broadcast method that returns a Stream takes only the '
          "parameters the channel's name uses",
        );
      }
      final payloads = element.accept(
        _Payloads(method, 'a "${broadcast.event}" broadcast'),
      );
      return (arguments) =>
          payloads.stream(method.session(arguments).events(event!));
    }
    if (!method.returnsFutureOfVoid) {
      method.problem(
        'a @Broadcast method returns Stream<T> (the broadcasts) or '
        'Future<void> (sends one)',
      );
      return (_) => null;
    }
    final payload = method.payload;
    return (arguments) => method
        .session(arguments)
        .send(
          event!,
          method.write(payload == null ? null : arguments[payload]),
        );
  }
}

final class _PresenceOperation implements RealtimeChannelOperation {
  const _PresenceOperation();

  @override
  Object? Function(List<Object?>)? plan(RealtimeChannelMethod method) {
    if (method.method.annotation<Presence>() == null) {
      return null;
    }
    final element = method.streamOf;
    if (element != null) {
      final lists = element.accept(_PresenceLists(method));
      if (lists == null || method.free.isNotEmpty) {
        method.problem(
          'a @Presence method that returns a Stream returns '
          'Stream<List<T>> and takes only the parameters the '
          "channel's name uses",
        );
        return (_) => null;
      }
      return (arguments) => lists(method.session(arguments).presence());
    }
    if (!method.returnsFutureOfVoid) {
      method.problem(
        'a @Presence method returns Stream<List<T>> (who is present) or '
        'Future<void> (tracks its payload, or ends the presence without '
        'one)',
      );
      return (_) => null;
    }
    final payload = method.payload;
    if (payload == null) {
      return (arguments) => method.session(arguments).untrack();
    }
    return (arguments) {
      final state = method.write(arguments[payload]);
      if (state is! Map) {
        throw MessageConversionException(
          'the presence of ${method.typeName}.${method.method.name} must '
          'be a JSON object, not ${state.runtimeType}',
        );
      }
      return method.session(arguments).track({
        for (final MapEntry(:key, :value) in state.entries) '$key': value,
      });
    };
  }
}

final class _PostgresChangesOperation implements RealtimeChannelOperation {
  const _PostgresChangesOperation();

  @override
  Object? Function(List<Object?>)? plan(RealtimeChannelMethod method) {
    final changes = method.method.annotation<PostgresChanges>();
    if (changes == null) {
      return null;
    }
    final schema = method.constant(changes.schema);
    final table = method.constant(changes.table);
    final filter = switch (changes.filter) {
      final filter? => method.template(
        filter,
        encoder: const PostgresFilterEncoder(),
      ),
      null => null,
    };
    if (table != null && table.trim().isEmpty) {
      method.problem('@PostgresChanges needs a table');
    }
    if (method.streamOf?.type != RealtimeRowChange || method.free.isNotEmpty) {
      method.problem(
        'a @PostgresChanges method returns Stream<RealtimeRowChange> and '
        "takes only the parameters the channel's name and the filter use",
      );
    }
    return (arguments) => method
        .session(arguments)
        .postgresChanges(
          schema: schema!,
          table: table!,
          filter: filter?.expand(method.method, arguments),
          kind: changes.kind,
        );
  }
}

/// Reads JSON as `T`, for the streams of a method.
final class _Decoder<T> {
  _Decoder(this._method, this._type, this._what);

  final RealtimeChannelMethod _method;
  final TypeInfo<T> _type;
  final String _what;

  T read(Object? json) {
    if (json is T) {
      return json;
    }
    try {
      return _method.mapper.treeToValue<T>(json, _type);
    } on Object catch (error) {
      throw MessageConversionException(
        'cannot read $_what of ${_method.typeName}.${_method.method.name} '
        'as $_type: $error',
        message: _text(json),
        cause: error,
      );
    }
  }

  /// [source] with each payload read as `T`; one that cannot be read is
  /// an error event.
  Stream<T> stream(Stream<Object?> source) => source.transform(
    StreamTransformer<Object?, T>.fromHandlers(
      handleData: (json, sink) {
        final T value;
        try {
          value = read(json);
        } on MessageConversionException catch (error, stackTrace) {
          sink.addError(error, stackTrace);
          return;
        }
        sink.add(value);
      },
    ),
  );

  /// [source] with the state of each presence read as `T` (a presence
  /// itself where `T` takes it).
  Stream<List<T>> lists(Stream<List<RealtimePresence>> source) =>
      source.transform(
        StreamTransformer<List<RealtimePresence>, List<T>>.fromHandlers(
          handleData: (presences, sink) {
            final List<T> values;
            try {
              values = [
                for (final presence in presences) _presence(presence),
              ];
            } on MessageConversionException catch (error, stackTrace) {
              sink.addError(error, stackTrace);
              return;
            }
            sink.add(values);
          },
        ),
      );

  // A presence itself where `T` takes it, else its state read as `T`.
  T _presence(RealtimePresence presence) =>
      _self(presence) ?? read(presence.state);

  T? _self(Object? presence) => presence is T ? presence : null;

  static String? _text(Object? json) {
    try {
      return jsonEncode(json);
    } on Object {
      return null;
    }
  }
}

/// The decoder of the `T` of a `Stream<T>`.
final class _Payloads implements TypeInfoVisitor<_Decoder<Object?>> {
  _Payloads(this._method, this._what);

  final RealtimeChannelMethod _method;
  final String _what;

  @override
  _Decoder<Object?> visitClass<T>(ClassType<T> type) =>
      _Decoder<T>(_method, type, _what);

  @override
  _Decoder<Object?> visitList<E>(ListType<E> type) =>
      _Decoder<List<E>>(_method, type, _what);

  @override
  _Decoder<Object?> visitSet<E>(SetType<E> type) =>
      _Decoder<Set<E>>(_method, type, _what);

  @override
  _Decoder<Object?> visitMap<K, V>(MapType<K, V> type) =>
      _Decoder<Map<K, V>>(_method, type, _what);

  @override
  _Decoder<Object?> visitEnum<E extends Enum>(EnumType<E> type) =>
      _Decoder<E>(_method, type, _what);

  @override
  _Decoder<Object?> visitGeneric<T>(GenericType<T> type) =>
      _Decoder<T>(_method, type, _what);

  @override
  _Decoder<Object?> visitDynamic(DynamicType type) =>
      _Decoder<Object?>(_method, type, _what);
}

typedef _Lists = Stream<Object?> Function(Stream<List<RealtimePresence>>);

/// The stream of a `Stream<List<T>>` presence method; `null` for a
/// stream of something that is no list.
final class _PresenceLists implements TypeInfoVisitor<_Lists?> {
  _PresenceLists(this._method);

  final RealtimeChannelMethod _method;

  @override
  _Lists? visitList<E>(ListType<E> type) =>
      type.element.accept(_Payloads(_method, 'a presence')).lists;

  @override
  _Lists? visitClass<T>(ClassType<T> type) => null;

  @override
  _Lists? visitSet<E>(SetType<E> type) => null;

  @override
  _Lists? visitMap<K, V>(MapType<K, V> type) => null;

  @override
  _Lists? visitEnum<E extends Enum>(EnumType<E> type) => null;

  @override
  _Lists? visitGeneric<T>(GenericType<T> type) => null;

  @override
  _Lists? visitDynamic(DynamicType type) => null;
}
