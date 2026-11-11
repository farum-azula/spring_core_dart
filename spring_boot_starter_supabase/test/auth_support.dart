// What the tests of Supabase Auth share: a clock and timers moved by
// hand, a recorder of events, answers shaped like Auth's, and the capture
// of everything logged.
import 'dart:async';
import 'dart:convert';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_web_dart/testing.dart';

import 'support.dart';

/// The id of the user of the tests.
const userId = '11111111-2222-3333-4444-555555555555';

/// A clock that only moves when a test says so.
final class TestClock {
  /// The time it shows.
  DateTime now = DateTime.utc(2026, 11, 10, 12);

  /// The time it shows (the function a `SupabaseAuth` takes).
  DateTime call() => now;

  /// Moves the clock on.
  void advance(Duration duration) => now = now.add(duration);
}

/// A timer that fires when a test says so.
final class ManualTimer implements Timer {
  /// A timer asked to fire after [delay].
  ManualTimer(this.delay, this._callback);

  /// When it was asked to fire.
  final Duration delay;

  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;

  /// Fires the timer, as the time passing would.
  void fire() {
    if (!_active) {
      throw StateError('The timer was cancelled or has fired');
    }
    _active = false;
    _callback();
  }
}

/// The timers a `SupabaseAuth` asked for.
final class ManualTimers {
  /// Every timer asked for, in order.
  final all = <ManualTimer>[];

  /// The factory a `SupabaseAuth` takes.
  Timer create(Duration delay, void Function() callback) {
    final timer = ManualTimer(delay, callback);
    all.add(timer);
    return timer;
  }

  /// The timers that have neither fired nor been cancelled.
  List<ManualTimer> get active => [
    for (final timer in all)
      if (timer.isActive) timer,
  ];
}

/// Keeps the events a `SupabaseAuth` publishes.
final class RecordingPublisher implements ApplicationEventPublisher {
  /// The events, in order.
  final events = <Object>[];

  @override
  void publishEvent<T extends Object>(T event) => events.add(event);
}

/// An `AuthorizationWindow` that answers as a test says.
final class FakeWindow implements AuthorizationWindow {
  /// Answers with what [answer] makes of the redirect and authorization
  /// addresses; [redirect] replaces the redirect address asked for (a
  /// loopback window's own port).
  FakeWindow(this.answer, {this.redirect});

  /// The redirect that comes back.
  final FutureOr<Uri> Function(Uri redirectUri, Uri authorizationUri) answer;

  /// The redirect address the window uses instead of the one asked for.
  final Uri? redirect;

  /// The authorization addresses that were opened.
  final opened = <Uri>[];

  @override
  Future<Uri> authorize({
    required Uri redirectUri,
    required Uri Function(Uri redirectUri) authorizationUri,
  }) async {
    final used = redirect ?? redirectUri;
    final address = authorizationUri(used);
    opened.add(address);
    return await answer(used, address);
  }
}

/// A `SecretStore` that fails when told to.
final class FailingSecretStore extends InMemorySecretStore {
  /// Whether [write] fails.
  bool failWrites = false;

  /// Whether [delete] fails.
  bool failDeletes = false;

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw StateError('the keychain is locked');
    }
    await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) {
      throw StateError('the keychain is locked');
    }
    await super.delete(key);
  }
}

/// A user as Auth answers it.
Map<String, Object?> userJson({
  String id = userId,
  String? email = 'ada@example.com',
  Map<String, Object?> appMetadata = const {'provider': 'email'},
  Map<String, Object?> userMetadata = const {},
}) => {
  'id': id,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': ?email,
  'phone': '',
  'email_confirmed_at': '2026-11-01T10:00:00Z',
  'last_sign_in_at': '2026-11-10T11:59:00Z',
  'app_metadata': appMetadata,
  'user_metadata': userMetadata,
  'created_at': '2026-11-01T09:00:00Z',
  'updated_at': '2026-11-10T11:59:00Z',
  'is_anonymous': false,
};

