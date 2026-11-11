import 'dart:async';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_message.dart';
import 'package:spring_boot_starter_websocket/src/phoenix/phoenix_serializer.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_client_config.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_connection_manager.dart';
import 'package:spring_boot_starter_websocket/src/web_socket_handshake.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

/// Gives the extra query parameters of a [PhoenixSocket]'s handshake,
/// such as a token. It is called for every connection and reconnection,
/// so each one carries a fresh value.
///
/// ```dart
/// PhoenixParameters parameters = () async {
///   return {'token': await tokens.current()};
/// };
/// ```
///
/// Phoenix (JavaScript): the `params` option of `new Socket(...)`, which
/// may be a function too.
typedef PhoenixParameters = FutureOr<Map<String, String>> Function();

/// Gives the payload a [PhoenixChannelSession] joins its topic with. It
/// is called for every join, also the ones after a reconnection, so each
/// carries a fresh value.
///
/// ```dart
/// PhoenixJoinPayload payload = () async {
///   return {'token': await tokens.current()};
/// };
/// ```
///
/// Phoenix (JavaScript): the `params` of `socket.channel(topic, params)`,
/// which may be a function too.
typedef PhoenixJoinPayload = FutureOr<Map<String, Object?>> Function();

/// One connection to a server that speaks the Phoenix Channels protocol
/// (a Phoenix application, or a service built on it), carrying any
/// number of channels.
///
/// Ask it for a [channel] per topic and join that. The socket connects
/// when the first channel joins and closes when the last one is left. It
/// keeps the connection as a `@WebSocketClient` does (the same
/// [WebSocketConnectionManager], reconnect policy and handshake
/// interceptors), numbers the messages ([nextRef]) and sends a heartbeat;
/// one without a reply before the next drops the connection, which is
/// opened again. After every reconnection the channels join again.
///
/// The [url] is the full address of the socket's WebSocket endpoint,
/// `/websocket` included (`ws://host/socket/websocket`); the socket adds
/// the `vsn` of its [serializer] and its [parameters] to the query.
///
/// Applications usually declare a `@PhoenixChannel` interface instead; a
/// library takes a socket from the `PhoenixSocketFactory` bean, which
/// reads the settings and closes the sockets at shutdown.
///
/// ```dart
/// final socket = sockets.socket(
///   'chat',
///   parameters: () async => {'token': await tokens.current()},
/// );
/// final room = socket.channel('room:42');
/// room.on('new_msg').listen(show);
/// await room.join();
/// await room.push('new_msg', {'body': 'hi'});
/// ```
///
/// Phoenix (JavaScript):
/// ```js
/// let socket = new Socket("/socket", {params: {token}})
/// socket.connect()
/// let room = socket.channel("room:42")
/// ```
///
/// Differs from Phoenix: no `connect()`; the connection follows the
/// channels. Only the WebSocket transport, no long polling.
final class PhoenixSocket {
  /// A socket named [name] for the endpoint [url], opened through
  /// [transport] when its first channel joins.
  PhoenixSocket({
    required this.name,
    required this.url,
    required WebSocketTransport transport,
    this.config = const WebSocketClientConfig(),
    this.serializer = const PhoenixSerializerV2(),
    this.parameters,
    List<WebSocketHandshakeInterceptor> interceptors = const [],
    SpringLog? log,
  }) : _log = log ?? SpringLog('websocket.phoenix.$name') {
    connectionManager = WebSocketConnectionManager(
      clientName: name,
      url: url,
      config: config,
      transport: transport,
      interceptors: [_PhoenixHandshake(this), ...interceptors],
      log: _log,
    );
    _changes = connectionManager.connectionChanges.listen(_connectionChanged);
  }

  /// The name of the client: its settings are
  /// `spring.websocket.client.config.<name>.*`, and a
  /// `WebSocketHandshakeInterceptor` sees it as
  /// `WebSocketHandshake.clientName`.
  final String name;

  /// The address of the WebSocket endpoint, before the `vsn`, the
  /// [parameters] and the interceptors change its query.
  final Uri url;

  /// The client's settings: timeouts, reconnection, and under
  /// `phoenix` the heartbeat interval and the push timeout.
  final WebSocketClientConfig config;

