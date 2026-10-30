import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/websocket/web_socket_transport.dart';

/// The [WebSocketTransport] for platforms with `dart:io` (the Dart VM,
/// Flutter on mobile and desktop), built on `dart:io`'s `WebSocket`.
///
/// `platformWebSocketTransport()` returns one on these platforms, so you
/// create it yourself only to pass an `HttpClient` for the handshakes: a
/// proxy, trusted certificates. Unlike the browser transport it sends
/// handshake headers, such as `Authorization`. A handshake that fails or
/// runs out of time throws a [WebSocketException].
///
/// What a session sends waits in memory while the server does not read
/// it; past [sendBufferSizeLimit] bytes waiting, or when what was sent
/// has not left within [sendTimeLimit], the connection is dropped (see
/// [IoWebSocketSession]). A message from the server larger than
/// [maxTextMessageSize] or [maxBinaryMessageSize] (8 KB each by default,
/// as Tomcat's client in Spring) is not read: the session is closed with
/// 1009 (message too big). No extension is offered, so messages are not
/// compressed (permessage-deflate), and a handshake answer that picks an
/// extension, or a subprotocol that was not offered, is refused (RFC 6455
/// §4.1). Redirects are not followed, as in browsers.
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// // A token in a header, which a browser could not send.
/// final transport = IoWebSocketTransport();
/// final session = await transport.connect(
///   Uri.parse('wss://chat.neon.books/ws'),
///   headers: HttpHeaders({'Authorization': 'Bearer $token'}),
/// );
/// ```
///
/// Spring (Java): `StandardWebSocketClient`.
class IoWebSocketTransport implements WebSocketTransport {
  /// A transport whose handshakes go through `client`, an `HttpClient`
  /// with your proxy or TLS settings; without it a default client is
  /// used. [sendBufferSizeLimit] and [sendTimeLimit] bound what each
  /// session keeps waiting for a server that does not read;
  /// [maxTextMessageSize] and [maxBinaryMessageSize] bound each message
  /// it receives.
  IoWebSocketTransport({
    this._client,
    this.sendBufferSizeLimit = IoWebSocketSession.defaultSendBufferSizeLimit,
    this.sendTimeLimit = IoWebSocketSession.defaultSendTimeLimit,
    this.maxTextMessageSize = IoWebSocketSession.defaultMaxMessageSize,
    this.maxBinaryMessageSize = IoWebSocketSession.defaultMaxMessageSize,
  });

  // The client for the handshakes (`null`: a default one).
  final io.HttpClient? _client;

  /// The most bytes a session keeps waiting to be sent; 512 KB by
  /// default, `-1` for no limit.
  final int sendBufferSizeLimit;

  /// How long what a session sent may take to leave; 10 seconds by
  /// default, `null` for no limit.
  final Duration? sendTimeLimit;

  /// The largest text message a session receives, in UTF-8 bytes; 8 KB
  /// by default (Tomcat's `maxTextMessageBufferSize`, which Spring's
  /// `StandardWebSocketClient` gets), `-1` for no limit. A larger one is
  /// not read, and the session is closed with 1009 (message too big).
  /// Tomcat counts characters, so text outside ASCII reaches this limit
  /// sooner than Tomcat's.
  final int maxTextMessageSize;

  /// The largest binary message a session receives, in bytes; as
  /// [maxTextMessageSize].
  final int maxBinaryMessageSize;

