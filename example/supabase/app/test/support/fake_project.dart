import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show BeanOverride, BeanOverrideProcessor;
import 'package:supabase_example_app/spring_gen/main.spring.dart';
import 'package:supabase_example_app/src/profile/avatars.dart';

/// A PNG of one pixel: what [FakeAvatarPainter] draws.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGA'
  'WjR9awAAAABJRU5ErkJggg==',
);

/// A Supabase project played in memory, as much of it as the app uses:
/// Auth (sign-up, sign-in with a password, sign-out), the REST API of
/// `todos` with each user's own rows, Realtime telling their changes,
/// Storage's bucket `avatars` and the Edge Function `send-invite`.
///
/// It is the app's network: its `HttpTransport` and its
/// `WebSocketTransport`. No server is needed; [requests] keeps what the
/// app sent.
final class FakeProject implements HttpTransport, WebSocketTransport {
  /// Every HTTP request of the app, in order.
  final requests = <HttpRequest>[];

  /// The rows of `todos`, with their `owner`.
  final todos = <Map<String, Object?>>[];

  /// The objects of the bucket `avatars`, by path.
  final avatars = <String, List<int>>{};

  /// Whether a new user must confirm their address before signing in (a
  /// project's "Confirm email").
  bool confirmEmail = false;

  /// The status `send-invite` answers with.
  int inviteStatus = 200;

  final _users = <String, ({String id, String password})>{};
  final _sockets = <_FakeSocket>[];
  int _nextTodo = 1;

  /// What `springBootTest(overrides:)` and [application] take.
  List<BeanOverride<Object>> get overrides => [
    BeanOverride<HttpTransport>(this, name: 'httpTransport'),
    BeanOverride<WebSocketTransport>(this),
    // Where the app keeps its session and its files: no plugin answers
    // in a widget test.
    BeanOverride<SecretStore>(InMemorySecretStore()),
    BeanOverride<FileStore>(InMemoryFileStore()),
    BeanOverride<AvatarPainter>(FakeAvatarPainter()),
  ];

  /// The app as `flutter run` starts it (for `SpringApplicationWidget`),
  /// with [overrides] applied like `springBootTest` does.
  SpringApplication application() {
    final app = springApplication;
    return SpringApplication(
      app.modules,
      autoConfigurations: app.autoConfigurations,
      autoConfigurationMetadata: app.autoConfigurationMetadata,
      dartDefines: const {'SUPABASE_ANON_KEY': anonKey},
      fingerprint: app.fingerprint,
      initializers: [
        ...app.initializers,
        ApplicationContextInitializer.of(
          (context) => context.addBeanFactoryPostProcessor(
            BeanOverrideProcessor(overrides),
          ),
        ),
      ],
    );
  }

  /// The anon key of the project.
  static const anonKey = 'anon-KEY-9f3a71c2';

  /// A user who signed up before the test; gives their id.
  String addUser(String email, String password) {
    final id = 'user-${_users.length + 1}';
    _users[email] = (id: id, password: password);
    return id;
  }

  /// The id of the user with [email].
  String idOf(String email) => _users[email]!.id;

  /// A row written by someone else (another window, the example's
  /// server): Realtime tells the app.
  void addTodo(String owner, String title, {String listId = 'home'}) =>
      _insert({'title': title, 'list_id': listId, 'done': false}, owner);

  /// The requests of [method] whose path starts with [path].
  List<HttpRequest> sent(HttpMethod method, String path) => [
    for (final request in requests)
      if (request.method == method && request.url.path.startsWith(path))
        request,
  ];