  /// The wire format; its `vsn` goes into the handshake's query.
  final PhoenixSerializer serializer;

  /// The extra query parameters, asked for every connection; `null` for
  /// none.
  final PhoenixParameters? parameters;

  /// Keeps the one connection, as for a `@WebSocketClient`.
  late final WebSocketConnectionManager connectionManager;

  final SpringLog _log;
  late final StreamSubscription<bool> _changes;
  late final _heartbeat = _Heartbeat(this);
  final _channels = <PhoenixChannelSession>[];
  StreamSubscription<Object>? _subscription;
  Object? _failure;
  StackTrace? _failureTrace;
  var _ref = 0;
  var _disposed = false;

  /// Whether the connection is open now.
  bool get isConnected => connectionManager.isConnected;

  /// The channels that were joined and not left yet, in the order of
  /// their joins.
  List<PhoenixChannelSession> get channels => List.unmodifiable(_channels);

  /// The next message number of this socket: `1`, `2`, and so on. Every
  /// message that expects a reply gets one, and so does every join.
  String nextRef() => '${++_ref}';

  /// A channel for [topic], not joined yet: call
  /// [PhoenixChannelSession.join]. [payload] gives what each join sends,
  /// nothing (`{}`) without it.
  ///
  /// Every call gives a new channel. A server keeps one channel per topic
  /// on a connection: when a second one joins the same topic, it closes
  /// the first.
  PhoenixChannelSession channel(String topic, {PhoenixJoinPayload? payload}) =>
      PhoenixChannelSession._(this, topic, payload);

  /// Sends [message] as it is when the connection is open, and says
  /// whether it was. Channels use it; code on top may send a message of
  /// its own, numbered by [nextRef]. Throws when the payload is not JSON.
  bool send(PhoenixMessage message) {
    if (!isConnected) {
      return false;
    }
    final frame = serializer.encode(message);
    unawaited(
      connectionManager
          .sendMessage(frame)
          .then(
            (_) {},
            onError: (Object error) {
              _log.debug(
                'cannot send ${message.event} on ${message.topic}: '
                '${redactText('$error')}',
                fields: {'client': name},
              );
            },
          ),
    );
    return true;
  }

  /// Closes for good, when the application stops: every channel ends
  /// (its streams are done) and the connection closes. Joining a channel
  /// of this socket afterwards fails with a [StateError].
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _heartbeat.stop();
    unawaited(_changes.cancel());
    unawaited(_subscription?.cancel());
    _subscription = null;
    final channels = [..._channels];
    _channels.clear();
    for (final channel in channels) {
      channel._close();
    }
    await connectionManager.dispose();
  }

  // A channel joins: the first one opens the connection.
  void _attach(PhoenixChannelSession channel) {
    if (_disposed) {
      throw StateError(
        'The Phoenix socket $name is closed: the application stopped',
      );
    }
    _channels.add(channel);
    _subscription ??= connectionManager.messages().listen(
      _received,
      onError: (Object error, StackTrace stackTrace) {
        _failure = error;
        _failureTrace = stackTrace;
      },
      onDone: _ended,
    );
  }

  // A channel ended: the last one closes the connection.
  Future<void> _detach(PhoenixChannelSession channel) {
    if (!_channels.remove(channel) || _channels.isNotEmpty || _disposed) {
      return Future.value();
    }
    _heartbeat.stop();
    unawaited(_subscription?.cancel());
    _subscription = null;
    return connectionManager.close();
  }

  void _connectionChanged(bool open) {
    if (open) {
      _heartbeat.start();
      for (final channel in [..._channels]) {
        channel._connected();
      }
    } else {
      _heartbeat.stop();
      for (final channel in [..._channels]) {
        channel._disconnected();
      }
    }
  }

  void _received(Object frame) {
    if (frame is! String) {
      _log.debug('a binary frame is skipped', fields: {'client': name});
      return;
    }
    final PhoenixMessage message;
    try {
      message = serializer.decode(frame);
    } on Object catch (error) {
      _log.debug(
        'a frame that is no Phoenix message is skipped: $error',
        fields: {'client': name},
      );
      return;
    }
    if (_heartbeat.receive(message)) {
      return;
    }
    for (final channel in [..._channels]) {
      channel._receive(message);
    }
  }

  // The connection ended for good: the server closed it with a code
  // that is not retried, or the retries were given up.
  void _ended() {
    _subscription = null;
    _heartbeat.stop();
    final error = _failure;
    final stackTrace = _failureTrace;
    _failure = null;
    _failureTrace = null;
    final channels = [..._channels];
    _channels.clear();
    for (final channel in channels) {
      channel._close(error, stackTrace);
    }
  }

  @override
  String toString() => 'PhoenixSocket($name, ${redactUrl(url)})';
}

