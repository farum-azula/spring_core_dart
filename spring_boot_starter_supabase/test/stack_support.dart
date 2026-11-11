// What the level 4 tests (stack_*_test.dart) share: where the stack is
// (environment variables), the test application started against it with
// the real transports, users made through the admin API, the mail
// catcher, and a recorder of a stream.
//
// The stack is the Supabase CLI's (test/stack/README.md) or a hosted
// project with the same migration and functions.
import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';

export 'app/supabase_app.dart';
export 'app_support.dart' show supabaseRunner;

/// Where the stack is and what it was started with, from the environment.
abstract final class Stack {
  /// The value of the variable [name], without the quotes
  /// `supabase status -o env` puts around it; `null` when not set.
  static String? env(String name) {
    var value = io.Platform.environment[name]?.trim();
    if (value == null) {
      return null;
    }
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value.isEmpty ? null : value;
  }

  /// `SUPABASE_URL`: the address of the project (the gateway).
  static final String? _url = switch (env('SUPABASE_URL')) {
    final url? when url.endsWith('/') => url.substring(0, url.length - 1),
    final url => url,
  };

  /// The address of the project.
  static String get url => _url!;

  /// `SUPABASE_ANON_KEY`.
  static String get anonKey => env('SUPABASE_ANON_KEY')!;

  /// `SUPABASE_SERVICE_ROLE_KEY`.
  static String get serviceRoleKey => env('SUPABASE_SERVICE_ROLE_KEY')!;

  /// `SUPABASE_DB_URL`: the PostgreSQL address of the project.
  static String? get dbUrl => env('SUPABASE_DB_URL');

  /// `SUPABASE_JWT_SECRET`: the legacy secret, for a stack that signs its
  /// users' tokens with HS256.
  static String? get jwtSecret => env('SUPABASE_JWT_SECRET');

  /// `SUPABASE_MAILPIT_URL`: the mail catcher of the local stack.
  static String? get mailUrl => switch (env('SUPABASE_MAILPIT_URL')) {
    final url? when url.endsWith('/') => url.substring(0, url.length - 1),
    final url => url,
  };

  /// `SUPABASE_SITE_URL`: the project's `site_url`, where Auth sends a
  /// login back when the address asked for is not allowed.
  static String get siteUrl =>
      env('SUPABASE_SITE_URL') ?? 'http://127.0.0.1:3000';

  /// `SUPABASE_REDIRECT_URL`: the address of the project's list of
  /// redirect URLs.
  static String get redirectUrl =>
      env('SUPABASE_REDIRECT_URL') ?? 'com.example.stack://login';

  /// An address that is in no project's list.
  static const strangerRedirectUrl = 'http://stranger.example.test/callback';

  /// Whether the stack runs on this machine.
  static bool get isLocal => const {
    '127.0.0.1',
    'localhost',
    '::1',
  }.contains(Uri.parse(url).host);

  /// `SUPABASE_REFRESH_TOKEN_REUSE_INTERVAL`: for how long a used refresh
  /// token is still taken (`refresh_token_reuse_interval`): 0 in the
  /// local stack's config.toml, 10 seconds in a hosted project unless
  /// set.
  static Duration get refreshReuseInterval => Duration(
    seconds:
        int.tryParse(env('SUPABASE_REFRESH_TOKEN_REUSE_INTERVAL') ?? '') ??
        (isLocal ? 0 : 10),
  );

  /// Why every test of level 4 is skipped; `null` with a stack.
  static String? get skip => _url == null
      ? 'SUPABASE_URL is not set: level 4 needs the whole of Supabase '
            '(test/stack/README.md)'
      : null;

  /// Why the tests that read mails are skipped; `null` with a mail
  /// catcher.
  static String? get skipMail => mailUrl == null
      ? 'SUPABASE_MAILPIT_URL is not set: no mail catcher to read the '
            'mails of Auth from (a hosted project sends them for real)'
      : null;

  /// Why the tests of the SQL path are skipped; `null` with a database
  /// address.
  static String? get skipDb => dbUrl == null
      ? 'SUPABASE_DB_URL is not set: no PostgreSQL address of the project'
      : null;

