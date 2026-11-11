import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/src/http/supabase_http.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';
import 'package:spring_boot_starter_supabase/src/realtime/realtime_presence_state.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_security_core/spring_security_core.dart';

const _log = SpringLog('spring.supabase.realtime');

/// Supabase Realtime (the bean `supabaseRealtime`): changes of the
/// database, messages between clients (Broadcast) and who is online
/// (Presence), as streams over one WebSocket connection to the project.
///
/// Ask it for a [channel] by name and use that; the connection opens
/// with the first channel that is used and closes with the last one that
/// is left, and everything stops when the application does. Applications
/// usually declare a `@RealtimeChannel` interface instead.
///
/// ```dart
/// @Service()
/// class Board {
///   Board(this.realtime);
///   final SupabaseRealtime realtime;
///
///   // The rows of one list, as they change.
///   Stream<RealtimeRowChange> changes(int list) => realtime.postgresChanges(
///     table: 'todos',
///     filter: 'list_id=eq.$list',
///   );
///
///   // Cursors of the others, and who is here.
///   late final room = realtime.channel('board', presenceKey: 'ann');
///   Stream<Map<String, Object?>> cursors() => room.broadcast('cursor');
///   Future<void> move(int x, int y) => room.send('cursor', {'x': x, 'y': y});
/// }
/// ```
///
/// Every channel is joined with the access token of
/// `SupabaseCredentials`, asked again at each join. When the application
/// has a `LoginSession`, each change of the login reaches the channels
/// in use: a new token of the same user is sent to the joined channel,
/// without joining again (a token that was refreshed is sent at the next
/// heartbeat); for another user, or nobody after a logout, the channel
/// is joined again with the new token (the anon key for nobody), and
/// what the server still sent for the user before is dropped. The
/// streams go on; as with any new join, a message of that moment is
/// missed.
///
/// A channel acts as the application itself: its login, or the anon key.
/// It outlives a server's request, so it never takes the token of the
/// request it was asked in; a channel asked inside
/// `SupabaseCredentials.asServiceRole` is joined as the service role.
///
/// The connection is the WebSocket client [clientName], a Phoenix socket
/// of the WebSocket starter, so
/// `spring.websocket.client.config.supabase-realtime.*` tunes it
/// (`reconnect.*`, `connect-timeout`, `max-text-message-size`,
/// `phoenix.*`). What the application does not set there comes from
/// `spring.supabase.realtime.heartbeat-interval` and `timeout`,
/// `spring.supabase.connect-timeout`, the wire format [defaultVsn] and
/// text messages of up to [defaultMaxMessageSize].
///
/// Supabase (JavaScript): `supabase.realtime`, a `RealtimeClient`.
///
/// Differs from Supabase: no `connect()`, `subscribe()` or
/// `removeChannel()`; a channel is joined while it is used. No REST
/// fallback for a broadcast: `send` joins the channel.
final class SupabaseRealtime implements DisposableBean {
  /// Realtime of the project of [http], with the tokens of [credentials]
  /// and the transport, handshake interceptors and wire formats of
  /// [sockets]. `session` gives the application's login when it has one
  /// (looked up when the connection is first needed).
  SupabaseRealtime({
    required this.http,
    required this.credentials,
    required this.sockets,
    this._session,
    DataSize? maxMessageSize,
  }) : maxMessageSize =
           maxMessageSize ?? const DataSize.ofBytes(defaultMaxMessageSize);

  /// The name of the WebSocket client: its settings are
  /// `spring.websocket.client.config.supabase-realtime.*`, and a
  /// `WebSocketHandshakeInterceptor` sees it as
  /// `WebSocketHandshake.clientName`.
  static const clientName = 'supabase-realtime';

  /// The wire format of the connection unless
  /// `spring.websocket.client.config.supabase-realtime.phoenix.vsn` says
  /// otherwise: `1.0.0`, where every message is JSON text. With `2.0.0`
  /// Realtime sends broadcasts as binary frames, which the Phoenix
  /// client of the WebSocket starter does not read.
  static const defaultVsn = '1.0.0';

  /// The largest text message the connection reads, in bytes, unless
  /// `spring.websocket.client.config.supabase-realtime.max-text-message-size`
  /// says otherwise: 4 MB, above the largest message Realtime sends (a
  /// broadcast of 3,000 KB on the paid plans, a database change of
  /// 1,024 KB).
  static const int defaultMaxMessageSize = 4 * 1024 * 1024;

  /// The project: its address and the `spring.supabase.*` properties.
  final SupabaseHttp http;

  /// Gives the `apikey` of each connection and the access token of each
  /// join.
  final SupabaseCredentials credentials;

  /// The WebSocket starter's sockets: their transport, handshake
  /// interceptors, wire formats and `spring.websocket.client.*`.
  final PhoenixSocketFactory sockets;

  /// The largest text message the connection reads when the application
  /// sets no limit for the client [clientName].
  final DataSize maxMessageSize;

  final LoginSession? Function()? _session;
  // The channels that are used now, by topic.
  final _channels = <String, _Channel>{};
  PhoenixSocket? _socket;
  StreamSubscription<Authentication?>? _logins;
  Timer? _refresh;
  var _stopped = false;

  /// The address of the connection, before the `vsn` and the `apikey`
  /// are added to its query: `wss://<project>/realtime/v1/websocket`.
  Uri get url {
    final base = http.realtimeUrl;
    return base.replace(path: '${base.path}/websocket');
  }

  /// Whether the connection is open now.
  bool get isConnected => _socket?.isConnected ?? false;

  /// The channels that are used now (joined, or being joined), in the
  /// order of their first use.
  List<RealtimeChannelSession> get channels => List.unmodifiable([
    for (final channel in _channels.values) channel.handle,
  ]);