  static final _defaultClient = io.HttpClient();
  static final _random = Random.secure();

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
  }) async {
    final handshake = _handshake(url, headers, protocols);
    try {
      return timeout == null
          ? await handshake
          : await handshake.timeout(
              timeout,
              onTimeout: () {
                // Close the socket if the handshake completes late.
                unawaited(
                  handshake.then((s) => s.close(), onError: (Object _) {}),
                );
                throw TimeoutException('handshake', timeout);
              },
            );
    } on TimeoutException catch (error) {
      throw WebSocketException(
        'no handshake within ${timeout!.inMilliseconds} ms',
        url: url,
        cause: error,
        isTimeout: true,
      );
    } on Object catch (error) {
      if (error is WebSocketException) {
        rethrow;
      }
      throw WebSocketException(
        'cannot connect: $error',
        url: url,
        cause: error,
      );
    }
  }

  // The opening handshake of RFC 6455 §4.1, as dart:io's
  // `WebSocket.connect` does it, but keeping the socket, so that the
  // session can bound what waits to be sent and drop the connection.
  Future<IoWebSocketSession> _handshake(
    Uri url,
    HttpHeaders? headers,
    List<String> protocols,
  ) async {
    if (url.scheme != 'ws' && url.scheme != 'wss') {
      throw io.WebSocketException("Unsupported URL scheme '${url.scheme}'");
    }
    final nonce = base64.encode([
      for (var i = 0; i < 16; i++) _random.nextInt(256),
    ]);
    final target = Uri(
      scheme: url.scheme == 'wss' ? 'https' : 'http',
      userInfo: url.userInfo,
      host: url.host,
      port: url.port,
      path: url.path,
      query: url.hasQuery ? url.query : null,
    );
    final request = await (_client ?? _defaultClient).openUrl('GET', target)
      // A redirect would go elsewhere with this handshake's key and
      // headers; browsers do not follow them either.
      ..followRedirects = false;
    if (url.userInfo.isNotEmpty) {
      request.headers.set(
        io.HttpHeaders.authorizationHeader,
        'Basic ${base64.encode(utf8.encode(url.userInfo))}',
      );
    }
    headers?.forEach((name, values) {
      for (final value in values) {
        request.headers.add(name, value);
      }
    });
    request.headers
      ..set(io.HttpHeaders.connectionHeader, 'Upgrade')
      ..set(io.HttpHeaders.upgradeHeader, 'websocket')
      ..set('Sec-WebSocket-Key', nonce)
      ..set(io.HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Sec-WebSocket-Version', '13');
    if (protocols.isNotEmpty) {
      request.headers.set('Sec-WebSocket-Protocol', protocols.join(', '));
    }
    final response = await request.close();
    Never refuse(String message, [int? status]) {
      // Let go of the connection; the answer is not read.
      unawaited(
        response.detachSocket().then(
          (socket) => socket.destroy(),
          onError: (Object _) {},
        ),
      );
      throw io.WebSocketException(message, status);
    }

    final connection = response.headers[io.HttpHeaders.connectionHeader];
    if (response.statusCode != io.HttpStatus.switchingProtocols ||
        connection == null ||
        !connection.any((value) => value.toLowerCase() == 'upgrade') ||
        response.headers[io.HttpHeaders.upgradeHeader]?.firstOrNull
                ?.toLowerCase() !=
            'websocket') {
      refuse(
        "Connection to '$target' was not upgraded to websocket",
        response.statusCode,
      );
    }
    final accept = response.headers['Sec-WebSocket-Accept'];
    if (accept == null || accept.length != 1) {
      refuse("Response did not contain a 'Sec-WebSocket-Accept' header");
    }
    if (accept.single.trim() != webSocketAccept(nonce)) {
      refuse("Bad response 'Sec-WebSocket-Accept' header");
    }
    // RFC 6455 §4.1: a subprotocol or an extension the client did not
    // ask for fails the connection (none is offered here).
    final chosen = response.headers['Sec-WebSocket-Protocol'] ?? const [];
    final String? protocol;
    if (chosen.isEmpty) {
      protocol = null;
    } else if (chosen.length == 1 && protocols.contains(chosen.single.trim())) {
      protocol = chosen.single.trim();
    } else {
      refuse(
        "The server chose the subprotocol '${chosen.join(', ')}', which was "
        'not offered',
      );
    }
    final extensions = response.headers['Sec-WebSocket-Extensions'];
    if (extensions != null && extensions.any((e) => e.trim().isNotEmpty)) {
      refuse(
        "The server chose the extension '${extensions.join(', ')}', which "
        'was not offered',
      );
    }
    final socket = await response.detachSocket();
    return IoWebSocketSession.fromUpgradedSocket(
      socket,
      url,
      serverSide: false,
      protocol: protocol,
      sendBufferSizeLimit: sendBufferSizeLimit,
      sendTimeLimit: sendTimeLimit,
      maxTextMessageSize: maxTextMessageSize,
      maxBinaryMessageSize: maxBinaryMessageSize,
    );
  }
}