  /// Fails when the stack is given without its keys: a half-configured
  /// run must not pass as skipped.
  static void require() {
    for (final name in ['SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY']) {
      if (env(name) == null) {
        fail('SUPABASE_URL is set but $name is not');
      }
    }
  }

  static final _random = Random.secure();

  /// [prefix] with twelve random hexadecimal digits: a name no other run
  /// uses.
  static String unique(String prefix) {
    final digits = [
      for (var i = 0; i < 12; i++) _random.nextInt(16).toRadixString(16),
    ].join();
    return '$prefix$digits';
  }

  /// An HTTP transport of the platform, without any key: for the
  /// addresses a browser would open (public and signed URLs, links of
  /// mails, the mail catcher).
  static final HttpTransport plain = platformHttpTransport();

  /// `GET` [url] with nothing of the project in the request and no
  /// redirect followed.
  static Future<HttpResponse> get(Uri url) => plain.send(
    HttpRequest(
      method: HttpMethod.get,
      url: url,
      timeout: const Duration(seconds: 30),
      followRedirects: false,
    ),
  );
}

/// The header of [token], a JWT.
Map<String, Object?> jwtHeader(String token) {
  final json = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(token.split('.').first))),
  );
  return json is Map<String, Object?> ? json : const {};
}

/// A user of the project, made by a test.
final class StackUser {
  /// The user [id] with the [email] and [password] they sign in with.
  StackUser(this.id, this.email, this.password);

  final String id;
  final String email;
  final String password;

  /// An address and a password nobody has.
  static ({String email, String password}) credentials() => (
    email: '${Stack.unique('stack-')}@example.com',
    password: Stack.unique('Pw-'),
  );
}

/// The test application (test/app/supabase_app.dart) started against the
/// stack: the starter's own beans, the real HTTP and WebSocket
/// transports, a `SecretStore` in memory. One application has one login,
/// so a test with two users starts two.
final class StackApp {
  StackApp._(this.context, this.secrets, this.sockets, this._stop);