  /// The channel [name] (the topic `realtime:<name>`), joined when it is
  /// first used: a stream of it is listened to, or something is sent or
  /// tracked.
  ///
  /// - [private]: a channel whose members are authorized by the policies
  ///   of row-level security on `realtime.messages`.
  /// - [self]: this client receives its own broadcasts too.
  /// - [ack]: [RealtimeChannelSession.send] waits until the server took
  ///   the message.
  /// - [presenceKey]: the key this client is present under (a user's id,
  ///   so two devices of one user are one key); the server makes one up
  ///   without it.
  ///
  /// Every call with the same name gives the same channel of the
  /// connection: the options must be the same while it is used, or its
  /// use fails with a [StateError]. Asked inside
  /// `SupabaseCredentials.asServiceRole`, the channel is joined as the
  /// service role, whenever it is used.
  ///
  /// ```dart
  /// final room = realtime.channel('room:42', self: true);
  /// room.broadcast('message').listen(show);
  /// await room.send('message', {'text': 'hi'});
  /// ```
  RealtimeChannelSession channel(
    String name, {
    bool private = false,
    bool self = false,
    bool ack = false,
    String? presenceKey,
  }) => RealtimeChannelSession._(
    this,
    name,
    private: private,
    self: self,
    ack: ack,
    presenceKey: presenceKey,
    serviceRole: credentials.caller.role == SupabaseRole.service,
  );

  /// The changes of the rows of [schema].[table], from the moment of
  /// listening, on a channel of their own that is left when the last
  /// listener cancels.
  ///
  /// [filter] narrows them on the server, as
  /// [RealtimeChannelSession.postgresChanges] describes; [kind] gives
  /// only inserts, updates or deletes. The table must be in the
  /// publication `supabase_realtime`, and the user must be allowed to
  /// read the rows (row-level security).
  ///
  /// ```dart
  /// realtime
  ///     .postgresChanges(table: 'todos', filter: 'list_id=eq.7')
  ///     .listen(apply);
  /// ```
  Stream<RealtimeRowChange> postgresChanges({
    required String table,
    String schema = 'public',
    String? filter,
    RealtimeChangeKind? kind,
  }) => channel(
    'db-changes:$schema:$table:${kind?.wire ?? '*'}'
    '${filter == null ? '' : ':$filter'}',
  ).postgresChanges(schema: schema, table: table, filter: filter, kind: kind);

  /// Brings every joined channel in line with the current access token:
  /// another token of the same user is sent to it, without joining
  /// again; with the token of another user, or of nobody, the channel is
  /// joined again.
  ///
  /// Called by itself when the application's `LoginSession` changes and
  /// at every heartbeat (so a refreshed token reaches the channels before
  /// the old one expires); call it after changing what
  /// `SupabaseCredentials.accessToken` gives in another way.
  ///
  /// ```dart
  /// await realtime.refreshAuth();
  /// ```
  ///
  /// Supabase (JavaScript): `realtime.setAuth()`.
  Future<void> refreshAuth() => Future.wait([
    for (final channel in [..._channels.values]) channel.refreshToken(),
  ]);

  /// Stops Realtime when the application stops: every stream is done and
  /// the connection closes. Later use fails with a [StateError]. With an
  /// open connection it returns a future that completes once it is
  /// closed, which `closeAsync()` awaits.
  @override
  FutureOr<void> destroy() {
    if (_stopped) {
      return null;
    }
    _stopped = true;
    _idle();
    for (final channel in [..._channels.values]) {
      channel.stop();
    }
    final socket = _socket;
    if (socket == null) {
      return null;
    }
    if (socket.isConnected) {
      return socket.dispose();
    }
    unawaited(socket.dispose());
  }

  // The state of the channel [handle] names, made on its first use.
  _Channel _channelOf(RealtimeChannelSession handle) {
    if (_stopped) {
      throw StateError(
        'Supabase Realtime is closed: the application stopped',
      );
    }
    final existing = _channels[handle.topic];
    if (existing != null) {
      if (!existing.handle._sameAs(handle)) {
        throw StateError(
          'The Realtime channel ${handle.name} is in use as '
          '${existing.handle._options}, and cannot be used as '
          '${handle._options} at the same time: a connection joins a '
          'topic once',
        );
      }
      return existing;
    }
    final socket = _socket ??= _open();
    _busy();
    return _channels[handle.topic] = _Channel(this, handle, socket);
  }

  void _forget(_Channel channel) {
    if (identical(_channels[channel.handle.topic], channel)) {
      _channels.remove(channel.handle.topic);
    }
    if (_channels.isEmpty) {
      _idle();
    }
  }

  // The first channel: tokens are followed from now on.
  void _busy() {
    _logins ??= _login()?.authenticationChanges.listen(
      (_) => unawaited(refreshAuth()),
      onError: (Object _) {},
    );
    final interval = _socket?.config.phoenix.heartbeatInterval ?? Duration.zero;
    if (_refresh == null && interval > Duration.zero) {
      _refresh = Timer.periodic(interval, (_) => unawaited(refreshAuth()));
    }
  }

  LoginSession? _login() {
    try {
      return _session?.call();
    } on Object catch (error) {
      // No login to follow; never the error's text, which is not ours.
      _log.debug('no LoginSession to follow: ${error.runtimeType}');
      return null;
    }
  }

  // No channel is left.
  void _idle() {
    unawaited(_logins?.cancel());
    _logins = null;
    _refresh?.cancel();
    _refresh = null;
  }

  // The settings of one client as the application wrote them, without
  // any default.
  WebSocketClientSettings? _settings(String name) {
    final configs = sockets.properties.config;
    return configs[name] ??
        configs.entries
            .where((entry) => entry.key.toLowerCase() == name)
            .map((entry) => entry.value)
            .firstOrNull;
  }