/// The `Sec-WebSocket-Accept` value for a `Sec-WebSocket-Key` [key]
/// (RFC 6455 §4.2.2): the base64 SHA-1 of the key and the protocol's GUID.
///
/// The server sends it in its handshake answer, and the client checks it.
String webSocketAccept(String key) => base64.encode(
  _sha1(ascii.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')),
);

/// A [WebSocketSession] over an open `dart:io` `WebSocket`, on either
/// side of the connection.
///
/// [IoWebSocketTransport] returns one for a client connection, and the
/// web starter's server returns one from
/// `ServerHttpRequest.upgradeToWebSocket` for an accepted connection;
/// both make it with [IoWebSocketSession.fromUpgradedSocket]. Create one
/// yourself only to wrap a `WebSocket` you opened with `dart:io`
/// directly.
///
/// [closeStatus] gives the code the other side sent; if this side closed
/// first and no answer has arrived yet, or the connection ended without
/// one, it gives the status passed to [close]. A connection that breaks
/// (reset by the other side, a write that fails) ends [messages], and
/// [closeStatus] is then [CloseStatus.noCloseFrame] (1006) with the error
/// as the reason (`Connection reset by peer`), as Tomcat reports it,
/// whether a read or a write met the error first: when the input ends
/// first (as it often does over TLS) while something is still being
/// written, [messages] ends once the write has ended too, or a second
/// later. A message larger than the
/// session's limits (8 KB by default) is not read: the session closes
/// with 1009 (see [IoWebSocketSession.fromUpgradedSocket]).
///
/// [sendMessage] does not wait: the message waits in memory until the
/// network takes it; [flush] waits for that. When the other side reads
/// nothing, that memory would grow without end, so a session made by
/// [IoWebSocketSession.fromUpgradedSocket] gives up on it, as Spring's
/// `ConcurrentWebSocketSessionDecorator` does: when more than
/// `sendBufferSizeLimit` bytes wait (512 KB by default), or what was sent
/// has not all left within `sendTimeLimit` (10 seconds by default), the
/// connection is dropped without a closing handshake (a close frame
/// could not get through either), [closeStatus] becomes
/// [CloseStatus.sessionNotReliable] (4500, with the reason), and
/// [messages] ends. The connection is still read while something waits,
/// so two sides that both send more than the network holds do not wait
/// for each other; the pongs that answer pings wait with the messages, so
/// a peer that sends pings and reads nothing reaches the limit too.
final class IoWebSocketSession implements WebSocketSession {
  /// A session over the open `socket`, whose address is [uri]. It does
  /// not bound what waits to be sent (`dart:io` keeps it all), nor the
  /// size of the messages it receives, and it has `dart:io`'s fault with
  /// a ping or pong between the fragments of a message: the fragments
  /// before it are lost, and the pong carries them (see
  /// [IoWebSocketSession.fromUpgradedSocket]).
  ///
  /// The session listens to `socket` at once (reading nothing until
  /// [messages] is listened to), so do not listen to `socket` yourself.
  IoWebSocketSession(io.WebSocket socket, this.uri)
    : _socket = socket,
      _guard = null {
    _receive();
  }

  IoWebSocketSession._guarded(this._socket, this.uri, _GuardedSocket guard)
    : _guard = guard {
    guard
      ..onLimitExceeded = (reason) {
        _local = CloseStatus.sessionNotReliable.withReason(reason);
      }
      ..onBroken = (error) {
        _local ??= CloseStatus.noCloseFrame.withReason(_describe(error));
      }
      ..onMessageTooBig = () {
        if (isOpen) {
          unawaited(
            close(
              CloseStatus.tooBigToProcess.withReason('Message too big'),
            ).catchError((Object _) {}),
          );
        }
      };
    _receive();
  }

  /// A session over [socket], a connection on which the WebSocket
  /// handshake has just been done (`HttpResponse.detachSocket` on a
  /// server, `HttpClientResponse.detachSocket` on a client); [uri] is its
  /// address. The handshake answer may still be on its way in [socket]
  /// (written with `add`): what the session sends follows it.
  ///
  /// [serverSide] tells which side this is (a server does not mask its
  /// frames), [protocol] is the subprotocol agreed on. Past
  /// [sendBufferSizeLimit] bytes waiting to be sent (`-1`: no limit), or
  /// when what was sent has not left within [sendTimeLimit] (`null`: no
  /// limit), the connection is dropped and [closeStatus] is
  /// [CloseStatus.sessionNotReliable]. A text message larger than
  /// [maxTextMessageSize] bytes (UTF-8), or a binary one larger than
  /// [maxBinaryMessageSize] bytes (`-1`: no limit), is dropped unread and
  /// the session is closed with 1009 (message too big). The sizes are
  /// counted from the frames before `dart:io` assembles the message, so
  /// a message in many small frames is stopped as early as one big frame.
  /// Until its final fragment, a message takes the memory of its payload,
  /// however many fragments (empty ones too) it comes in.
  ///
  /// A control frame between the fragments of a message (RFC 6455 §5.4)
  /// is taken at once: a ping is answered with its own payload, and a
  /// close ends the session with its code, the unfinished message
  /// dropped; the message itself arrives whole. (`dart:io`'s own
  /// `WebSocket` reads the control frame into the message's buffer: the
  /// message loses the fragments before it, and the pong carries them,
  /// more than the 125 bytes a control frame may have.)
  factory IoWebSocketSession.fromUpgradedSocket(
    io.Socket socket,
    Uri uri, {
    required bool serverSide,
    String? protocol,
    int sendBufferSizeLimit = defaultSendBufferSizeLimit,
    Duration? sendTimeLimit = defaultSendTimeLimit,
    int maxTextMessageSize = defaultMaxMessageSize,
    int maxBinaryMessageSize = defaultMaxMessageSize,
  }) {
    final guard = _GuardedSocket(
      socket,
      serverSide: serverSide,
      maxText: maxTextMessageSize,
      maxBinary: maxBinaryMessageSize,
      sendBufferSizeLimit: sendBufferSizeLimit,
      sendTimeLimit: sendTimeLimit,
    );
    return IoWebSocketSession._guarded(
      io.WebSocket.fromUpgradedSocket(
        guard,
        protocol: protocol,
        serverSide: serverSide,
      ),
      uri,
      guard,
    );
  }

  /// The most bytes a session keeps waiting to be sent before it drops
  /// the connection: 512 KB, Spring's default `sendBufferSizeLimit`
  /// (`WebSocketTransportRegistration`).
  static const int defaultSendBufferSizeLimit = 512 * 1024;

  /// How long what a session sent may take to leave before it drops the
  /// connection: 10 seconds, Spring's default `sendTimeLimit`.
  static const defaultSendTimeLimit = Duration(seconds: 10);

  /// The largest message a session receives, text or binary: 8 KB,
  /// Tomcat's default `maxTextMessageBufferSize` and
  /// `maxBinaryMessageBufferSize`, on its server and its client.
  static const int defaultMaxMessageSize = 8 * 1024;

  final io.WebSocket _socket;
  final _GuardedSocket? _guard;

  @override
  final Uri uri;

  /// The incoming messages. The session listens to the `dart:io` socket
  /// from the start, paused until this stream is listened to: the network
  /// is not read before, and `dart:io`'s `close` never drains the socket
  /// itself (it does so for a socket nobody listens to, and a later
  /// listen then fails). So a session closed before anyone listened still
  /// gives a stream that ends, once the close is done; the messages that
  /// arrive after that [close] while nobody listens are dropped (nobody
  /// could answer them any more).
  @override
  Stream<Object> get messages => _incoming.stream;

  final _incoming = StreamController<Object>(sync: true);
  late final StreamSubscription<Object?> _source;
  // Whether the pause the session starts with was released.
  var _reading = false;
  // Whether close() came before anyone listened to [messages].
  var _closedUnheard = false;

  void _receive() {
    final source = _source = _socket.listen(
      _received,
      onError: _receivedError,
      onDone: _inputEnded,
    )..pause();
    _incoming
      ..onListen = _read
      ..onPause = source.pause
      ..onResume = source.resume
      ..onCancel = source.cancel;
  }

  void _read() {
    if (!_reading) {
      _reading = true;
      _source.resume();
    }
  }

  void _received(Object? message) {
    // What dart:io had already read when this side dropped the
    // connection (4500) is not handed on: no answer could go out.
    if ((_guard?.aborted ?? false) ||
        (_closedUnheard && !_incoming.hasListener)) {
      return;
    }
    _incoming.add(switch (message) {
      final String text => text,
      final Uint8List bytes => bytes,
      final List<int> bytes => Uint8List.fromList(bytes),
      _ => '$message',
    });
  }

  void _receivedError(Object error, StackTrace stackTrace) =>
      _incoming.addError(
        error is WebSocketException
            ? error
            : WebSocketException(
                'connection broke: $error',
                url: uri,
                cause: error,
              ),
        stackTrace,
      );

  // The input has ended. Over TLS it often ends cleanly, without a close
  // frame (1006), before the write that the other side's reset makes fail
  // reports the error: [messages] ends once the output has ended too (or
  // after [_outputGrace]), so that [closeStatus] has the reason by then.
  void _inputEnded() {
    final guard = _guard;
    if (guard != null &&
        _socket.closeCode == CloseStatus.noCloseFrame.code &&
        !guard.outputEnded) {
      unawaited(
        guard.outputEnd
            .timeout(_outputGrace, onTimeout: () {})
            .whenComplete(_incoming.close),
      );
    } else {
      unawaited(_incoming.close());
    }
  }

  // How long [messages] waits for the output's end after the input ended
  // without a close frame.
  static const _outputGrace = Duration(seconds: 1);

  @override
  String? get acceptedProtocol => _socket.protocol;

  // dart:io's `readyState` stays open after `close` until the other side
  // answers (up to 5 seconds), and after a protocol error.
  @override
  bool get isOpen =>
      _local == null &&
      _socket.readyState == io.WebSocket.open &&
      _socket.closeCode == null &&
      !(_guard?.dropped ?? false);

  /// Completes when the connection has closed, whichever side closed it,
  /// or was dropped.
  Future<void> get done =>
      _guard?.closed ?? _socket.done.then((_) {}, onError: (Object _) {});

  @override
  void sendMessage(Object message) {
    if (!isOpen) {
      throw WebSocketException('the connection is closed', url: uri);
    }
    if (message is! String && message is! List<int>) {
      throw ArgumentError.value(message, 'message', 'a String or a List<int>');
    }
    try {
      _socket.add(message);
    } on StateError catch (error) {
      // A `WebSocket` passed to the constructor and closed directly.
      throw WebSocketException(
        'the connection is closed',
        url: uri,
        cause: error,
      );
    }
  }

  /// Completes once everything sent so far has left this process: handed
  /// to the network, nothing of it waiting in memory any more. So a loop
  /// that awaits it after each [sendMessage] sends as fast as the other
  /// side reads, and never reaches the session's `sendBufferSizeLimit`.
  ///
  /// Fails with a [WebSocketException] when the connection closes, breaks
  /// or is dropped first (past `sendTimeLimit`, for example). On a session
  /// made with the [IoWebSocketSession.new] constructor it completes at
  /// once: `dart:io` does not tell.
  ///
  /// Spring (Java): `sendMessage` itself blocks until the message is sent.
  Future<void> flush() async {
    final guard = _guard;
    if (guard == null) {
      return;
    }
    try {
      await guard.flushed();
    } on StateError catch (error) {
      throw WebSocketException(error.message, url: uri, cause: error);
    }
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) {
    _local ??= status;
    if (!_incoming.hasListener) {
      // Nobody reads yet: read on, so that the other side's answer (its
      // close frame) is seen and the close completes, as dart:io's drain
      // would; a later listener gets the end of the stream.
      _closedUnheard = true;
      _read();
    }
    if (_guard?.dropped ?? false) {
      return Future.value();
    }
    return _socket.close(status.code, status.reason);
  }

  // What this side closed with (the other side's answer may come later),
  // or why the connection was dropped.
  CloseStatus? _local;

  @override
  CloseStatus? get closeStatus {
    final guard = _guard;
    if (guard != null && guard.aborted) {
      return _local;
    }
    final received = switch (_socket.closeCode) {
      final code? => CloseStatus(code, switch (_socket.closeReason) {
        final reason? when reason.isNotEmpty => reason,
        _ => null,
      }),
      null => null,
    };
    // The input ended without a close frame (1006, no reason) after this
    // side closed, or after the output met the error that broke the
    // connection: _local has the status passed to close, or the error. (A
    // close frame that arrived is the other side's answer: it wins.)
    if (received != null &&
        received.code == CloseStatus.noCloseFrame.code &&
        _local != null) {
      return _local;
    }
    // A broken connection: dart:io reports 1002 when the input side saw
    // the error, 1006 when the output side saw it first (the guard then
    // destroys the socket, and the input just ends without a close
    // frame), 1005 for a close frame without a code whose answer failed,
    // or nothing yet while the application holds the messages back.
    // dart:io gives no reason then; _local has the error (or the status
    // this side closed with first).
    if (guard != null &&
        guard.broken != null &&
        (received == null ||
            received.code == CloseStatus.protocolError.code ||
            received.code == CloseStatus.noStatusCode.code ||
            received.code == CloseStatus.noCloseFrame.code)) {
      return _local;
    }
    return received ?? _local;
  }

  static String _describe(Object error) => switch (error) {
    io.SocketException(:final osError?) => osError.message,
    io.SocketException(:final message) => message,
    _ => '$error',
  };
}

/// What [session] holds of an incoming message whose final fragment has
/// not arrived yet: the bytes it keeps, and in how many buffers. `(0, 0)`
/// when nothing is held, and for a session made with the
/// [IoWebSocketSession.new] constructor.
///
/// For the tests of this package: `package:spring_web_dart/io.dart` hides
/// it.
({int bytes, int buffers}) heldIncomingMessage(IoWebSocketSession session) =>
    session._guard?._incoming.held ?? (bytes: 0, buffers: 0);

/// The socket of one WebSocket connection, between `dart:io`'s
/// `WebSocket` and the network.
///
/// `dart:io` keeps everything a `WebSocket` sends (messages, pongs) in
/// memory while the network does not take it. Here the outgoing bytes
/// are taken at once and queued, so they can be counted: past
/// [sendBufferSizeLimit] queued bytes, or when the queue has not emptied
/// within [sendTimeLimit], the connection is destroyed. The incoming side
/// is never paused for the outgoing one: two peers that both wait for
/// their output to drain before they read would wait for ever. The
/// incoming frames are counted and put in order on the way
/// ([_IncomingFrames]).
final class _GuardedSocket extends Stream<Uint8List> implements io.Socket {
  _GuardedSocket(
    this._socket, {
    required bool serverSide,
    required int maxText,
    required int maxBinary,
    required this.sendBufferSizeLimit,
    required this.sendTimeLimit,
  }) : _incoming = _IncomingFrames(
         maxText,
         maxBinary,
         serverSide: serverSide,
       );

  final io.Socket _socket;
  final _IncomingFrames _incoming;
  final int sendBufferSizeLimit;
  final Duration? sendTimeLimit;

  /// Called once, with the reason, when a limit is passed and the
  /// connection is dropped.
  void Function(String reason)? onLimitExceeded;

  /// Called once, with the error, when the connection breaks.
  void Function(Object error)? onBroken;

  /// Called once when a message larger than its limit arrives (it is
  /// dropped, and so is every later data frame).
  void Function()? get onMessageTooBig => _incoming.onTooBig;
  set onMessageTooBig(void Function()? callback) =>
      _incoming.onTooBig = callback;

  /// Whether a limit was passed and the connection dropped.
  bool aborted = false;

  /// The error that broke the connection (a reset, a write that failed),
  /// or `null`.
  Object? broken;

  /// Whether the connection was dropped or broke: nothing can be sent.
  bool get dropped => aborted || broken != null;

  final _closed = Completer<void>();

  /// Completes when the connection is closed or dropped.
  Future<void> get closed => _closed.future;

  final _outputEnd = Completer<void>();

  /// Completes when the output has ended: all written, failed (the
  /// connection broke) or dropped.
  Future<void> get outputEnd => _outputEnd.future;

  /// Whether [outputEnd] has completed.
  bool get outputEnded => _outputEnd.isCompleted;

  void _endOutput() {
    if (!_outputEnd.isCompleted) {
      _outputEnd.complete();
    }
  }

  // The outgoing side: what goes to the network, what waits, since when,
  // and who waits for it to empty.
  StreamController<List<int>>? _out;
  final _queue = Queue<List<int>>();
  var _queued = 0;
  Timer? _sendTimer;
  var _sendingSince = DateTime.now();
  var _drainScheduled = false;
  var _upstreamDone = false;
  Completer<void>? _outputDone;
  var _outputFinished = false;
  final _flushes = <Completer<void>>[];

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _socket
        .transform(_incoming)
        .listen(
          onData,
          // Every error here comes from the network (a reset, TLS): the
          // connection is gone. dart:io then closes the session.
          onError: (Object error, StackTrace stackTrace) {
            _broke(error);
            switch (onError) {
              case final void Function(Object, StackTrace) handler:
                handler(error, stackTrace);
              case final void Function(Object) handler:
                handler(error);
            }
          },
          onDone: () {
            _markClosed();
            onDone?.call();
          },
          cancelOnError: cancelOnError,
        );
  }

  // dart:io binds one stream of frames for the life of the connection.
  // The socket listens to [_out] only once what was added to it before is
  // written (a handshake answer written by hand, for example); until then
  // what is sent waits in the queue, on the clock.
  @override
  Future<void> addStream(Stream<List<int>> stream) {
    final done = _outputDone = Completer<void>();
    final out = _out = StreamController<List<int>>(
      sync: true,
      onListen: _scheduleDrain,
      onPause: _backedUp,
      onResume: _scheduleDrain,
    );
    unawaited(
      _socket
          .addStream(out.stream)
          .then(
            (_) => _finishOutput(),
            onError: (Object error, StackTrace stackTrace) {
              // The other side went away (a reset, a broken pipe).
              _broke(error);
              _finishOutput(error, stackTrace);
            },
          ),
    );
    stream.listen(
      _send,
      onError: (Object error, StackTrace stackTrace) {
        if (!dropped && !out.isClosed) {
          out.addError(error, stackTrace);
        }
      },
      onDone: () {
        _upstreamDone = true;
        _closeIfDrained();
      },
    );
    return done.future;
  }

  void _send(List<int> bytes) {
    final out = _out!;
    if (dropped || _outputFinished || out.isClosed) {
      return; // dropped: nobody will read it
    }
    if (_queue.isEmpty && !out.isPaused) {
      out.add(bytes);
      return;
    }
    _queue.add(bytes);
    _queued += bytes.length;
    if (sendBufferSizeLimit >= 0 && _queued > sendBufferSizeLimit) {
      _exceeded(
        'Buffer size $_queued bytes exceeds the allowed limit '
        '$sendBufferSizeLimit',
      );
    } else {
      _backedUp(); // already running, unless the socket has not listened
    }
  }

  // The network takes no more for now, or the socket does not listen
  // yet: start the clock. The input goes on being read (see the class
  // comment).
  void _backedUp() {
    if (dropped || _outputFinished) {
      return;
    }
    final limit = sendTimeLimit;
    if (limit != null && _sendTimer == null) {
      _sendingSince = DateTime.now();
      _sendTimer = Timer(
        limit,
        () => _exceeded(
          'Send time ${DateTime.now().difference(_sendingSince).inMilliseconds}'
          ' (ms) exceeded the allowed limit ${limit.inMilliseconds}',
        ),
      );
    }
  }

  // Called from inside the network's resume: the queue is passed on from
  // a microtask, so each add reaches the network at once and the next
  // pause stops the loop.
  void _scheduleDrain() {
    if (_drainScheduled) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _drainScheduled = false;
    final out = _out;
    if (out == null || dropped || out.isClosed) {
      return;
    }
    while (_queue.isNotEmpty && !out.isPaused) {
      final bytes = _queue.removeFirst();
      _queued -= bytes.length;
      out.add(bytes);
    }
    if (_queue.isEmpty && !out.isPaused) {
      _sendTimer?.cancel();
      _sendTimer = null;
      _settleFlushes();
      _closeIfDrained();
    }
  }

  /// Completes when nothing waits to be sent; fails with a [StateError]
  /// when the connection is closed, breaks or is dropped first.
  Future<void> flushed() {
    final out = _out;
    if (_outputFinished || dropped) {
      return Future.error(StateError(_why()));
    }
    if (out == null || (_queue.isEmpty && !out.isPaused)) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _flushes.add(waiter);
    return waiter.future;
  }

  String _why() => switch ((aborted, broken)) {
    (true, _) => 'the connection was dropped',
    (_, final error?) => 'the connection broke: $error',
    _ => 'the connection is closed',
  };

  // Completes the waiting flushes: with an error when the connection
  // ended (closed, broken or dropped) before they were written.
  void _settleFlushes({bool failed = false}) {
    if (_flushes.isEmpty) {
      return;
    }
    final waiters = [..._flushes];
    _flushes.clear();
    for (final waiter in waiters) {
      if (failed) {
        waiter.completeError(StateError(_why()));
      } else {
        waiter.complete();
      }
    }
  }

  void _closeIfDrained() {
    final out = _out;
    if (dropped) {
      _finishOutput();
    } else if (_upstreamDone &&
        _queue.isEmpty &&
        out != null &&
        !out.isClosed) {
      unawaited(out.close());
    }
  }

  void _exceeded(String reason) {
    if (dropped) {
      return;
    }
    aborted = true;
    _sendTimer?.cancel();
    _sendTimer = null;
    _queue.clear();
    _queued = 0;
    onLimitExceeded?.call(reason);
    // The input ends too, which reaches dart:io: it closes the session.
    _socket.destroy();
    _finishOutput();
    _markClosed();
  }

  // The connection broke: nothing more can be written, and the input is
  // ended (destroyed), so dart:io closes the session even when the
  // output failed while the other side had stopped reading.
  void _broke(Object error) {
    if (dropped) {
      return;
    }
    broken = error;
    onBroken?.call(error);
    _socket.destroy();
    _markClosed();
    _endOutput();
  }

  // The output has ended: written, failed (the peer went away) or
  // dropped. Nothing waits any more.
  void _finishOutput([Object? error, StackTrace? stackTrace]) {
    _outputFinished = true;
    _sendTimer?.cancel();
    _sendTimer = null;
    final failed = dropped || error != null || _queue.isNotEmpty;
    _queue.clear();
    _queued = 0;
    _settleFlushes(failed: failed);
    _endOutput();
    final done = _outputDone;
    if (done == null || done.isCompleted) {
      return;
    }
    if (error != null && !aborted) {
      done.completeError(error, stackTrace);
    } else {
      done.complete();
    }
  }

  void _markClosed() {
    if (!_closed.isCompleted) {
      _closed.complete();
    }
  }

  @override
  Future<void> close() async {
    _markClosed();
    if (dropped) {
      return;
    }
    await _socket.close();
  }

  @override
  void destroy() {
    _markClosed();
    _socket.destroy();
  }

  @override
  Future<void> get done => _socket.done;

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding value) => _socket.encoding = value;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> flush() => _socket.flush();

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);

  @override
  io.InternetAddress get address => _socket.address;

  @override
  io.InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get port => _socket.port;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool setOption(io.SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  Uint8List getRawOption(io.RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  void setRawOption(io.RawSocketOption option) => _socket.setRawOption(option);
}

// Passes the other side's frames on to dart:io, with two corrections.
//
// The payload of each data message is counted. A frame that would make
// its message larger than the limit is dropped, header and payload, with
// what was held of the message (below), and so is every later data
// frame; control frames (close, ping, pong) still pass, so the closing
// handshake ends.
//
// dart:io reads a control frame's payload into the same buffer as the
// fragments of the message it interrupts (RFC 6455 §5.4 allows control
// frames there): the message would lose the fragments before it, with no
// error, and the pong would carry them (more than the 125 bytes a
// control frame may have). So an unfinished message is held here, and a
// control frame between its fragments passes at once, while dart:io's
// buffer is empty: a ping is answered at once with its own payload, and
// a close ends the connection at once, the unfinished message dropped.
// Only the message's payload is held, unmasked, in a few buffers
// ([_HeldMessage]), not its fragments, whose headers are dropped: what is
// held is the payload, which dart:io would hold anyway (within the size
// limit, when there is one), and at most a buffer more, however many
// fragments, empty or tiny, it came in. With the final fragment, dart:io
// gets two frames, whatever their number: the payload held as one frame
// that starts the message, then the final fragment as it came. A message
// in one frame passes as it came.
//
// A frame dart:io refuses (reserved bits or opcodes, masked the wrong
// way, a data frame out of turn, a control frame fragmented or longer
// than 125 bytes) passes at once, after what was held, and so does all
// that follows: dart:io fails the connection as it would without this.
// No extension is ever negotiated (`WebSocket.fromUpgradedSocket` gets
// no permessage-deflate, and the client refuses a handshake answer that
// picks one), so a reserved bit is refused, payload sizes are message
// sizes, and the frame rebuilt from held fragments has no reserved bits
// to carry over.
final class _IncomingFrames
    extends StreamTransformerBase<Uint8List, Uint8List> {
  _IncomingFrames(this.maxText, this.maxBinary, {required this.serverSide});

  final int maxText;
  final int maxBinary;
  // A client masks its frames, a server does not.
  final bool serverSide;
  void Function()? onTooBig;

  // The current frame's header so far: 2 bytes, the extended length (2
  // or 8 bytes), the mask key (4 bytes).
  final _header = Uint8List(14);
  var _headerLength = 0;
  var _remaining = 0; // payload bytes left in the current frame
  _Payload _payload = _Payload.pass; // what becomes of them
  final _mask = Uint8List(4); // the mask key of a held frame
  var _masked = false;
  var _maskIndex = 0; // payload bytes of the held frame so far
  var _messageType = 0; // 1 text, 2 binary, 0 none
  var _messageSize = 0;
  var _tooBig = false;
  var _refused = false; // dart:io fails the connection: the rest passes
  final _held = _HeldMessage(); // the unfinished message

  ({int bytes, int buffers}) get held =>
      (bytes: _held.capacity, buffers: _held.buffers);

  @override
  Stream<Uint8List> bind(Stream<Uint8List> stream) => stream.transform(
    StreamTransformer<Uint8List, Uint8List>.fromHandlers(handleData: _data),
  );

  void _data(Uint8List chunk, EventSink<Uint8List> sink) {
    var offset = 0;
    while (offset < chunk.length) {
      if (_refused) {
        sink.add(_slice(chunk, offset, chunk.length));
        return;
      }
      if (_remaining > 0) {
        final take = min(chunk.length - offset, _remaining);
        switch (_payload) {
          case _Payload.pass:
            sink.add(_slice(chunk, offset, offset + take));
          case _Payload.hold:
            _held.add(
              chunk,
              offset,
              offset + take,
              _masked ? _mask : null,
              _maskIndex,
            );
            _maskIndex += take;
          case _Payload.drop:
            break;
        }
        offset += take;
        _remaining -= take;
        continue;
      }
      // A frame header: 2 bytes, the extended length, the mask key.
      _header[_headerLength++] = chunk[offset++];
      if (_headerLength < 2) {
        continue;
      }
      final short = _header[1] & 0x7F;
      final extended = short == 126 ? 2 : (short == 127 ? 8 : 0);
      final masked = (_header[1] & 0x80) != 0;
      final length = 2 + extended + (masked ? 4 : 0);
      if (_headerLength < length) {
        continue;
      }
      _headerLength = 0;
      var payload = short;
      if (extended > 0) {
        payload = 0;
        for (var i = 2; i < 2 + extended; i++) {
          // Lengths past 2^63 come out negative: too big, or refused.
          payload = payload * 256 + _header[i];
        }
      }
      _remaining = payload;
      _payload = _accept(_header[0], _header[1], payload, sink);
      switch (_payload) {
        case _Payload.pass:
          sink.add(_header.sublist(0, length));
        case _Payload.hold:
          // The header is not kept: its payload joins the held message.
          _masked = masked;
          if (masked) {
            _mask.setRange(0, 4, _header, length - 4);
          }
          _maskIndex = 0;
        case _Payload.drop:
          break;
      }
    }
  }

  // A copy, not a view, unless it is the whole chunk: dart:io unmasks in
  // place with aligned Int32x4 views, which needs a list that starts its
  // buffer.
  static Uint8List _slice(Uint8List chunk, int start, int end) =>
      start == 0 && end == chunk.length && chunk.offsetInBytes == 0
      ? chunk
      : chunk.sublist(start, end);

  // What becomes of a frame whose header starts with [first] and
  // [second], with [payload] bytes.
  _Payload _accept(
    int first,
    int second,
    int payload,
    EventSink<Uint8List> sink,
  ) {
    final opcode = first & 0x0F;
    final fin = (first & 0x80) != 0;
    final malformed =
        (first & 0x70) != 0 || // reserved bits: no extension
        ((second & 0x80) != 0) != serverSide;
    if (opcode >= 8) {
      if (malformed || opcode > 10 || !fin || (second & 0x7F) > 125) {
        return _refuse(sink);
      }
      if (opcode == 8) {
        _held.clear(); // the message never ends
        _messageType = 0;
      }
      return _Payload.pass;
    }
    if (_tooBig) {
      return _Payload.drop;
    }
    final outOfTurn = opcode != 0 && _messageType != 0;
    if (opcode == 1 || opcode == 2) {
      _messageType = opcode;
      _messageSize = 0;
    }
    final limit = switch (_messageType) {
      1 => maxText,
      2 => maxBinary,
      _ => -1, // a continuation of nothing: dart:io refuses it
    };
    final size = _messageSize + payload;
    if (limit >= 0 && (size > limit || size < 0)) {
      _tooBig = true;
      _held.clear();
      onTooBig?.call();
      return _Payload.drop;
    }
    if (malformed ||
        outOfTurn ||
        opcode > 2 ||
        _messageType == 0 ||
        payload < 0) {
      return _refuse(sink);
    }
    if (!fin) {
      _messageSize = size;
      if (opcode != 0) {
        _held.start(first);
      }
      return _Payload.hold;
    }
    _release(sink);
    _messageType = 0;
    _messageSize = 0;
    return _Payload.pass;
  }

  _Payload _refuse(EventSink<Uint8List> sink) {
    _release(sink);
    _refused = true;
    return _Payload.pass;
  }

  // dart:io's server takes only masked frames, its client only unmasked
  // ones.
  void _release(EventSink<Uint8List> sink) =>
      _held.release(sink, masked: serverSide);
}

// What becomes of a frame's payload.
enum _Payload { pass, hold, drop }

// The payload of an unfinished message, unmasked, in buffers of 256
// bytes to 64 KB, each as large as all those before it (or as the bytes
// added, if more): the memory it takes is its payload and up to a buffer
// more, whatever the number of fragments it came in.
final class _HeldMessage {
  static const int _smallest = 256;
  static const int _largest = 64 * 1024;

  var _first = 0; // the first byte of the message's first frame; 0: none
  final _buffers = <Uint8List>[];
  var _filled = 0; // bytes written in the last buffer
  var _length = 0;

  /// The bytes of the buffers.
  int capacity = 0;

  int get buffers => _buffers.length;

  /// A message starts with a frame (not final) whose first byte is
  /// [first].
  void start(int first) {
    assert((first & 0xF0) == 0, 'final, or with reserved bits (refused)');
    _first = first;
  }

  /// Adds the bytes of [chunk] from [start] to [end], the payload of a
  /// frame from its byte [maskIndex] on, unmasked with [mask] (`null`:
  /// not masked).
  void add(
    Uint8List chunk,
    int start,
    int end,
    Uint8List? mask,
    int maskIndex,
  ) {
    assert(_first != 0, 'no message started');
    var from = start;
    var index = maskIndex;
    while (from < end) {
      if (_buffers.isEmpty || _filled == _buffers.last.length) {
        final size = max(end - from, _length).clamp(_smallest, _largest);
        _buffers.add(Uint8List(size));
        capacity += size;
        _filled = 0;
      }
      final buffer = _buffers.last;
      final count = min(end - from, buffer.length - _filled);
      buffer.setRange(_filled, _filled + count, chunk, from);
      if (mask != null) {
        _unmask(buffer, _filled, count, mask, index);
      }
      _filled += count;
      _length += count;
      from += count;
      index += count;
    }
  }

  /// Passes what is held to [sink] as one frame that starts the message,
  /// not final (the final fragment follows as it came), [masked] with
  /// the key 0, 0, 0, 0; then holds nothing.
  void release(EventSink<Uint8List> sink, {required bool masked}) {
    if (_first == 0) {
      return;
    }
    final length = _length;
    final extended = length < 126 ? 0 : (length < 65536 ? 2 : 8);
    // A new list's bytes are 0: so is the mask key.
    final header = Uint8List(2 + extended + (masked ? 4 : 0))
      ..[0] = _first
      ..[1] =
          (masked ? 0x80 : 0) |
          switch (extended) {
            0 => length,
            2 => 126,
            _ => 127,
          };
    for (var i = 0; i < extended; i++) {
      header[2 + i] = (length >> (8 * (extended - 1 - i))) & 0xFF;
    }
    sink.add(header);
    // Each starts its own buffer, as dart:io's unmasking needs.
    for (final buffer in _buffers) {
      sink.add(
        identical(buffer, _buffers.last) && _filled < buffer.length
            ? Uint8List.view(buffer.buffer, 0, _filled)
            : buffer,
      );
    }
    clear();
  }

  void clear() {
    _first = 0;
    _buffers.clear();
    _filled = 0;
    _length = 0;
    capacity = 0;
  }

  // XORs [count] bytes of [buffer] from [start] with [mask], whose byte
  // [index] % 4 goes with the first; 16 bytes at a time where aligned,
  // as dart:io does (on a little-endian machine, as all Dart VMs are).
  static void _unmask(
    Uint8List buffer,
    int start,
    int count,
    Uint8List mask,
    int index,
  ) {
    if ((mask[0] | mask[1] | mask[2] | mask[3]) == 0) {
      return;
    }
    final end = start + count;
    var i = start;
    var m = index;
    while (i < end && (i & 15) != 0) {
      buffer[i++] ^= mask[m++ & 3];
    }
    final blocks = (end - i) >> 4;
    if (blocks > 0) {
      var word = 0;
      for (var k = 3; k >= 0; k--) {
        word = (word << 8) | mask[(m + k) & 3];
      }
      final block = Int32x4(word, word, word, word);
      final view = Int32x4List.view(
        buffer.buffer,
        buffer.offsetInBytes + i,
        blocks,
      );
      for (var k = 0; k < blocks; k++) {
        view[k] ^= block;
      }
      i += blocks << 4; // m moves on by a multiple of 4: the same key byte
    }
    while (i < end) {
      buffer[i++] ^= mask[m++ & 3];
    }
  }
}

/// The SHA-1 digest of [message] (FIPS 180-4), for the WebSocket
/// handshake only (SHA-1 is not fit for anything secret).
Uint8List _sha1(List<int> message) {
  const mask = 0xFFFFFFFF;
  int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & mask;
  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;
  final padded = BytesBuilder()
    ..add(message)
    ..addByte(0x80);
  while (padded.length % 64 != 56) {
    padded.addByte(0);
  }
  final bits = message.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.addByte((bits >> shift) & 0xFF);
  }
  final bytes = padded.takeBytes();
  final data = ByteData.sublistView(bytes);
  final w = List<int>.filled(80, 0);
  for (var chunk = 0; chunk < bytes.length; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = data.getUint32(chunk + i * 4);
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    for (var i = 0; i < 80; i++) {
      final int f;
      final int k;
      if (i < 20) {
        f = (b & c) | ((~b & mask) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[i]) & mask;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & mask;
    h1 = (h1 + b) & mask;
    h2 = (h2 + c) & mask;
    h3 = (h3 + d) & mask;
    h4 = (h4 + e) & mask;
  }
  final out = ByteData(20)
    ..setUint32(0, h0)
    ..setUint32(4, h1)
    ..setUint32(8, h2)
    ..setUint32(12, h3)
    ..setUint32(16, h4);
  return out.buffer.asUint8List();
}