  // ----------------------------------------------------------- HTTP

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.headers['apikey'] != anonKey && !path.contains('/public/')) {
      return _json(request, 401, {'message': 'No API key found in request'});
    }
    return switch (path) {
      '/auth/v1/signup' => _signUp(request),
      '/auth/v1/token' => _signIn(request),
      '/auth/v1/logout' => HttpResponse(204, request: request),
      '/rest/v1/todos' => _todos(request),
      '/functions/v1/api/send-invite' => _invite(request),
      _ when path.startsWith('/storage/v1/object/') => _storage(request),
      _ => _json(request, 404, {'message': 'no $path in the fake project'}),
    };
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    final response = await send(request);
    return StreamedHttpResponse(
      response.statusCode,
      headers: response.headers,
      body: Stream.value(response.bodyBytes),
      request: request,
    );
  }

  @override
  void close() {}

  static HttpResponse _json(HttpRequest request, int status, Object? json) =>
      HttpResponse(
        status,
        headers: HttpHeaders({'Content-Type': 'application/json'}),
        body: utf8.encode(jsonEncode(json)),
        request: request,
      );

  static Map<String, Object?> _body(HttpRequest request) =>
      jsonDecode(utf8.decode(request.body ?? const [])) as Map<String, Object?>;

  /// The id of the user whose token [request] carries; `null` for the
  /// anon key.
  String? _caller(HttpRequest request) {
    final token = request.headers['Authorization']?.replaceFirst('Bearer ', '');
    return token != null && token.startsWith('token-of-')
        ? token.substring('token-of-'.length)
        : null;
  }

  Map<String, Object?> _user(String id, String email) => {
    'id': id,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': email,
    'app_metadata': {'provider': 'email'},
    'user_metadata': <String, Object?>{},
  };

  Map<String, Object?> _session(String id, String email) => {
    'access_token': 'token-of-$id',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-of-$id',
    'user': _user(id, email),
  };

  HttpResponse _signUp(HttpRequest request) {
    final body = _body(request);
    final email = body['email']! as String;
    final password = body['password']! as String;
    if (password.length < 6) {
      return _json(request, 422, {
        'code': 422,
        'error_code': 'weak_password',
        'msg': 'Password should be at least 6 characters.',
      });
    }
    if (_users.containsKey(email)) {
      return _json(request, 422, {
        'code': 422,
        'error_code': 'user_already_exists',
        'msg': 'User already registered',
      });
    }
    final id = addUser(email, password);
    return _json(
      request,
      200,
      confirmEmail ? _user(id, email) : _session(id, email),
    );
  }

  HttpResponse _signIn(HttpRequest request) {
    final body = _body(request);
    final email = body['email']! as String;
    final password = body['password']! as String;
    final user = _users[email];
    if (user == null || user.password != password) {
      return _json(request, 400, {
        'code': 400,
        'error_code': 'invalid_credentials',
        'msg': 'Invalid login credentials',
      });
    }
    return _json(request, 200, _session(user.id, email));
  }

  // The REST API of `todos`, with the one policy of the table: a user
  // reads and writes their own rows.
  HttpResponse _todos(HttpRequest request) {
    final caller = _caller(request);
    if (caller == null) {
      return _json(request, 401, {
        'code': '42501',
        'message': 'permission denied for table todos',
      });
    }
    final query = request.url.queryParameters;
    bool matches(Map<String, Object?> row) =>
        row['owner'] == caller &&
        (query['id'] == null || query['id'] == 'eq.${row['id']}') &&
        (query['list_id'] == null ||
            query['list_id'] == 'eq.${row['list_id']}');
    Map<String, Object?> shown(Map<String, Object?> row) =>
        {...row}..remove('owner');

    switch (request.method) {
      case HttpMethod.post:
        return _json(request, 201, [shown(_insert(_body(request), caller))]);
      case HttpMethod.patch:
        final changed = todos.where(matches).toList();
        for (final row in changed) {
          row.addAll(_body(request));
          _tell('UPDATE', record: shown(row));
        }
        return _json(request, 200, changed.map(shown).toList());
      case HttpMethod.delete:
        final gone = todos.where(matches).toList();
        todos.removeWhere(matches);
        for (final row in gone) {
          _tell('DELETE', old: {'id': row['id']});
        }
        return HttpResponse(204, request: request);
      default:
        return _json(request, 200, todos.where(matches).map(shown).toList());
    }
  }

  Map<String, Object?> _insert(Map<String, Object?> values, String owner) {
    final row = {
      'done': false,
      'created_at': null,
      ...values,
      'id': _nextTodo++,
      'owner': owner,
    };
    todos.add(row);
    _tell('INSERT', record: {...row}..remove('owner'));
    return row;
  }

  // Storage: the caller's own folder of `avatars` only.
  HttpResponse _storage(HttpRequest request) {
    final caller = _caller(request);
    final path = request.url.path
        .substring('/storage/v1/object/'.length)
        .replaceFirst(RegExp('^authenticated/'), '');
    if (caller == null || !path.startsWith('avatars/$caller/')) {
      return _json(request, 400, {
        'statusCode': '403',
        'error': 'Unauthorized',
        'message': 'new row violates row-level security policy',
      });
    }
    if (request.method == HttpMethod.post) {
      avatars[path] = request.body ?? const [];
      return _json(request, 200, {'Key': path});
    }
    final object = avatars[path];
    return object == null
        ? _json(request, 400, {
            'statusCode': '404',
            'error': 'not_found',
            'message': 'Object not found',
          })
        : HttpResponse(
            200,
            headers: HttpHeaders({'Content-Type': 'image/png'}),
            body: object,
            request: request,
          );
  }

  // `send-invite`: who called and what was sent.
  HttpResponse _invite(HttpRequest request) => inviteStatus == 200
      ? _json(request, 200, {
          'id': '${_caller(request) ?? 'anon'}|${_body(request)['email']}',
        })
      : _json(request, inviteStatus, {'error': 'the function failed'});

  // ------------------------------------------------------- Realtime

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
    int? maxTextMessageSize,
    int? maxBinaryMessageSize,
  }) async {
    final socket = _FakeSocket(url);
    _sockets.add(socket);
    return socket;
  }

  /// How many connections to Realtime are open.
  int get openSockets => _sockets.where((socket) => socket.isOpen).length;

  // A change of `todos`, to every channel that asked for them. (The real
  // Realtime sends a user only the rows they may read; the app asks the
  // REST API again anyway, which does apply the policy here.)
  void _tell(
    String type, {
    Map<String, Object?> record = const {},
    Map<String, Object?> old = const {},
  }) {
    for (final socket in _sockets) {
      socket.tell({
        'schema': 'public',
        'table': 'todos',
        'commit_timestamp': DateTime.now().toUtc().toIso8601String(),
        'type': type,
        'columns': const <Object?>[],
        'record': record,
        'old_record': old,
        'errors': null,
      });
    }
  }
}