  /// Starts the application, with [properties] on top of the project's
  /// address and keys. With [recordSockets] its WebSocket transport
  /// records the connections ([sockets]).
  static Future<StackApp> start({
    List<String> properties = const [],
    List<String>? redirectUrls,
    bool recordSockets = false,
    ApplicationContextRunner Function()? runner,
  }) async {
    final ready = Completer<StackApp>();
    final stop = Completer<void>();
    final secrets = InMemorySecretStore();
    final sockets = recordSockets ? SocketRecorder() : null;
    final redirects = (redirectUrls ?? [Stack.redirectUrl]).join(',');
    var configured = (runner ?? baseRunner)()
        .withPropertyValues([
          'spring.supabase.url=${Stack.url}',
          'spring.supabase.anon-key=${Stack.anonKey}',
          'spring.supabase.service-role-key=${Stack.serviceRoleKey}',
          'spring.supabase.auth.redirect-urls=$redirects',
          ...properties,
        ])
        .withBean<SecretStore>(() => secrets);
    if (sockets != null) {
      configured = configured.withBean<WebSocketTransport>(() => sockets);
    }
    final done = configured.runAsync((context) async {
      final failure = context.startupFailure;
      if (failure != null) {
        ready.completeError(
          StateError('The application failed to start: $failure'),
        );
        return;
      }
      ready.complete(StackApp._(context, secrets, sockets, stop));
      await stop.future;
    });
    unawaited(
      done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!ready.isCompleted) {
            ready.completeError(error, stackTrace);
          }
        },
      ),
    );
    final app = await ready.future;
    app._done = done;
    return app;
  }

  final AssertableApplicationContext context;

  /// Where the application keeps its session.
  final InMemorySecretStore secrets;

  /// The WebSocket connections, when the application was started with
  /// `recordSockets`.
  final SocketRecorder? sockets;

  static final Object _scope = Object();

  final Completer<void> _stop;
  late final Future<void> _done;
  final _users = <String>{};

  T bean<T extends Object>() => context.getBean<T>();

  SupabaseAuth get auth => bean();
  SupabaseAuthAdmin get admin => bean();
  SupabaseCredentials get credentials => bean();
  SupabaseHttp get http => bean();
  SupabaseRealtime get realtime => bean();
  StorageTemplate get storage => bean();
  PostgrestDataStore get store => bean();
  Todos get todos => bean();
  Notes get notes => bean();
  Avatars get avatars => bean();
  Functions get functions => bean();
  Room get room => bean();

  /// The id of the signed-in user.
  String get userId => auth.user!.id;

  /// Runs [body] as this application: with its login as the current user
  /// of Spring Security, in a scope of its own, so that two applications
  /// in one test (two users) do not see each other's.
  ///
  /// Inside itself it only runs [body]: a login made there is the login
  /// of the whole scope.
  Future<T> run<T>(Future<T> Function() body) =>
      identical(Zone.current[_scope], this)
      ? body()
      : runZoned(
          () => SecurityContextHolder.runWithContext(
            body,
            SecurityContextImpl(auth.authentication),
          ),
          zoneValues: {_scope: this},
        );

  /// The session as the application stored it (with its refresh token);
  /// `null` when nobody is signed in.
  Future<SupabaseSession?> session() async =>
      switch (await secrets.read(SupabaseAuth.sessionKey)) {
        final stored? => SupabaseSession.decode(stored),
        null => null,
      };

  /// A new user with a confirmed address, made through the admin API and
  /// deleted when the application closes.
  Future<StackUser> createUser({Map<String, Object?>? appMetadata}) async {
    final (:email, :password) = StackUser.credentials();
    final user = await admin.createUser(
      email: email,
      password: password,
      emailConfirm: true,
      appMetadata: appMetadata,
    );
    _users.add(user.id);
    return StackUser(user.id, email, password);
  }

  /// Makes a new user and signs this application in as them.
  Future<StackUser> signInAsNewUser() async {
    final user = await createUser();
    await signIn(user);
    return user;
  }

  /// Signs this application in as [user], with their password.
  Future<void> signIn(StackUser user) => run(
    () => auth.signInWithPassword(email: user.email, password: user.password),
  );

  /// Deletes the user [id] when the application closes.
  void deleteAtClose(String id) => _users.add(id);

  /// The id of the user with [email], asked of the admin API; `null`
  /// when there is none.
  Future<String?> userIdOf(String email) async {
    for (var page = 1; page <= 50; page++) {
      final users = await admin.users(page: page, perPage: 200);
      for (final user in users) {
        if (user.email?.toLowerCase() == email.toLowerCase()) {
          return user.id;
        }
      }
      if (users.length < 200) {
        return null;
      }
    }
    return null;
  }

  /// A request to the REST API as the current caller, outside the
  /// repositories; the answer as it came.
  Future<HttpResponse> rest(
    HttpMethod method,
    String path, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    Object? json,
  }) => http.send(
    SupabaseService.rest,
    method,
    path,
    query: query.entries,
    headers: headers,
    json: json,
  );

  /// Deletes the users made here and stops the application. The rows and
  /// objects of a user are the test's to remove.
  Future<void> close() async {
    for (final id in _users) {
      try {
        await admin.deleteUser(id);
      } on Object catch (error) {
        // The rest of the cleanup goes on; the leftover is a random user.
        printOnFailure('user $id was not deleted: ${error.runtimeType}');
      }
    }
    _stop.complete();
    await _done;
  }
}

/// A mail of Auth, read from the mail catcher.
final class StackMail {
  StackMail(this.subject, this.body);

  final String subject;

  /// The HTML of the mail, or its text.
  final String body;