  PhoenixSocket _open() {
    final base = sockets.configOf(clientName);
    final own = _settings(clientName);
    final shared = _settings('default');
    final realtime = http.properties.realtime;
    final vsn = own?.phoenix.vsn ?? defaultVsn;
    final serializer = sockets.serializerOf(vsn);
    if (serializer == null) {
      throw StateError(
        'spring.websocket.client.config.$clientName.phoenix.vsn: no '
        'PhoenixSerializer for vsn "$vsn"',
      );
    }
    final config = WebSocketClientConfig(
      connectTimeout:
          own?.connectTimeout ??
          shared?.connectTimeout ??
          http.properties.connectTimeout,
      reconnect: base.reconnect,
      defaultRequestHeaders: base.defaultRequestHeaders,
      phoenix: PhoenixSocketConfig(
        heartbeatInterval:
            own?.phoenix.heartbeatInterval ?? realtime.heartbeatInterval,
        pushTimeout: own?.phoenix.pushTimeout ?? realtime.timeout,
        vsn: vsn,
      )..validate('spring.supabase.realtime'),
      // Realtime's messages are larger than the 8 KB of other clients.
      maxTextMessageSize: own?.maxTextMessageSize ?? maxMessageSize,
      maxBinaryMessageSize: base.maxBinaryMessageSize,
    );
    // The address is the project's, whatever config.<name>.url says: a
    // key or a token is only ever sent to spring.supabase.url.
    return PhoenixSocket(
      name: clientName,
      url: url,
      transport: sockets.transport,
      config: config,
      serializer: serializer,
      parameters: () async => {
        'apikey': await _outside(() => credentials.apiKey),
      },
      interceptors: sockets.interceptors,
    );
  }

  // Runs [body] outside the zone of whoever uses a channel now: a
  // channel outlives a request and `asServiceRole`, so what it sends is
  // never theirs by accident. The result comes back through a completer
  // of the caller's zone, as an error does not cross error zones.
  Future<T> _outside<T>(FutureOr<T> Function() body) {
    final result = Completer<T>();
    Zone.root.run(() {
      unawaited(
        Future<T>.sync(
          body,
        ).then(result.complete, onError: result.completeError),
      );
    });
    return result.future;
  }

  @override
  String toString() => 'SupabaseRealtime(${_channels.keys.join(', ')})';
}

/// One channel of Supabase Realtime: the changes of the database it
/// subscribes to, the broadcasts of its clients, and who is present.
///
/// [SupabaseRealtime.channel] gives it. Nothing is joined until it is
/// used: listening to [postgresChanges], [broadcast], [events] or
/// [presence], or calling [send] or [track], joins the topic, with what
/// is used at that moment as the configuration of the join. It is left
/// when its last stream is cancelled and nothing is tracked, or with
/// [leave]; using it again joins it again.
///
/// The server takes the configuration of a channel at its join only. So
/// when a stream of database changes is added or cancelled, or presence
/// is first used, while the channel is joined, it is joined again with
/// the new configuration: the other streams go on, but a broadcast sent
/// in that moment is missed. Listen to what a channel needs at once, or
/// give database changes a channel of their own
/// ([SupabaseRealtime.postgresChanges] does).
///
/// After a lost connection the channel is joined again by itself, with a
/// fresh access token; what was tracked is tracked again, and the streams
/// go on. When the server ends the channel (a limit that was passed, a
/// token it refused), the streams get a [RealtimeException] and are done.
///
/// ```dart
/// final room = realtime.channel('room:42', presenceKey: userId);
/// room.broadcast('cursor').listen(moveCursor);
/// room.presence().listen(showMembers);
/// await room.track({'name': 'Ann'});
/// await room.send('cursor', {'x': 3, 'y': 4});
/// ```
///
/// Supabase (JavaScript):
/// ```js
/// const room = supabase.channel('room:42', {config: {presence: {key}}})
/// room.on('broadcast', {event: 'cursor'}, moveCursor)
///     .on('presence', {event: 'sync'}, showMembers)
///     .subscribe()
/// room.track({name: 'Ann'})
/// room.send({type: 'broadcast', event: 'cursor', payload: {x: 3, y: 4}})
/// ```
///
/// Differs from Supabase: it is the `RealtimeChannel` of `realtime-js`,
/// named a session here because `@RealtimeChannel` is the annotation;
/// streams instead of callbacks, and no `subscribe()`.
final class RealtimeChannelSession {
  RealtimeChannelSession._(
    this._realtime,
    this.name, {
    required this.private,
    required this.self,
    required this.ack,
    required this.presenceKey,
    required this._serviceRole,
  });

  final SupabaseRealtime _realtime;

  /// The name of the channel, such as `room:42`.
  final String name;

  /// Whether the channel is private: its members are authorized by
  /// policies on `realtime.messages`.
  final bool private;

  /// Whether this client receives its own broadcasts.
  final bool self;

  /// Whether [send] waits until the server took the message.
  final bool ack;

  /// The key this client is present under; `null` lets the server make
  /// one up.
  final String? presenceKey;

  // Asked inside asServiceRole: joined as the service role.
  final bool _serviceRole;

  /// The topic of the channel in the protocol: `realtime:<name>`.
  String get topic => 'realtime:$name';

  /// Whether the server has accepted the join of the channel and it is
  /// in force now.
  bool get isJoined => _used?.session?.state == PhoenixChannelState.joined;

  // The channel's state while it is used (as this one, not under other
  // options).
  _Channel? get _used => switch (_realtime._channels[topic]) {
    final channel? when channel.handle._sameAs(this) => channel,
    _ => null,
  };

  String get _options =>
      '(private: $private, self: $self, ack: $ack, presenceKey: '
      '$presenceKey${_serviceRole ? ', as the service role' : ''})';