/// The server side of one connection to Realtime, in its first wire
/// format (a JSON object per message): every join, heartbeat and leave is
/// accepted.
final class _FakeSocket implements WebSocketSession {
  _FakeSocket(this.uri);

  @override
  final Uri uri;

  final _incoming = StreamController<Object>();

  // The topics that asked for database changes, with the ids of their
  // subscriptions.
  final _subscriptions = <String, List<int>>{};
  int _nextId = 1;

  @override
  Stream<Object> get messages => _incoming.stream;

  @override
  String? get acceptedProtocol => null;

  @override
  bool get isOpen => closeStatus == null;

  @override
  CloseStatus? closeStatus;

  void _push(Map<String, Object?> message) {
    if (isOpen) {
      _incoming.add(jsonEncode(message));
    }
  }

  @override
  void sendMessage(Object message) {
    final frame = jsonDecode(message as String) as Map<String, Object?>;
    final topic = frame['topic']! as String;
    var response = const <String, Object?>{};
    switch (frame['event']) {
      case 'phx_join':
        final asked = switch (frame['payload']) {
          {'config': {'postgres_changes': final List<Object?> changes}} =>
            changes,
          _ => const <Object?>[],
        };
        final ids = [for (final _ in asked) _nextId++];
        _subscriptions[topic] = ids;
        response = {
          'postgres_changes': [
            for (final (index, subscription) in asked.indexed)
              {...subscription! as Map<String, Object?>, 'id': ids[index]},
          ],
        };
      case 'phx_leave':
        _subscriptions.remove(topic);
    }
    if (frame['ref'] != null) {
      _push({
        'topic': topic,
        'event': 'phx_reply',
        'ref': frame['ref'],
        'payload': {'status': 'ok', 'response': response},
      });
    }
  }

  void tell(Map<String, Object?> change) {
    for (final MapEntry(key: topic, value: ids) in _subscriptions.entries) {
      if (ids.isNotEmpty) {
        _push({
          'topic': topic,
          'event': 'postgres_changes',
          'ref': null,
          'payload': {'ids': ids, 'data': change},
        });
      }
    }
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) async {
    closeStatus ??= status;
    await _incoming.close();
  }
}

/// Draws nothing: the same PNG of one pixel each time (the real painter
/// needs the engine's picture recorder).
final class FakeAvatarPainter extends AvatarPainter {
  /// The letters it was asked to draw.
  final letters = <String>[];

  @override
  Future<Uint8List> paint(String letter, Color color) async {
    letters.add(letter);
    return onePixelPng;
  }
}