  static String _unescape(String text) => text
      .replaceAllMapped(
        RegExp('&#(x?)([0-9a-fA-F]+);'),
        (m) => String.fromCharCode(
          int.parse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16),
        ),
      )
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// The one-time code: of the stack's own template
  /// (test/stack/supabase/templates/mail.html), else the first run of six
  /// digits.
  String get code =>
      RegExp(r'code=\[(\d+)\]').firstMatch(body)?[1] ??
      RegExp(r'(?<!\d)(\d{6})(?!\d)').firstMatch(body)?[1] ??
      (throw StateError('no code in the mail "$subject"'));

  /// The link of the mail: Auth's `/verify` with the token.
  Uri get link {
    final links = RegExp(
      'href="([^"]+)"',
    ).allMatches(body).map((m) => _unescape(m[1]!));
    return Uri.parse(
      links.firstWhere(
        (link) => link.contains('/verify'),
        orElse: () => throw StateError('no link in the mail "$subject"'),
      ),
    );
  }

  /// Opens the [link] as a browser would, without following it: the
  /// address Auth sends the user to.
  Future<Uri> follow() async {
    final response = await Stack.get(link);
    final location = response.headers.location;
    if (location == null) {
      fail(
        'the link of the mail "$subject" answered '
        '${response.statusCode.value} without a Location',
      );
    }
    return location;
  }
}

/// The mail catcher of the local stack (Mailpit; its API under
/// `/api/v1`).
final class MailCatcher {
  final _seen = <String>{};

  static Future<Object?> _json(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await Stack.get(
      Uri.parse('${Stack.mailUrl}$path').replace(queryParameters: query),
    );
    if (!response.isSuccess) {
      fail(
        'the mail catcher answered ${response.statusCode.value} to $path',
      );
    }
    return jsonDecode(response.bodyText);
  }