  bool _sameAs(RealtimeChannelSession other) =>
      other.private == private &&
      other.self == self &&
      other.ack == ack &&
      other.presenceKey == presenceKey &&
      other._serviceRole == _serviceRole;

  /// The changes of the rows of [schema].[table], from the moment of
  /// listening (Postgres Changes). Listening subscribes on the server;
  /// when the last listener of the same subscription cancels, the
  /// server's subscription ends.
  ///
  /// [filter] narrows the rows on the server: `column=operator.value`
  /// with `eq`, `neq`, `lt`, `lte`, `gt`, `gte` or `in`
  /// (`id=in.(1,2,3)`); newer servers also take `like`, `ilike`, `is`,
  /// `match`, `imatch` and `isdistinct`, a `not.` before the operator,
  /// and several conditions joined by commas. [kind] gives only inserts,
  /// updates or deletes.
  ///
  /// A filter is tested against the row after the change: with one, the
  /// server sends no delete (it carries only the primary key) and no
  /// update that takes a row out of the filter. To follow the rows of a
  /// condition, subscribe without a filter and test the rows, as the
  /// repositories' `watchBy…` and `changesBy…` do.
  ///
  /// A subscription the server cannot make (a wrong filter, a table that
  /// is not published) is an error event, a [RealtimeException]; the
  /// stream stays open. A join the server refuses is an error event too
  /// (a `PhoenixJoinException`), and is tried again.
  ///
  /// ```dart
  /// room
  ///     .postgresChanges(table: 'messages', filter: 'room_id=eq.42')
  ///     .listen((change) => show(change.record));
  /// ```
  ///
  /// Supabase (JavaScript):
  /// `channel.on('postgres_changes', {event, schema, table, filter}, fn)`.
  Stream<RealtimeRowChange> postgresChanges({
    required String table,
    String schema = 'public',
    String? filter,
    RealtimeChangeKind? kind,
  }) {
    final subscription = _Subscription(
      event: kind?.wire ?? '*',
      schema: schema,
      table: table,
      filter: filter,
    );
    return _listen<RealtimeRowChange>(
      (channel, listener) => channel.postgres.add(subscription, listener),
      (channel, listener) => channel.postgres.remove(subscription, listener),
    );
  }

  /// The payloads of the broadcasts named [event], whatever their JSON
  /// (an object, a list, a text); see [broadcast] for objects.
  ///
  /// ```dart
  /// room.events('tick').listen((payload) => count = payload! as int);
  /// ```
  Stream<Object?> events(String event) => _listen<Object?>(
    (channel, listener) => channel.broadcasts.add(event, listener),
    (channel, listener) => channel.broadcasts.remove(event, listener),
  );

  /// The payloads of the broadcasts named [event] that other clients of
  /// the channel [send] (this client's own too with `self`). A payload
  /// that is not a JSON object is an error event (a [FormatException]);
  /// [events] gives those.
  ///
  /// ```dart
  /// room.broadcast('cursor').listen((cursor) => move(cursor['x']));
  /// ```
  ///
  /// Supabase (JavaScript): `channel.on('broadcast', {event}, fn)`.
  Stream<Map<String, Object?>> broadcast(String event) => events(event)
      .transform(
        StreamTransformer.fromHandlers(
          handleData: (payload, sink) {
            if (payload is Map) {
              sink.add({
                for (final MapEntry(:key, :value) in payload.entries)
                  '$key': value,
              });
            } else {
              sink.addError(
                FormatException(
                  'the broadcast "$event" of $name is not a JSON object '
                  '(${payload.runtimeType}): listen with events()',
                ),
              );
            }
          },
        ),
      );

  /// Broadcasts [event] with [payload] (JSON: usually a map; `null`
  /// sends `{}`) to the other clients of the channel, joining it first
  /// when needed.
  ///
  /// It completes when the message was handed to the connection; with
  /// `ack`, when the server took it, and it then fails with a
  /// `PhoenixPushException` when the server refuses it (too large, too
  /// many) and with a `TimeoutException` without an answer in time. A
  /// channel that cannot be joined fails it with a
  /// `PhoenixJoinException`.
  ///
  /// A channel that is only sent to stays joined until [leave] or the
  /// end of the application (one that could not be joined for the send
  /// is given up at once).
  ///
  /// ```dart
  /// await room.send('cursor', {'x': 3, 'y': 4});
  /// ```
  ///
  /// Supabase (JavaScript):
  /// `channel.send({type: 'broadcast', event, payload})`.
  Future<void> send(String event, [Object? payload]) async {
    final message = {
      'type': 'broadcast',
      'event': event,
      'payload': payload ?? const <String, Object?>{},
    };
    await _realtime._channelOf(this).push((session) async {
      if (ack) {
        await session.push('broadcast', message);
      } else {
        await session.send('broadcast', message);
      }
    });
  }

  /// Who is present on the channel: the list now, then again after every
  /// change. Listening joins the channel with presence on; the first
  /// list comes when the server has sent it.
  ///
  /// ```dart
  /// room.presence().listen((present) => count.value = present.length);
  /// ```
  ///
  /// Supabase (JavaScript): `channel.on('presence', {event: 'sync'}, fn)`
  /// with `channel.presenceState()`.
  Stream<List<RealtimePresence>> presence() => _listen<List<RealtimePresence>>(
    (channel, listener) => channel.presences.add(listener),
    (channel, listener) => channel.presences.remove(listener),
  );