/// Adds the socket's `vsn` and its parameters to every handshake.
final class _PhoenixHandshake implements WebSocketHandshakeInterceptor {
  _PhoenixHandshake(this._socket);

  final PhoenixSocket _socket;

  @override
  Future<void> apply(WebSocketHandshake handshake) async {
    final parameters = await _socket.parameters?.call();
    handshake.queryParameter('vsn', _socket.serializer.vsn);
    for (final MapEntry(:key, :value) in (parameters ?? const {}).entries) {
      handshake.queryParameter(key, value);
    }
  }
}

/// The heartbeat of a socket: one message per interval while the
/// connection is open; a beat without a reply before the next one means
/// the connection is dead.
final class _Heartbeat {
  _Heartbeat(this._socket);

  final PhoenixSocket _socket;
  Timer? _timer;
  String? _pending;

  void start() {
    stop();
    final interval = _socket.config.phoenix.heartbeatInterval;
    if (interval > Duration.zero) {
      _timer = Timer.periodic(interval, (_) => _beat());
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  void _beat() {
    if (_pending != null) {
      _socket._log.debug(
        'no reply to the heartbeat: reconnecting',
        fields: {'client': _socket.name},
      );
      _socket.connectionManager.reconnect('heartbeat timeout');
      return;
    }
    final ref = _pending = _socket.nextRef();
    _socket.send(
      PhoenixMessage(
        topic: PhoenixEvents.heartbeatTopic,
        event: PhoenixEvents.heartbeat,
        payload: const <String, Object?>{},
        ref: ref,
      ),
    );
  }

  // Whether [message] was the heartbeat's: everything on its topic.
  bool receive(PhoenixMessage message) {
    if (message.topic != PhoenixEvents.heartbeatTopic) {
      return false;
    }
    if (message.ref == _pending) {
      _pending = null;
    }
    return true;
  }
}

/// Where a [PhoenixChannelSession] is in its life.
///
/// ```dart
/// room.states.listen((state) {
///   offline.value = state == PhoenixChannelState.errored;
/// });
/// ```
///
/// Phoenix (JavaScript): `CHANNEL_STATES` of `phoenix.js`.
enum PhoenixChannelState {
  /// Not joined yet, or ended: left, closed by the server, or its socket
  /// ended.
  closed,

  /// The join was asked and its reply is awaited, or the connection is
  /// being opened for it.
  joining,

  /// The server accepted the join: events arrive and pushes are sent.
  joined,

  /// The join failed, the channel crashed on the server (`phx_error`) or
  /// the connection was lost; it joins again by itself.
  errored,

  /// [PhoenixChannelSession.leave] was called and its reply is awaited.
  leaving,
}

/// One topic of a [PhoenixSocket], from its join to its end: the events
/// the server sends on it, and pushes to the server with their replies.
///
/// A socket gives one with [PhoenixSocket.channel]. Listen to [messages]
/// or [on] first, then [join]; [push] sends an event and returns the
/// server's reply. Once joined it stays so: after a reconnection of the
/// socket, or when the server reports a crash of the channel
/// (`phx_error`), it joins again with a fresh join payload, and the
/// listeners keep receiving. A join that fails is tried again as well,
/// with the waits of the socket's reconnect policy, until [leave]. It
/// ends with [leave], when the server closes it (`phx_close`), or when
/// the socket's connection ends for good; then the streams are done and a
/// new channel is needed.
///
/// ```dart
/// final room = socket.channel(
///   'room:42',
///   payload: () async => {'token': await tokens.current()},
/// );
/// room.on('new_msg').listen(show);
/// await room.join();
/// final reply = await room.push('new_msg', {'body': 'hi'});
/// await room.leave();
/// ```
///
/// Phoenix (JavaScript):
/// ```js
/// let room = socket.channel("room:42", () => ({token}))
/// room.on("new_msg", show)
/// room.join().receive("ok", ...).receive("error", ...)
/// room.push("new_msg", {body: "hi"}).receive("ok", ...)
/// room.leave()
/// ```
///
/// Differs from Phoenix: it is the `Channel` of `phoenix.js`, named a
/// session here because `@PhoenixChannel` is the annotation; replies are
/// futures and events are streams instead of callbacks.
final class PhoenixChannelSession {
  PhoenixChannelSession._(this.socket, this.topic, this._payload);

  /// The socket that carries the channel.
  final PhoenixSocket socket;

  /// The topic, such as `room:42`.
  final String topic;

  final PhoenixJoinPayload? _payload;
  final _states = StreamController<PhoenixChannelState>.broadcast();
  final _messages = StreamController<PhoenixMessage>.broadcast();
  final _done = Completer<void>();
  // Pushes awaiting their reply, by ref, and those made before the join
  // succeeded.
  final _pending = <String, _Push>{};
  final _buffer = <_Push>[];
  late final Map<String, void Function(PhoenixMessage message)> _lifecycle = {
    PhoenixEvents.reply: _replied,
    PhoenixEvents.close: _closedByServer,
    PhoenixEvents.error: _erroredByServer,
  };
  PhoenixChannelState _state = PhoenixChannelState.closed;
  var _attached = false;
  var _ended = false;
  // The ref of the join in progress or in force; null in between.
  String? _joinRef;
  // Bumped with every join: a join payload that arrives late is dropped.
  var _attempt = 0;
  // What the callers of join() wait for, and their time limit.
  Completer<Object?>? _join;
  Timer? _joinDeadline;
  // Waits for the reply to the join that was sent.
  Timer? _joinTimeout;
  Timer? _rejoin;
  var _rejoins = 0;
  Object? _response;
  String? _leaveRef;
  Timer? _leaveTimeout;

  /// Where the channel is in its life: [PhoenixChannelState.closed]
  /// before [join] and after its end.
  PhoenixChannelState get state => _state;

  /// Each new [state], from the moment of listening; done when the
  /// channel ended.
  Stream<PhoenixChannelState> get states => _states.stream;

  /// The ref of the join in force, which the server puts on what it
  /// sends for it; `null` while not joined.
  String? get joinRef => _joinRef;

  /// Every event the server sends on the topic, replies and the
  /// protocol's own (`phx_...`) left out. Listen before [join] to miss
  /// nothing. The stream goes on over reconnections; it is done when the
  /// channel ended, after an error event when the socket's connection
  /// failed for good.
  Stream<PhoenixMessage> get messages => _messages.stream;

  /// Completes when the channel ended: left, closed by the server, or
  /// its socket ended.
  Future<void> get done => _done.future;

  /// The payloads of the events named [event], as decoded JSON; see
  /// [messages].
  ///
  /// ```dart
  /// room.on('new_msg').listen((payload) => show(payload! as Map));
  /// ```
  Stream<Object?> on(String event) => messages
      .where((message) => message.event == event)
      .map((message) => message.payload);

  /// Joins the topic, opening the socket's connection when this is its
  /// first channel, and completes with the response of the server's
  /// reply (often an empty map).
  ///
  /// It fails with a [PhoenixJoinException] when the server answers
  /// `error`, when no answer comes within the push timeout (counted from
  /// this call, the time to connect included), or when the channel is
  /// left first. The channel goes on trying after such a failure; call
  /// [leave] to give up. While joined it completes at once with the
  /// response of the join in force; called again while the channel is
  /// joining again, it waits for that outcome. On an ended channel it
  /// fails with a [StateError].
  Future<Object?> join() {
    if (_ended || _state == PhoenixChannelState.leaving) {
      return Future.error(_endedError());
    }
    if (_state == PhoenixChannelState.joined) {
      return Future.value(_response);
    }
    final waiting = _join;
    if (waiting != null && !waiting.isCompleted) {
      return waiting.future;
    }
    if (!_attached) {
      try {
        socket._attach(this);
      } on StateError catch (error, stackTrace) {
        return Future.error(error, stackTrace);
      }
      _attached = true;
      _setState(PhoenixChannelState.joining);
      if (socket.isConnected) {
        _sendJoin();
      }
    }
    final join = _join = Completer<Object?>();
    _joinDeadline = Timer(socket.config.phoenix.pushTimeout, () {
      _completeJoin(
        error: PhoenixJoinException(
          topic,
          'no reply to the join in time',
          isTimeout: true,
        ),
      );
    });
    return join.future;
  }

  /// Sends [event] with [payload] (JSON: usually a map; `null` sends
  /// `{}`) and completes with the server's `ok` reply.
  ///
  /// It fails with a [PhoenixPushException] when the reply is an `error`
  /// or the channel ends first, and with a [TimeoutException] when no
  /// reply comes within [timeout] (the socket's push timeout by default).
  /// A push made while the channel is joining, or joining again, is sent
  /// once it joined; the time limit runs meanwhile. Before [join] and
  /// after the end it fails with a [StateError].
  ///
  /// ```dart
  /// final reply = await room.push('new_msg', {'body': 'hi'});
  /// ```
  Future<PhoenixReply> push(
    String event,
    Object? payload, {
    Duration? timeout,
  }) {
    if (_notOpen() case final error?) {
      return Future.error(error);
    }
    final reply = Completer<PhoenixReply>();
    final push = _Push(event, payload, reply: reply);
    final limit = timeout ?? socket.config.phoenix.pushTimeout;
    push.timer = Timer(limit, () {
      _buffer.remove(push);
      _pending.remove(push.ref);
      push.fail(
        TimeoutException('no reply to "$event" on $topic in time', limit),
      );
    });
    _submit(push);
    return reply.future;
  }

  /// Sends [event] with [payload] without waiting for a reply, for an
  /// event the server does not answer (`{:noreply, socket}`); completes
  /// when it was handed to the connection, after the join when the
  /// channel is joining. Fails as [push] does when the channel ends
  /// first.
  ///
  /// ```dart
  /// await room.send('typing', {'user': 'ann'});
  /// ```
  Future<void> send(String event, [Object? payload]) {
    if (_notOpen() case final error?) {
      return Future.error(error);
    }
    final sent = Completer<void>();
    _submit(_Push(event, payload, sent: sent));
    return sent.future;
  }

  /// Leaves the topic: tells the server when joined, waits for its reply
  /// (at most the push timeout) and ends the channel. Its streams are
  /// done, pushes without a reply fail, and the socket closes its
  /// connection when this was its last channel. Leaving twice, or before
  /// [join], is harmless.
  Future<void> leave() {
    if (_ended || _state == PhoenixChannelState.leaving) {
      return done;
    }
    final joinRef = _joinRef;
    _attempt++;
    _cancelTimers();
    _setState(PhoenixChannelState.leaving);
    _completeJoin(
      error: PhoenixJoinException(topic, 'left before it was joined'),
    );
    if (joinRef == null || !socket.isConnected) {
      _close();
      return done;
    }
    final ref = _leaveRef = socket.nextRef();
    _leaveTimeout = Timer(socket.config.phoenix.pushTimeout, _close);
    socket.send(
      PhoenixMessage(
        topic: topic,
        event: PhoenixEvents.leave,
        payload: const <String, Object?>{},
        ref: ref,
        joinRef: joinRef,
      ),
    );
    return done;
  }

  StateError _endedError() => StateError(
    'The Phoenix channel $topic ended: ask the socket for a new one',
  );

  StateError? _notOpen() {
    if (_ended || _state == PhoenixChannelState.leaving) {
      return _endedError();
    }
    if (!_attached) {
      return StateError(
        'The Phoenix channel $topic is not joined: call join()',
      );
    }
    return null;
  }

  void _setState(PhoenixChannelState state) {
    if (_state != state) {
      _state = state;
      _states.add(state);
    }
  }

  void _cancelTimers() {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    _rejoin?.cancel();
    _rejoin = null;
    _leaveTimeout?.cancel();
    _leaveTimeout = null;
  }

  // Tells the callers of join() the outcome, once.
  void _completeJoin({
    Object? response,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _joinDeadline?.cancel();
    _joinDeadline = null;
    final join = _join;
    if (join == null || join.isCompleted) {
      return;
    }
    if (error == null) {
      join.complete(response);
    } else {
      join.completeError(error, stackTrace);
    }
  }

  // Starts a join over the open connection.
  void _sendJoin() {
    final attempt = ++_attempt;
    _joinTimeout?.cancel();
    _joinRef = null;
    unawaited(_startJoin(attempt));
  }

  Future<void> _startJoin(int attempt) async {
    final Map<String, Object?> payload;
    try {
      payload = await _payload?.call() ?? const {};
    } on Object catch (error, stackTrace) {
      if (attempt == _attempt) {
        _joinFailed(
          PhoenixJoinException(
            topic,
            'cannot make the join payload: $error',
            cause: error,
          ),
          stackTrace,
        );
      }
      return;
    }
    if (attempt != _attempt || !socket.isConnected) {
      return;
    }
    final ref = _joinRef = socket.nextRef();
    try {
      socket.send(
        PhoenixMessage(
          topic: topic,
          event: PhoenixEvents.join,
          payload: payload,
          ref: ref,
          joinRef: ref,
        ),
      );
    } on Object catch (error, stackTrace) {
      _joinRef = null;
      _joinFailed(
        PhoenixJoinException(
          topic,
          'cannot write the join payload: $error',
          cause: error,
        ),
        stackTrace,
      );
      return;
    }
    _joinTimeout = Timer(socket.config.phoenix.pushTimeout, () {
      // As phoenix.js does: the server may have joined us all the same.
      socket.send(
        PhoenixMessage(
          topic: topic,
          event: PhoenixEvents.leave,
          payload: const <String, Object?>{},
          ref: socket.nextRef(),
          joinRef: ref,
        ),
      );
      _joinRef = null;
      _joinFailed(
        PhoenixJoinException(
          topic,
          'no reply to the join in time',
          isTimeout: true,
        ),
      );
    });
  }

  // This join failed: its callers are told, and it is tried again.
  void _joinFailed(Object error, [StackTrace? stackTrace]) {
    _joinTimeout?.cancel();
    _joinTimeout = null;
    _setState(PhoenixChannelState.errored);
    _completeJoin(error: error, stackTrace: stackTrace);
    _scheduleRejoin();
  }

  // Joins again after the wait of the socket's reconnect policy, while
  // the connection is open; a new connection joins at once.
  void _scheduleRejoin() {
    _rejoin?.cancel();
    _rejoin = null;
    if (!socket.isConnected) {
      return;
    }
    final delay = socket.config.reconnect.delayFor(++_rejoins);
    _rejoin = Timer(delay, () {
      _rejoin = null;
      if (socket.isConnected && _state == PhoenixChannelState.errored) {
        _setState(PhoenixChannelState.joining);
        _sendJoin();
      }
    });
  }

  // The socket's connection opened: the first join, or a join again.
  void _connected() {
    _rejoin?.cancel();
    _rejoin = null;
    _rejoins = 0;
    if (_state == PhoenixChannelState.errored ||
        _state == PhoenixChannelState.joining) {
      _setState(PhoenixChannelState.joining);
      _sendJoin();
    }
  }

  // The socket's connection was lost: nothing of this join is left.
  void _disconnected() {
    if (_state == PhoenixChannelState.leaving) {
      _close();
      return;
    }
    _attempt++;
    _joinRef = null;
    _cancelTimers();
    if (_state == PhoenixChannelState.joined ||
        _state == PhoenixChannelState.joining) {
      _setState(PhoenixChannelState.errored);
    }
  }

  // A message of the socket: taken when it is for this topic and this
  // join.
  void _receive(PhoenixMessage message) {
    if (_ended || message.topic != topic) {
      return;
    }
    final joinRef = message.joinRef;
    if (joinRef != null && joinRef != _joinRef) {
      socket._log.debug(
        'a message of an older join of $topic is dropped '
        '(${message.event}, join_ref $joinRef)',
        fields: {'client': socket.name},
      );
      return;
    }
    (_lifecycle[message.event] ?? _messages.add)(message);
  }

  void _replied(PhoenixMessage message) {
    final ref = message.ref;
    if (ref == null) {
      return;
    }
    final reply = PhoenixReply.of(message.payload);
    if (ref == _leaveRef) {
      _close();
    } else if (ref == _joinRef && _state == PhoenixChannelState.joining) {
      _joinReplied(reply);
    } else {
      _pending.remove(ref)?.replied(this, reply);
    }
  }

  void _joinReplied(PhoenixReply reply) {
    if (!reply.isOk) {
      _joinRef = null;
      _joinFailed(
        PhoenixJoinException(
          topic,
          'the server refused the join: ${reply.response}',
          reply: reply,
        ),
      );
      return;
    }
    _cancelTimers();
    _rejoins = 0;
    _response = reply.response;
    _setState(PhoenixChannelState.joined);
    _completeJoin(response: reply.response);
    final buffered = [..._buffer];
    _buffer.clear();
    buffered.forEach(_transmit);
  }

  // phx_close and phx_error carry the join's ref as their own ref too,
  // which is all the first wire format has.
  bool _ofThisJoin(PhoenixMessage message) =>
      (message.joinRef ?? message.ref ?? _joinRef) == _joinRef;

  void _closedByServer(PhoenixMessage message) {
    if (_ofThisJoin(message)) {
      _close();
    }
  }

  void _erroredByServer(PhoenixMessage message) {
    final open =
        _state == PhoenixChannelState.joined ||
        _state == PhoenixChannelState.joining;
    if (!open || !_ofThisJoin(message)) {
      return;
    }
    _attempt++;
    _joinRef = null;
    _cancelTimers();
    _setState(PhoenixChannelState.errored);
    _scheduleRejoin();
  }

  void _submit(_Push push) {
    if (_state == PhoenixChannelState.joined) {
      _transmit(push);
    } else {
      _buffer.add(push);
    }
  }

  void _transmit(_Push push) {
    final ref = socket.nextRef();
    try {
      socket.send(
        PhoenixMessage(
          topic: topic,
          event: push.event,
          payload: push.payload ?? const <String, Object?>{},
          ref: ref,
          joinRef: _joinRef,
        ),
      );
    } on Object catch (error, stackTrace) {
      push.fail(error, stackTrace);
      return;
    }
    push.ref = ref;
    if (push.reply != null) {
      _pending[ref] = push;
    }
    push.sent?.complete();
  }

  // The end of the channel, with [error] when its socket failed.
  void _close([Object? error, StackTrace? stackTrace]) {
    if (_ended) {
      return;
    }
    _ended = true;
    _attempt++;
    _joinRef = null;
    _cancelTimers();
    _completeJoin(
      error: error ?? PhoenixJoinException(topic, 'the channel closed'),
      stackTrace: stackTrace,
    );
    final pushes = [..._pending.values, ..._buffer];
    _pending.clear();
    _buffer.clear();
    for (final push in pushes) {
      push.fail(
        error ??
            PhoenixPushException(
              topic,
              push.event,
              'the channel closed before the reply',
            ),
        stackTrace,
      );
    }
    _setState(PhoenixChannelState.closed);
    if (error != null) {
      _messages.addError(error, stackTrace);
    }
    unawaited(_messages.close());
    unawaited(_states.close());
    final detached = _attached
        ? socket._detach(this).then((_) {}, onError: (_) {})
        : null;
    _done.complete(detached);
  }

  @override
  String toString() => 'PhoenixChannelSession($topic, ${_state.name})';
}

/// One push of a channel: what to send, and who waits for it.
final class _Push {
  _Push(this.event, this.payload, {this.reply, this.sent});

  final String event;
  final Object? payload;
  // Completed with the server's reply; null for a push without one.
  final Completer<PhoenixReply>? reply;
  // Completed when the push was handed to the connection.
  final Completer<void>? sent;
  Timer? timer;
  String? ref;

  void replied(PhoenixChannelSession channel, PhoenixReply answer) {
    timer?.cancel();
    if (answer.isOk) {
      reply?.complete(answer);
    } else {
      reply?.completeError(
        PhoenixPushException(
          channel.topic,
          event,
          'the server answered ${answer.status}: ${answer.response}',
          reply: answer,
        ),
      );
    }
  }

  void fail(Object error, [StackTrace? stackTrace]) {
    timer?.cancel();
    for (final waiter in [reply, sent]) {
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(error, stackTrace);
      }
    }
  }
}