/// A session as Auth answers it.
Map<String, Object?> sessionJson({
  String accessToken = 'access-token-1',
  String refreshToken = 'refresh-token-1',
  int expiresIn = 3600,
  Map<String, Object?>? user,
}) => {
  'access_token': accessToken,
  'token_type': 'bearer',
  'expires_in': expiresIn,
  'expires_at': 1794312000,
  'refresh_token': refreshToken,
  'user': user ?? userJson(),
};

/// An error as Auth answers it.
Map<String, Object?> errorJson(int status, String code, String message) => {
  'code': status,
  'error_code': code,
  'msg': message,
};

/// The JSON body of [request].
Map<String, Object?> bodyOf(HttpRequest request) =>
    jsonDecode(utf8.decode(request.body ?? const [])) as Map<String, Object?>;

/// Lets what is waiting in the event loop run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A `SupabaseAuth` over a fake transport, with everything around it in
/// the hands of the test.
final class AuthHarness {
  /// The answers of Auth and the requests it got.
  final transport = MockHttpTransport();

  /// The clock.
  final clock = TestClock();

  /// The refresh timers.
  final timers = ManualTimers();

  /// Where the session is kept.
  final store = FailingSecretStore();

  /// The events published.
  final publisher = RecordingPublisher();

  /// Where the current user is set.
  final contexts = GlobalSecurityContextHolderStrategy();

  /// What `authenticationChanges` of the last [auth] emitted.
  final changes = <Authentication?>[];

  /// A `SupabaseAuth` of [projectUrl].
  SupabaseAuth auth({
    List<String> redirectUrls = const [],
    bool persistSession = true,
    bool autoRefresh = false,
    Duration refreshMargin = const Duration(seconds: 30),
    AuthorizationWindow? window,
    bool serviceRole = false,
  }) {
    final all = properties(serviceRole: serviceRole);
    all.auth
      ..redirectUrls = redirectUrls
      ..persistSession = persistSession
      ..autoRefresh = autoRefresh
      ..refreshMargin = refreshMargin;
    final auth = SupabaseAuth(
      http: http(transport, properties_: all),
      secretStore: store,
      authorizationWindow: window,
      eventPublisher: publisher,
      securityContextHolderStrategy: contexts,
      clock: clock.call,
      timerFactory: timers.create,
    );
    auth.authenticationChanges.listen(changes.add);
    return auth;
  }

  /// Prepares the answer of a password login and signs in.
  Future<SupabaseAuth> signedIn({
    bool autoRefresh = false,
    Map<String, Object?>? session,
    List<String> redirectUrls = const [],
  }) async {
    final auth = this.auth(
      autoRefresh: autoRefresh,
      redirectUrls: redirectUrls,
    );
    transport
        .when(HttpMethod.post, '/auth/v1/token?grant_type=password')
        .respond(200, json: session ?? sessionJson());
    await auth.signInWithPassword(
      email: 'ada@example.com',
      password: 'correct horse',
    );
    return auth;
  }

  /// The requests sent to [path] (without the query).
  List<HttpRequest> requestsTo(String path) => [
    for (final request in transport.requests)
      if (request.url.path == path) request,
  ];

  /// The session as the store has it; `null` when it has none.
  Future<Map<String, Object?>?> storedSession() async {
    final text = await store.read(SupabaseAuth.sessionKey);
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }
}

/// Everything logged while [body] ran, at every level: a line per record,
/// with its error, stack trace and fields.
Future<List<String>> captureLogs(Future<void> Function() body) async {
  final handler = SpringLog.handler;
  SpringLog.handler = (_) {};
  SpringLog.level = SpringLogLevel.trace;
  final records = <SpringLogRecord>[];
  final stop = SpringLog.listen(records.add);
  try {
    await body();
  } finally {
    stop();
    SpringLog.handler = handler;
    SpringLog.level = SpringLogLevel.info;
    SpringLog.resetLevels();
  }
  String line(SpringLogRecord r) =>
      '[${r.loggerName}] ${r.level.name}: ${r.message} | error=${r.error} '
      '| stack=${r.stackTrace} | fields=${r.fields}';
  return records.map(line).toList();
}