  /// Makes this client present on the channel with [state] (JSON), under
  /// its `presenceKey`, joining the channel first when needed; tracking
  /// again replaces the state. It completes when the server took it, and
  /// fails with a `PhoenixPushException` when it refuses; after a
  /// failure nothing is tracked.
  ///
  /// The client stays present until [untrack], [leave] or the end of its
  /// connection, and is tracked again by itself after the channel was
  /// joined again.
  ///
  /// ```dart
  /// await room.track({'name': 'Ann', 'typing': false});
  /// ```
  ///
  /// Supabase (JavaScript): `channel.track(state)`.
  Future<void> track(Map<String, Object?> state) async {
    final channel = _realtime._channelOf(this);
    final tracked = Map<String, Object?>.unmodifiable(state);
    channel.presences.tracked = tracked;
    try {
      await channel.push(channel.presences.track);
    } on Object {
      // Not present: nothing is tracked later behind the caller's back.
      if (identical(channel.presences.tracked, tracked)) {
        channel.presences.tracked = null;
        channel.changed();
      }
      rethrow;
    }
  }

  /// Ends the presence of this client on the channel; harmless when
  /// nothing is tracked. The channel is left when nothing listens to it
  /// either.
  ///
  /// ```dart
  /// await room.untrack();
  /// ```
  ///
  /// Supabase (JavaScript): `channel.untrack()`.
  Future<void> untrack() async {
    await _used?.untrack();
  }

  /// Leaves the channel now: its streams are done and nothing is tracked
  /// any more. Leaving a channel that is not used is harmless; using it
  /// afterwards joins it again.
  ///
  /// ```dart
  /// await room.leave();
  /// ```
  ///
  /// Supabase (JavaScript): `supabase.removeChannel(channel)`.
  Future<void> leave() async {
    await _used?.leave();
  }

  // A stream whose listener is added to the channel while it listens.
  Stream<T> _listen<T>(
    void Function(_Channel channel, StreamController<T> listener) add,
    void Function(_Channel channel, StreamController<T> listener) remove,
  ) {
    late final StreamController<T> controller;
    _Channel? used;
    controller = StreamController<T>(
      onListen: () {
        final _Channel channel;
        try {
          channel = _realtime._channelOf(this);
        } on StateError catch (error, stackTrace) {
          controller.addError(error, stackTrace);
          unawaited(controller.close());
          return;
        }
        used = channel;
        add(channel, controller);
        channel.changed();
      },
      onCancel: () {
        final channel = used;
        used = null;
        if (channel != null) {
          remove(channel, controller);
          channel.changed();
        }
      },
    );
    return controller.stream;
  }

  @override
  String toString() => 'RealtimeChannelSession($name)';
}

/// One subscription to database changes, as the join names it.
final class _Subscription {
  _Subscription({
    required this.event,
    required this.schema,
    required this.table,
    required this.filter,
  });

  final String event;
  final String schema;
  final String table;
  final String? filter;

  // Realtime keeps one subscription for equal ones: so does the channel.
  String get key => jsonEncode([event, schema, table, filter]);

  Map<String, Object?> get json => {
    'event': event,
    'schema': schema,
    'table': table,
    'filter': ?filter,
  };

  // Whether [server], an entry of the join's reply, is this one.
  bool matches(Object? server) =>
      server is Map &&
      server['event'] == event &&
      server['schema'] == schema &&
      server['table'] == table &&
      server['filter'] == filter;

  bool takes(RealtimeRowChange change) =>
      event == '*' || event == change.kind.wire;
}

/// One part of a channel (database changes, broadcasts, presence, the
/// server's own notices): its share of the join's configuration, and
/// the messages it takes.
abstract interface class _Feature {
  /// Whether someone uses it now: a channel nothing uses is left.
  bool get inUse;

  /// Adds its part to the `config` of a join.
  void configure(Map<String, Object?> config);

  /// A join is being made with the configuration it just gave.
  void opened();

  /// The server accepted a join, the first or one after a reconnection,
  /// with [response].
  void joined(PhoenixChannelSession session, Object? response);

  /// A message of the server; whether it was this feature's.
  bool receive(PhoenixChannelSession session, PhoenixMessage message);

  /// A problem of the whole channel, for everyone who listens.
  void fail(Object error, [StackTrace? stackTrace]);

  /// The channel ended or was left: the streams are done, and nothing
  /// of the join is kept.
  void end();
}

// Whose token it is: the user of a token of Auth (its `sub`); null for a
// key, which is nobody's (the anon key) or the service role's.
String? _userOf(String? token) =>
    switch (token == null ? null : supabaseTokenClaims(token)?['sub']) {
      final String subject when subject.isNotEmpty => subject,
      _ => null,
    };

/// One join of a channel: the Phoenix session with the configuration
/// it was made for.
final class _Join {
  _Join(this.session, this.config, {this.replied = true});

  final PhoenixChannelSession session;
  // The configuration as JSON text, to tell when another one is needed.
  final String config;
  final subscriptions = <StreamSubscription<Object?>>[];
  // Messages that came before the reply of the join was read.
  final held = <PhoenixMessage>[];
  bool ready = false;
  // Whether the server has answered this join. False at first for a join
  // that takes the place of another user's: what comes before the answer
  // is still of that one, and is dropped.
  bool replied;
  // The token the server has for this join.
  String? token;

  void dispose() {
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    session.leave().ignore();
  }
}

/// The state of a channel while it is used: who listens, and its join.
final class _Channel {
  _Channel(this.realtime, this.handle, this.socket);

  final SupabaseRealtime realtime;
  final RealtimeChannelSession handle;
  final PhoenixSocket socket;

  late final postgres = _PostgresChanges(this);
  late final broadcasts = _Broadcasts(this);
  late final presences = _Presences(this);
  late final List<_Feature> features = [
    postgres,
    broadcasts,
    presences,
    _Notices(this),
  ];

  _Join? _join;
  var _scheduled = false;
  // Pushes in progress: the channel is not left under them.
  var _pushes = 0;
  var _ended = false;

  PhoenixChannelSession? get session => _join?.session;