  /// The next mail to [email] this catcher has not given yet, waited for
  /// up to [timeout].
  Future<StackMail> next(
    String email, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final found = await _json('/api/v1/search', {'query': 'to:"$email"'});
      if (found case {'messages': final List<Object?> messages}) {
        for (final message in messages) {
          if (message
              case {
                'ID': final String id,
              }
              when _seen.add(id)) {
            final mail = await _json('/api/v1/message/$id');
            if (mail is Map<String, Object?>) {
              final html = mail['HTML'];
              final text = mail['Text'];
              return StackMail(
                '${mail['Subject'] ?? ''}',
                html is String && html.isNotEmpty ? html : '${text ?? ''}',
              );
            }
          }
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        fail('no mail to $email within ${timeout.inSeconds} s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
}

/// Listens to a stream and keeps what it gave, so that a test can wait
/// for an event that may already have come.
final class Recorder<T> {
  /// Listens to [stream] at once.
  Recorder(Stream<T> stream) {
    _subscription = stream.listen(
      (event) {
        events.add(event);
        _wake();
      },
      onError: (Object error) {
        errors.add(error);
        _wake();
      },
      onDone: () {
        isDone = true;
        _wake();
      },
    );
  }

  late final StreamSubscription<T> _subscription;
  Completer<void>? _waiter;

  /// The events so far, in their order.
  final events = <T>[];

  /// The error events so far.
  final errors = <Object>[];

  /// Whether the stream is done.
  bool isDone = false;

  void _wake() {
    _waiter?.complete();
    _waiter = null;
  }

  /// The first event, among those so far and those to come, that
  /// [matches]; `null` when none came within [timeout].
  Future<T?> maybe(
    bool Function(T event) matches, {
    Duration timeout = const Duration(seconds: 20),
    int from = 0,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var checked = from;
    while (true) {
      for (; checked < events.length; checked++) {
        if (matches(events[checked])) {
          return events[checked];
        }
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero || isDone) {
        return null;
      }
      await (_waiter ??= Completer<void>()).future.timeout(
        left,
        onTimeout: () {},
      );
    }
  }

  /// The first event that [matches], or the failure of the test.
  Future<T> next(
    bool Function(T event) matches, {
    Duration timeout = const Duration(seconds: 20),
    int from = 0,
    String what = 'the event',
  }) async {
    final event = await maybe(matches, timeout: timeout, from: from);
    if (event == null) {
      fail(
        '$what did not arrive within ${timeout.inSeconds} s; got '
        '${events.length} events, errors: $errors',
      );
    }
    return event;
  }

  /// Does [act] again and again (with the number of the attempt) until
  /// an event [matches]: for what a server starts to send some time
  /// after it was asked (a join, a subscription to the changes of a
  /// table).
  Future<T> provoke(
    Future<void> Function(int attempt) act,
    bool Function(T event) matches, {
    int attempts = 30,
    Duration every = const Duration(seconds: 1),
    String what = 'the event',
  }) async {
    final from = events.length;
    for (var attempt = 0; attempt < attempts; attempt++) {
      await act(attempt);
      final event = await maybe(matches, timeout: every, from: from);
      if (event != null) {
        return event;
      }
    }
    fail(
      '$what did not arrive after $attempts attempts; got ${events.length} '
      'events, errors: $errors',
    );
  }

  Future<void> cancel() => _subscription.cancel();
}

/// A message of the Phoenix protocol as it went over a recorded socket.
typedef SocketFrame = ({String? topic, String? event, Object? payload});

/// The real WebSocket transport of the platform, recording its
/// connections: what was sent on them, and a way to drop one from this
/// side, as a network would.
final class SocketRecorder implements WebSocketTransport {
  final WebSocketTransport _delegate = platformWebSocketTransport();

  /// Every connection opened so far.
  final sessions = <RecordedSocket>[];

  /// Every message sent so far, on any connection.
  Iterable<SocketFrame> get sent => sessions.expand((s) => s.sent);

  @override
  Future<WebSocketSession> connect(
    Uri url, {
    HttpHeaders? headers,
    List<String> protocols = const [],
    Duration? timeout,
    int? maxTextMessageSize,
    int? maxBinaryMessageSize,
  }) async {
    final session = RecordedSocket(
      await _delegate.connect(
        url,
        headers: headers,
        protocols: protocols,
        timeout: timeout,
        maxTextMessageSize: maxTextMessageSize,
        maxBinaryMessageSize: maxBinaryMessageSize,
      ),
    );
    sessions.add(session);
    return session;
  }

  /// The first message sent, so far or within [timeout], that [matches],
  /// or the failure of the test. A message the application hands to its
  /// connection is on the wire (and here) a moment later, not at once:
  /// the connection sends it in a turn of its own.
  Future<SocketFrame> next(
    bool Function(SocketFrame frame) matches, {
    Duration timeout = const Duration(seconds: 5),
    String what = 'the message',
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final found = sent.where(matches).firstOrNull;
      if (found != null) {
        return found;
      }
      if (!DateTime.now().isBefore(deadline)) {
        fail(
          '$what was not sent within ${timeout.inSeconds} s; sent: '
          '${[for (final frame in sent) '${frame.event} on ${frame.topic}']}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Closes the open connection behind the application's back, with the
  /// code of a server that goes away: the application has to connect
  /// again.
  Future<void> drop() async {
    final open = sessions.where((s) => s.isOpen).toList();
    expect(open, isNotEmpty, reason: 'no open connection to drop');
    for (final session in open) {
      await session._delegate.close(CloseStatus.goingAway);
    }
  }
}

/// A connection of a [SocketRecorder].
final class RecordedSocket implements WebSocketSession {
  RecordedSocket(this._delegate);

  final WebSocketSession _delegate;

  /// The messages sent on this connection.
  final sent = <SocketFrame>[];

  static SocketFrame? _frame(Object message) {
    if (message is! String) {
      return null;
    }
    try {
      return switch (jsonDecode(message)) {
        // vsn 1.0.0: an object.
        final Map<String, Object?> json => (
          topic: json['topic'] as String?,
          event: json['event'] as String?,
          payload: json['payload'],
        ),
        // vsn 2.0.0: [join_ref, ref, topic, event, payload].
        [_, _, final String? topic, final String? event, final payload] => (
          topic: topic,
          event: event,
          payload: payload,
        ),
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  @override
  Uri get uri => _delegate.uri;

  @override
  Stream<Object> get messages => _delegate.messages;

  @override
  String? get acceptedProtocol => _delegate.acceptedProtocol;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  void sendMessage(Object message) {
    if (_frame(message) case final frame?) {
      sent.add(frame);
    }
    _delegate.sendMessage(message);
  }

  @override
  Future<void> close([CloseStatus status = CloseStatus.normal]) =>
      _delegate.close(status);

  @override
  CloseStatus? get closeStatus => _delegate.closeStatus;
}
