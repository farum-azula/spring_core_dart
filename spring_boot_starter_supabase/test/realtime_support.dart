// What the Realtime tests share: a Realtime server played on a mock
// connection, in the first wire format (JSON objects), and a
// SupabaseRealtime over it.
//
// It names the libraries of the starter one by one, and gives the
// Realtime ones to the tests, so they read the same before and after
// the starter's main library exports them.
import 'dart:async';

import 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';
import 'package:spring_boot_starter_supabase/src/realtime/supabase_realtime.dart';
import 'package:spring_boot_starter_supabase/src/supabase_credentials.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support.dart';

export 'package:spring_boot_starter_supabase/src/realtime/realtime_auto_configuration.dart';
export 'package:spring_boot_starter_supabase/src/realtime/realtime_channel.dart';
export 'package:spring_boot_starter_supabase/src/realtime/realtime_model.dart';
export 'package:spring_boot_starter_supabase/src/realtime/realtime_presence_state.dart';
export 'package:spring_boot_starter_supabase/src/realtime/supabase_realtime.dart';

/// The address every connection of the tests goes to, before its query.
const realtimeAddress = 'wss://abcd.supabase.co/realtime/v1/websocket';

/// Lets the microtasks and timers that are due run.
Future<void> pump([int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A login the test changes: [signIn] and [signOut] tell the listeners.
final class TestLogin implements LoginSession {
  final _changes = StreamController<Authentication?>.broadcast();

  /// The access token of the user who is signed in; null for nobody.
  String? token;

  /// How often the token was asked.
  int asked = 0;

  /// Signs a user in with [token].
  void signIn(String token, {String name = 'ann'}) {
    this.token = token;
    _name = name;
    _changes.add(authentication);
  }

  /// Signs the user out.
  void signOut() {
    token = null;
    _changes.add(null);
  }

  String _name = 'ann';

  @override
  Authentication? get authentication =>
      token == null ? null : TestingAuthenticationToken(_name, null);

  @override
  bool get isLoggedIn => token != null;

  @override
  Stream<Authentication?> get authenticationChanges => _changes.stream;

  @override
  Future<String?> accessToken() async {
    asked++;
    return token;
  }

  @override
  Future<Authentication?> restore() async => authentication;

  @override
  Future<void> logout() async => signOut();
}

/// Realtime of [projectUrl] over [sockets]: nobody signed in unless
/// [login] is given; quick reconnections and replies, no heartbeat unless
/// [heartbeat] is given. [settings] are the application's
/// `spring.websocket.client.config.*`.
SupabaseRealtime realtimeOf(
  MockWebSocketTransport sockets, {
  TestLogin? login,
  SupabaseCredentials? credentials,
  Duration heartbeat = Duration.zero,
  Duration timeout = const Duration(milliseconds: 150),
  Map<String, WebSocketClientSettings>? settings,
}) {
  final all = properties(serviceRole: true)
    ..realtime.heartbeatInterval = heartbeat
    ..realtime.timeout = timeout;
  final as =
      credentials ??
      DefaultSupabaseCredentials(
        properties: all,
        session: () => login,
        authentication: () => null,
      );
  return SupabaseRealtime(
    http: http(MockHttpTransport(), properties_: all, credentials: as),
    credentials: as,
    sockets: PhoenixSocketFactory(
      environment: StandardEnvironment(systemEnvironment: const {}),
      properties: WebSocketProperties()
        ..config =
            settings ??
            {
              'default': WebSocketClientSettings()
                ..reconnect = (WebSocketReconnectSettings()
                  ..delay = const Duration(milliseconds: 10)
                  ..maxDelay = const Duration(milliseconds: 40)),
            },
      transport: sockets,
    ),
    session: () => login,
  );
}

/// The server side of one mock connection: reads the messages the client
/// sent, `{topic, event, payload, ref, join_ref}`, and answers them.
final class RealtimeServer {
  RealtimeServer(this.socket);

  /// The next connection the client opens.
  static Future<RealtimeServer> next(MockWebSocketTransport sockets) async =>
      RealtimeServer(await sockets.nextConnection);

  final MockWebSocket socket;
  var _read = 0;

  /// Every message the client sent on this connection.
  List<Map<String, Object?>> get frames => [
    for (final frame in socket.sentJson) frame! as Map<String, Object?>,
  ];

  /// The messages of [event].
  List<Map<String, Object?>> framesOf(String event) => [
    for (final frame in frames)
      if (frame['event'] == event) frame,
  ];

  /// The events the client sent, in order, without the heartbeats.
  List<String> get events => [
    for (final frame in frames)
      if (frame['event'] != 'heartbeat') '${frame['event']}',
  ];

  /// The next message of [event] that no earlier call returned, waiting
  /// for it; messages of other events before it are skipped.
  Future<Map<String, Object?>> take(String event) async {
    for (var i = 0; i < 500; i++) {
      final sent = frames;
      while (_read < sent.length) {
        final frame = sent[_read++];
        if (frame['event'] == event) {
          return frame;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    fail('the client sent no $event: $frames');
  }

  /// Answers [frame] with [status] and [response].
  void reply(
    Map<String, Object?> frame, {
    String status = 'ok',
    Object? response = const <String, Object?>{},
  }) => socket.pushJson({
    'topic': frame['topic'],
    'event': 'phx_reply',
    'ref': frame['ref'],
    'payload': {'status': status, 'response': response},
  });

  /// Waits for the next join and accepts it; gives its message.
  /// [ids] are the ids of its subscriptions to database changes, in
  /// order.
  Future<Map<String, Object?>> acceptJoin({List<int> ids = const []}) async {
    final join = await take('phx_join');
    final asked = configOf(join)['postgres_changes']! as List<Object?>;
    reply(
      join,
      response: {
        'postgres_changes': [
          for (final (index, subscription) in asked.indexed)
            {...subscription! as Map<String, Object?>, 'id': ids[index]},
        ],
      },
    );
    await pump();
    return join;
  }

  /// Waits for the next message of [event] and answers it.
  Future<Map<String, Object?>> accept(String event) async {
    final frame = await take(event);
    reply(frame);
    await pump();
    return frame;
  }

  /// Sends [event] with [payload] on the channel [name].
  void send(String name, String event, Object? payload) => socket.pushJson({
    'topic': 'realtime:$name',
    'event': event,
    'payload': payload,
    'ref': null,
  });

  /// Sends a database change of [type] to the subscriptions [ids] of the
  /// channel [name].
  void change(
    String name,
    List<int> ids,
    String type, {
    Map<String, Object?> record = const {},
    Map<String, Object?> old = const {},
    String table = 'todos',
    Object? errors,
  }) => send(name, 'postgres_changes', {
    'ids': ids,
    'data': {
      'schema': 'public',
      'table': table,
      'commit_timestamp': '2026-11-10T08:30:00.000Z',
      'type': type,
      'columns': [
        {'name': 'id', 'type': 'int8'},
        {'name': 'title', 'type': 'text'},
      ],
      'record': record,
      'old_record': old,
      'errors': errors,
    },
  });

  /// Sends the broadcast [event] with [payload] on the channel [name].
  void broadcast(String name, String event, Object? payload) => send(
    name,
    'broadcast',
    {'type': 'broadcast', 'event': event, 'payload': payload},
  );

  /// The `config` of the join [frame].
  static Map<String, Object?> configOf(Map<String, Object?> frame) =>
      (frame['payload']! as Map<String, Object?>)['config']!
          as Map<String, Object?>;

  /// The access token of the join [frame].
  static Object? tokenOf(Map<String, Object?> frame) =>
      (frame['payload']! as Map<String, Object?>)['access_token'];
}

/// A presence of the protocol: `{metas: [{phx_ref, ...}]}` with one
/// meta per entry of [metas], reference to state.
Map<String, Object?> metas(Map<String, Map<String, Object?>> metas) => {
  'metas': [
    for (final MapEntry(key: ref, value: state) in metas.entries)
      {'phx_ref': ref, ...state},
  ],
};

/// The presences of [list] as `key/ref` texts, for comparisons.
List<String> refs(List<RealtimePresence> list) => [
  for (final presence in list) '${presence.key}/${presence.ref}',
];