  // Something about who listens changed: the join is brought in line
  // once, after everything that changes now.
  void changed() {
    if (_scheduled || _ended) {
      return;
    }
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_ended) {
        return;
      }
      if (features.any((feature) => feature.inUse)) {
        try {
          _open();
        } on Object catch (error, stackTrace) {
          fail(error, stackTrace);
        }
      } else if (_pushes == 0) {
        _close();
      }
    });
  }

  // The join with the configuration wanted now: the one in force, or a
  // new one in its place; always a new one with [asAnother], when the
  // token is another user's.
  _Join _open({bool asAnother = false}) {
    final config = <String, Object?>{};
    for (final feature in features) {
      feature.configure(config);
    }
    config['private'] = handle.private;
    final encoded = jsonEncode(config);
    final current = _join;
    if (current != null && current.config == encoded && !asAnother) {
      return current;
    }
    late final _Join join;
    final session = socket.channel(
      handle.topic,
      payload: () async {
        final token = await _token();
        join.token = token;
        return {'config': config, 'access_token': token};
      },
    );
    join = _join = _Join(session, encoded, replied: !asAnother);
    for (final feature in features) {
      feature.opened();
    }
    join.subscriptions
      ..add(session.states.listen((state) => _state(join, state)))
      ..add(
        session.messages.listen(
          (message) => _message(join, message),
          onError: (Object error, StackTrace stackTrace) {
            if (identical(join, _join)) {
              fail(error, stackTrace);
            }
          },
          onDone: () => _done(join),
        ),
      );
    void start() => unawaited(
      session.join().then(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          // A join that ended has nothing more to say.
          final ended = session.state == PhoenixChannelState.closed;
          if (identical(join, _join) && !ended) {
            fail(error, stackTrace);
          }
        },
      ),
    );
    // On the wire the old join is left before the new one is asked: a
    // server takes a leave for the topic's channel, whichever join it
    // names. Without anything on the wire the new one comes first, so
    // the connection is not closed in between.
    if (current != null &&
        socket.isConnected &&
        current.session.joinRef != null) {
      current.dispose();
      start();
    } else {
      start();
      current?.dispose();
    }
    return join;
  }

  // The access token of a join, as the application itself or as the
  // service role; never as the user of the request that is running.
  Future<String> _token() => realtime._outside(
    () => handle._serviceRole
        ? realtime.credentials.asServiceRole(realtime.credentials.accessToken)
        : realtime.credentials.accessToken(),
  );

  void _state(_Join join, PhoenixChannelState state) {
    if (!identical(join, _join) || state != PhoenixChannelState.joined) {
      return;
    }
    // The reply of this join: until it is read, messages wait.
    join
      ..ready = false
      ..replied = true;
    unawaited(
      join.session.join().then((response) {
        if (!identical(join, _join)) {
          return;
        }
        for (final feature in features) {
          feature.joined(join.session, response);
        }
        join.ready = true;
        final held = [...join.held];
        join.held.clear();
        for (final message in held) {
          _receive(join, message);
        }
        // The login may have changed while the join was on its way.
        unawaited(refreshToken());
      }, onError: (Object _) {}),
    );
  }

  void _message(_Join join, PhoenixMessage message) {
    if (!identical(join, _join) || !join.replied) {
      return;
    }
    if (join.ready) {
      _receive(join, message);
    } else {
      join.held.add(message);
    }
  }

  void _receive(_Join join, PhoenixMessage message) {
    for (final feature in features) {
      if (feature.receive(join.session, message)) {
        return;
      }
    }
  }

  // The server ended the join, or the connection ended for good.
  void _done(_Join join) {
    if (identical(join, _join)) {
      _join = null;
      _finish();
    }
  }

  // An error event for every stream of the channel.
  void fail(Object error, [StackTrace? stackTrace]) {
    for (final feature in features) {
      feature.fail(error, stackTrace);
    }
  }

  // Runs [body] on the joined channel, joining it first; the channel is
  // not left meanwhile.
  Future<T> push<T>(
    Future<T> Function(PhoenixChannelSession session) body,
  ) async {
    _pushes++;
    try {
      while (true) {
        if (_ended) {
          throw StateError(
            'The Realtime channel ${handle.name} was left: use it again',
          );
        }
        final join = _open();
        await join.session.join();
        // Another configuration was asked meanwhile: its join counts.
        if (identical(join, _join)) {
          return await body(join.session);
        }
      }
    } on PhoenixJoinException {
      // Joined for this push only: not tried again for nobody.
      if (_pushes == 1 && !features.any((feature) => feature.inUse)) {
        _close();
      }
      rethrow;
    } finally {
      _pushes--;
    }
  }

  Future<void> untrack() async {
    final join = _join;
    final tracked = presences.tracked != null;
    presences.tracked = null;
    if (!tracked) {
      return;
    }
    _pushes++;
    try {
      if (join != null && join.session.state == PhoenixChannelState.joined) {
        await join.session.push('presence', const {
          'type': 'presence',
          'event': 'untrack',
        });
      }
    } finally {
      _pushes--;
      changed();
    }
  }

  // Brings the join in line with the access token when it is not the
  // one of the join any more: sent to the server when it is the same
  // user's, a new join when it is another user's or nobody's. The server
  // takes a token for a joined channel whoever it names, but goes on
  // sending the rows of the user before for a moment, and nothing here
  // could tell them from the new user's.
  Future<void> refreshToken() async {
    final join = _join;
    if (join == null || join.session.state != PhoenixChannelState.joined) {
      return;
    }
    final String token;
    try {
      token = await _token();
    } on Object catch (error) {
      // Never the error's text: it may quote what it could not read.
      _log.debug(
        'no access token for ${handle.topic}: ${error.runtimeType}',
      );
      return;
    }
    if (!identical(join, _join) ||
        join.session.state != PhoenixChannelState.joined ||
        join.token == token) {
      return;
    }
    if (_userOf(join.token) != _userOf(token)) {
      try {
        _open(asAnother: true);
      } on Object catch (error, stackTrace) {
        fail(error, stackTrace);
      }
      return;
    }
    join.token = token;
    try {
      // The server does not answer this one.
      await join.session.send('access_token', {'access_token': token});
    } on Object catch (error) {
      _log.debug(
        'the access token of ${handle.topic} was not sent: '
        '${error.runtimeType}',
      );
    }
  }

  Future<void> leave() {
    final session = _join?.session;
    _close();
    return session?.done ?? Future.value();
  }

  // The application stops: the socket ends the join.
  void stop() {
    final join = _join;
    _join = null;
    if (join != null) {
      for (final subscription in join.subscriptions) {
        unawaited(subscription.cancel());
      }
    }
    _finish();
  }

  // Leaves the topic.
  void _close() {
    final join = _join;
    _join = null;
    join?.dispose();
    _finish();
  }

  void _finish() {
    if (_ended) {
      return;
    }
    _ended = true;
    realtime._forget(this);
    for (final feature in features) {
      feature.end();
    }
  }
}

/// The database changes of a channel: the subscriptions of its join,
/// and the routing of each change by the ids the server gave them.
final class _PostgresChanges implements _Feature {
  _PostgresChanges(this.channel);

  final _Channel channel;
  // Who listens, by subscription, in the order of the first listener.
  final _wanted = <String, _Subscription>{};
  final _listeners = <String, Set<StreamController<RealtimeRowChange>>>{};
  // The subscriptions of the join in force, in its order, and the ids
  // the server gave them.
  var _asked = <_Subscription>[];
  final _byId = <String, _Subscription>{};

  void add(
    _Subscription subscription,
    StreamController<RealtimeRowChange> listener,
  ) {
    _wanted.putIfAbsent(subscription.key, () => subscription);
    _listeners.putIfAbsent(subscription.key, () => {}).add(listener);
  }

  void remove(
    _Subscription subscription,
    StreamController<RealtimeRowChange> listener,
  ) {
    final listeners = _listeners[subscription.key];
    if (listeners == null) {
      return;
    }
    listeners.remove(listener);
    if (listeners.isEmpty) {
      _listeners.remove(subscription.key);
      _wanted.remove(subscription.key);
    }
  }

  Iterable<StreamController<RealtimeRowChange>> get _all => [
    for (final listeners in _listeners.values) ...listeners,
  ];

  @override
  bool get inUse => _wanted.isNotEmpty;

  @override
  void configure(Map<String, Object?> config) {
    config['postgres_changes'] = [
      for (final subscription in _wanted.values) subscription.json,
    ];
  }

  @override
  void opened() {
    _asked = [..._wanted.values];
    _byId.clear();
  }

  @override
  void joined(PhoenixChannelSession session, Object? response) {
    _byId.clear();
    if (_asked.isEmpty) {
      return;
    }
    final answered = switch (response) {
      {'postgres_changes': final List<Object?> subscriptions} => subscriptions,
      _ => const <Object?>[],
    };
    // As realtime-js: the reply names the subscriptions in the order of
    // the join, each with its id.
    final same =
        answered.length == _asked.length &&
        [
          for (final (index, asked) in _asked.indexed)
            asked.matches(answered[index]),
        ].every((matches) => matches);
    if (!same) {
      fail(
        RealtimeException(
          'the server answered the join with other subscriptions to '
          'database changes than were asked: no change can be told apart',
          topic: session.topic,
          extension: 'postgres_changes',
        ),
      );
      return;
    }
    for (final (index, asked) in _asked.indexed) {
      _byId['${(answered[index]! as Map)['id']}'] = asked;
    }
  }

  @override
  bool receive(PhoenixChannelSession session, PhoenixMessage message) {
    final payload = message.payload;
    if (message.event == 'postgres_changes') {
      if (payload case {'ids': final List<Object?> ids, 'data': final data}) {
        _route(ids, data);
      }
      return true;
    }
    if (message.event == 'system' &&
        payload is Map &&
        payload['extension'] == 'postgres_changes') {
      if (payload['status'] != 'ok') {
        fail(
          RealtimeException(
            '${payload['message'] ?? 'the subscription to database '
                    'changes failed'}',
            topic: session.topic,
            extension: 'postgres_changes',
            status: '${payload['status']}',
          ),
        );
      }
      return true;
    }
    return false;
  }

  void _route(List<Object?> ids, Object? data) {
    final change = RealtimeRowChange.of(data);
    if (change == null) {
      _log.debug('a change of an unknown kind is skipped');
      return;
    }
    final subscriptions = {
      for (final id in ids) ?_byId['$id'],
    };
    for (final subscription in subscriptions) {
      if (!subscription.takes(change)) {
        continue;
      }
      final listeners = _listeners[subscription.key] ?? const {};
      for (final listener in [...listeners]) {
        listener.add(change);
      }
    }
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    for (final listener in _all) {
      listener.addError(error, stackTrace);
    }
  }

  @override
  void end() {
    final listeners = _all;
    _wanted.clear();
    _listeners.clear();
    _asked = [];
    _byId.clear();
    for (final listener in listeners) {
      unawaited(listener.close());
    }
  }
}

/// The broadcasts of a channel: each to the listeners of its event.
final class _Broadcasts implements _Feature {
  _Broadcasts(this.channel);

  final _Channel channel;
  final _listeners = <String, Set<StreamController<Object?>>>{};

  void add(String event, StreamController<Object?> listener) =>
      _listeners.putIfAbsent(event, () => {}).add(listener);

  void remove(String event, StreamController<Object?> listener) {
    final listeners = _listeners[event];
    if (listeners != null && listeners.remove(listener) && listeners.isEmpty) {
      _listeners.remove(event);
    }
  }

  Iterable<StreamController<Object?>> get _all => [
    for (final listeners in _listeners.values) ...listeners,
  ];

  @override
  bool get inUse => _listeners.isNotEmpty;

  @override
  void configure(Map<String, Object?> config) {
    config['broadcast'] = {
      'ack': channel.handle.ack,
      'self': channel.handle.self,
    };
  }

  @override
  void opened() {}

  @override
  void joined(PhoenixChannelSession session, Object? response) {}

  @override
  bool receive(PhoenixChannelSession session, PhoenixMessage message) {
    if (message.event != 'broadcast') {
      return false;
    }
    if (message.payload case {'event': final String event} && final payload) {
      for (final listener in [...?_listeners[event]]) {
        listener.add(payload['payload']);
      }
    }
    return true;
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    for (final listener in _all) {
      listener.addError(error, stackTrace);
    }
  }

  @override
  void end() {
    final listeners = _all;
    _listeners.clear();
    for (final listener in listeners) {
      unawaited(listener.close());
    }
  }
}

/// The presence of a channel: who is there, kept from `presence_state`
/// and `presence_diff` as `phoenix.js` does, and what this client
/// tracks.
final class _Presences implements _Feature {
  _Presences(this.channel);

  final _Channel channel;
  final _listeners = <StreamController<List<RealtimePresence>>>{};
  final _state = RealtimePresenceState();
  // Diffs that came after a join and before its `presence_state`.
  final _pending = <Object?>[];
  // The join the state was sent for; another one: the state is awaited.
  String? _joinRef;
  var _synced = false;
  // Presence is part of the join in force. It stays on for the life of
  // the channel: turning it off would mean joining again.
  var _enabled = false;
  // The push that tracked `tracked` for one join.
  ({String? joinRef, Map<String, Object?> state, Future<void> done})? _tracking;

  /// What this client tracks; null for nothing.
  Map<String, Object?>? tracked;

  void add(StreamController<List<RealtimePresence>> listener) {
    _listeners.add(listener);
    if (_synced) {
      listener.add(_state.presences);
    }
  }

  void remove(StreamController<List<RealtimePresence>> listener) =>
      _listeners.remove(listener);

  // Tracks `tracked` on [session], once per join and state.
  Future<void> track(PhoenixChannelSession session) {
    final state = tracked;
    if (state == null) {
      return Future.value();
    }
    final joinRef = session.joinRef;
    final tracking = _tracking;
    if (tracking != null &&
        tracking.joinRef == joinRef &&
        identical(tracking.state, state)) {
      return tracking.done;
    }
    final done = session
        .push('presence', {
          'type': 'presence',
          'event': 'track',
          'payload': state,
        })
        .then((_) {});
    _tracking = (joinRef: joinRef, state: state, done: done);
    return done;
  }

  @override
  bool get inUse => _listeners.isNotEmpty || tracked != null;

  @override
  void configure(Map<String, Object?> config) {
    _enabled = _enabled || inUse;
    config['presence'] = {
      'key': channel.handle.presenceKey ?? '',
      'enabled': _enabled,
    };
  }

  @override
  void opened() {}

  @override
  void joined(PhoenixChannelSession session, Object? response) {
    // What was tracked is tracked again for this join; who asked waits
    // for the same push.
    unawaited(
      track(session).then(
        (_) {},
        onError: (Object error) {
          _log.debug(
            'the presence of ${session.topic} was not tracked: $error',
          );
        },
      ),
    );
  }

  @override
  bool receive(PhoenixChannelSession session, PhoenixMessage message) {
    if (message.event == 'presence_state') {
      _joinRef = session.joinRef;
      _state.syncState(message.payload);
      _pending.forEach(_state.syncDiff);
      _pending.clear();
      _synced = true;
      _emit();
      return true;
    }
    if (message.event == 'presence_diff') {
      if (_joinRef == null || _joinRef != session.joinRef) {
        _pending.add(message.payload);
      } else {
        _state.syncDiff(message.payload);
        _emit();
      }
      return true;
    }
    return false;
  }

  void _emit() {
    final presences = _state.presences;
    for (final listener in [..._listeners]) {
      listener.add(presences);
    }
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {
    for (final listener in [..._listeners]) {
      listener.addError(error, stackTrace);
    }
  }

  @override
  void end() {
    final listeners = [..._listeners];
    _listeners.clear();
    _state.clear();
    _pending.clear();
    _joinRef = null;
    _synced = false;
    _enabled = false;
    _tracking = null;
    tracked = null;
    for (final listener in listeners) {
      unawaited(listener.close());
    }
  }
}

/// The server's notices about the channel itself (`system` messages):
/// an error is told to every stream; the server then closes the channel.
final class _Notices implements _Feature {
  _Notices(this.channel);

  final _Channel channel;

  @override
  bool get inUse => false;

  @override
  void configure(Map<String, Object?> config) {}

  @override
  void opened() {}

  @override
  void joined(PhoenixChannelSession session, Object? response) {}

  @override
  bool receive(PhoenixChannelSession session, PhoenixMessage message) {
    if (message.event != 'system') {
      return false;
    }
    if (message.payload case {'status': final status} && final payload
        when status != 'ok') {
      channel.fail(
        RealtimeException(
          '${payload['message'] ?? 'the server reported a problem'}',
          topic: session.topic,
          extension: switch (payload['extension']) {
            final String extension => extension,
            _ => null,
          },
          status: '$status',
        ),
      );
    }
    return true;
  }

  @override
  void fail(Object error, [StackTrace? stackTrace]) {}

  @override
  void end() {}
}
