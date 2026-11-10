import 'dart:async';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/isolates/isolate_scaler.dart';
import 'package:spring_boot_starter_web/src/web_server.dart';
import 'package:spring_boot_starter_web/src/web_server_lifecycle.dart';

const _log = SpringLog('spring.web.isolates');

// A Flutter app (dart:ui exists): its beans cannot be made again in
// another isolate.
const _isFlutter = bool.fromEnvironment('dart.library.ui');

// The way back to the pool, in an isolate the pool started: set before
// the application starts there.
_Link? _link;

/// Whether this isolate was started by a pool.
bool get isServerIsolate => _link != null;

// An isolate's line to the first one: what it tells the pool, and the
// questions it asks with their answers.
final class _Link {
  _Link(this.toPrimary) {
    _answers.listen(_answered);
  }

  final SendPort toPrimary;
  final _answers = ReceivePort();
  final _waiting = <int, Completer<Object?>>{};
  var _asked = 0;

  // `[ask, number, id, request, where to answer]`.
  Future<Object?> ask(String id, Object? request) {
    final number = ++_asked;
    final answer = _waiting[number] = Completer<Object?>();
    toPrimary.send(['ask', number, id, request, _answers.sendPort]);
    return answer.future;
  }

  // `[answer, number, result, the error's text or null]`.
  void _answered(Object? message) {
    if (message case ['answer', final int number, final result, final error]) {
      final answer = _waiting.remove(number);
      if (error is String) {
        answer?.completeError(PrimaryIsolateException(error));
      } else {
        answer?.complete(result);
      }
    }
  }
}

// What an isolate of the pool is started with.
final class _Start {
  const _Start(this.launch, this.name, this.index, this.port, this.toPrimary);

  final ApplicationLaunch launch;
  final String name;
  final int index;
  final int port;
  final SendPort toPrimary;
}

// An isolate of the pool: the whole application again, on the same port.
Future<void> _serverIsolateMain(_Start start) async {
  IsolateInfo.current = IsolateInfo(
    name: start.name,
    index: start.index,
    primary: false,
  );
  final link = _link = _Link(start.toPrimary);
  // Questions for the first isolate go there from now on.
  PrimaryIsolate.remote = link.ask;
  try {
    await start.launch.start(
      properties: {
        // The primary's port, also when it asked for any free one.
        'server.port': '${start.port}',
        'spring.test.web-environment': 'defined-port',
        // Said once, by the primary.
        'spring.main.banner-mode': 'off',
        'spring.main.log-startup-info': 'false',
        // The primary takes the signals and stops the pool.
        'spring.main.register-shutdown-hook': 'false',
      },
    );
  } on Object catch (error, stackTrace) {
    start.toPrimary.send(['failed', '$error', '$stackTrace']);
    Isolate.exit();
  }
}

/// The pool of this application's server.
ServerIsolatePool createServerIsolatePool({
  required ServerIsolatesSettings settings,
  required WebServerStartStopLifecycle lifecycle,
  required IsolateReports reports,
  required IsolateLoadSampler sampler,
  PrimaryIsolate? Function()? primary,
  ApplicationLaunch? launch,
  IsolateScalingPolicy? policy,
  Iterable<IsolateLocalState> Function()? localState,
}) => ServerIsolatePool(
  settings: settings,
  lifecycle: lifecycle,
  reports: reports,
  sampler: sampler,
  primary: primary,
  launch: launch,
  policy: policy,
  localState: localState,
);

/// The pool's side in this isolate, which a pool started.
ServerIsolateWorker createServerIsolateWorker({
  required WebServerStartStopLifecycle lifecycle,
  required IsolateLoads loads,
  required IsolateReports reports,
}) => ServerIsolateWorker(lifecycle: lifecycle, loads: loads, reports: reports);

/// The pool of isolates that serve the port together
/// (`server.isolates.*`), in the application's first isolate: it starts
/// the others, each running the whole application, scales them
/// ([IsolateScaler]), restarts one that ends unexpectedly, shows them in
/// the task manager ([IsolateLoadSource]) and stops them with the
/// context.
///
/// The others are named `isolate-1`, `isolate-2`, … in the logs; the first
/// stays `main`. Each start, each scaling step, each failure is logged.
///
/// For server programs: a Flutter app that runs a server keeps its one
/// isolate (its widgets, assets and plugins exist only there), and the
/// pool says so instead of starting.
///
/// Spring has no counterpart: Tomcat's worker threads share the beans.
final class ServerIsolatePool
    with SmartLifecycle
    implements
        IsolateScaler,
        IsolateLoadSource,
        AsyncStartup,
        PrimaryIsolateHandler {
  /// The pool of the server [lifecycle] runs.
  ServerIsolatePool({
    required this.settings,
    required this.lifecycle,
    required this.reports,
    required this.sampler,
    this.primary,
    this.launch,
    IsolateScalingPolicy? policy,
    this.localState,
  }) : policy =
           policy ??
           LagScalingPolicy(
             scaleUpLag: settings.scaleUpLag,
             scaleUpAfter: settings.scaleUpAfter,
             scaleDownAfter: settings.scaleDownAfter,
           );

  /// `server.isolates.*`.
  final ServerIsolatesSettings settings;

  /// The first isolate's server: the pool starts after it and shares its
  /// port.
  final WebServerStartStopLifecycle lifecycle;

  /// Where the other isolates' reports are kept.
  final IsolateReports reports;

  /// The first isolate's own load, for the scaling policy.
  final IsolateLoadSampler sampler;

  /// Gives what answers the other isolates' questions for the first one
  /// ([PrimaryIsolate.ask]), looked up when one asks: the pool is one of
  /// its handlers, so it cannot be given at creation. `null`: they
  /// cannot ask.
  final PrimaryIsolate? Function()? primary;

  /// The name the pool answers under when another isolate scales it
  /// ([PrimaryIsolateHandler]): the request is `{to, reason}`.
  static const scaleHandlerId = 'isolates.scale';

  @override
  String get id => scaleHandlerId;

  @override
  Future<Object?> handle(Object? request) async {
    final asked = request! as Map<Object?, Object?>;
    return await scaleTo(
      (asked['to']! as num).toInt(),
      reason: '${asked['reason'] ?? 'manual'}',
    );
  }

  /// How the application is started in another isolate; `null` when it
  /// was not started in a way that can be repeated.
  final ApplicationLaunch? launch;

  /// Decides the size with `server.isolates.scaling: auto`.
  final IsolateScalingPolicy policy;

  /// The beans that keep state per isolate, asked for when the pool first
  /// has a second isolate and named in one warning.
  final Iterable<IsolateLocalState> Function()? localState;

  /// How long an isolate may take to start before it is given up.
  static const startTimeout = Duration(minutes: 2);

  /// How often the scaling policy looks.
  static const policyInterval = Duration(seconds: 2);

  final _isolates = <int, _ServerIsolate>{};
  final _clock = Stopwatch()..start();
  var _running = false;
  var _port = -1;
  var _warned = false;
  Completer<void> _started = Completer<void>()..complete();
  Future<void> _queue = Future<void>.value();
  Timer? _policyTimer;
  Duration? _scaledAt;
  Duration _askedAt = Duration.zero;
  // For the requests per second between two looks of the policy.
  (Duration, int)? _counted;
  // When isolates ended unexpectedly, to stop restarting a broken one.
  final _failures = <Duration>[];

  // The server starts first and stops last.
  @override
  int get phase => lifecycle.phase + 1;

  @override
  bool get isRunning => _running;

  @override
  int get count =>
      1 + _isolates.values.where((i) => i.serving && !i.draining).length;

  @override
  int get min => settings.least;

  @override
  int get max => settings.maxFor(Platform.numberOfProcessors);

  @override
  Future<void> awaitStartup() => _started.future;

  @override
  void start() {
    if (_running) {
      return;
    }
    _running = true;
    if (!settings.pooled) {
      return;
    }
    if (_isFlutter) {
      _log.warning(
        'server.isolates is ignored in a Flutter app: an isolate of the '
        'pool runs the whole application, and the widgets, the assets and '
        'the plugins of a Flutter app exist in its first isolate only.',
      );
      return;
    }
    reports.onRefresh = refresh;
    _started = Completer<void>();
    unawaited(_begin().whenComplete(_started.complete));
  }

  Future<void> _begin() async {
    final WebServer? server;
    try {
      server = await lifecycle.started;
    } on Object {
      return; // the server's own failure is reported by its lifecycle
    }
    if (server == null || !_running) {
      return; // no server (web-application-type=none, a mock environment)
    }
    _port = server.port;
    final initial = settings.countFor(Platform.numberOfProcessors);
    if (initial > 1) {
      try {
        await scaleTo(
          initial,
          reason: 'server.isolates.count=${settings.count}',
        );
      } on Object catch (error) {
        // The first isolate serves alone.
        _log.error('The pool of isolates did not start', error: error);
      }
    }
    if (_running && settings.scaling == IsolateScaling.auto) {
      _log.info(
        'Scaling the isolates automatically between $min and $max '
        '(${policy.runtimeType})',
      );
      _policyTimer = Timer.periodic(policyInterval, (_) => unawaited(_look()));
    }
  }

  @override
  Future<int> scaleBy(int delta, {String reason = 'manual'}) =>
      scaleTo(count + delta, reason: reason);

  @override
  Future<int> scaleTo(int count, {String reason = 'manual'}) {
    if (!settings.pooled) {
      throw StateError(
        'The server has no pool of isolates: its port is not shared. Set '
        'server.isolates.max (or server.isolates.count) above 1 to scale.',
      );
    }
    if (_isFlutter) {
      throw StateError('A Flutter app has no pool of server isolates.');
    }
    final result = _queue.then((_) => _apply(count, reason));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<int> _apply(int wanted, String reason) async {
    if (!_running || _port < 0) {
      return count;
    }
    final target = wanted < min ? min : (wanted > max ? max : wanted);
    final now = count;
    if (target == now) {
      return now;
    }
    if (target > now && launch == null) {
      throw StateError(
        'Isolates cannot be added: the application was not started in a '
        'way that can be repeated in another isolate. Start it with the '
        'generated runApplication(args), or pass what returns it: '
        'SpringApplication.run(args, hotReload: () => springApplication).',
      );
    }
    _log.info('Scaling $now → $target isolates ($reason)');
    _scaledAt = _clock.elapsed;
    if (target > now) {
      _warnLocalState();
      final free = <int>[];
      for (var index = 1; free.length < target - now; index++) {
        if (!_isolates.containsKey(index)) {
          free.add(index);
        }
      }
      await Future.wait(free.map(_spawn));
    } else {
      final newest = _isolates.values.where((i) => !i.draining).toList()
        ..sort((a, b) => b.index.compareTo(a.index));
      await Future.wait(newest.take(now - target).map(_drain));
    }
    _tellSize();
    return count;
  }

  // Every isolate knows how many serve: its IsolateScaler says so.
  void _tellSize() {
    final size = ['pool', count, min, max];
    for (final isolate in _isolates.values) {
      if (!isolate.draining) {
        isolate.commands?.send(size);
      }
    }
  }

  Future<void> _spawn(int index) async {
    final isolate = _ServerIsolate('isolate-$index', index);
    _isolates[index] = isolate;
    final watch = Stopwatch()..start();
    isolate.messages.listen((message) => _received(isolate, message));
    isolate.exits.listen((_) => _exited(isolate));
    isolate.errors.listen((Object? error) {
      final parts = error is List ? error : [error];
      _log.error(
        'Uncaught error in ${isolate.name}: ${parts.first}'
        '${parts.length > 1 ? '\n${parts[1]}' : ''}',
      );
    });
    try {
      isolate.isolate = await Isolate.spawn(
        _serverIsolateMain,
        _Start(
          launch!,
          isolate.name,
          index,
          _port,
          isolate.messages.sendPort,
        ),
        debugName: isolate.name,
        onExit: isolate.exits.sendPort,
        onError: isolate.errors.sendPort,
        errorsAreFatal: false,
      );
      await isolate.ready.future.timeout(startTimeout);
      _log.info(
        'Isolate ${isolate.name} ready in '
        '${watch.elapsedMilliseconds / 1000} seconds',
      );
    } on Object catch (error) {
      _log.error('Isolate ${isolate.name} failed to start', error: error);
      isolate.draining = true;
      isolate.isolate?.kill(priority: Isolate.immediate);
      _forget(isolate);
    }
  }

  Future<void> _drain(_ServerIsolate isolate) async {
    isolate.draining = true;
    final commands = isolate.commands;
    if (commands == null) {
      isolate.isolate?.kill(priority: Isolate.immediate);
      _forget(isolate);
      return;
    }
    _log.info('Draining isolate ${isolate.name}');
    commands.send(const ['stop']);
    await isolate.gone.future.timeout(
      settings.drainTimeout,
      onTimeout: () {
        _log.warning(
          'Isolate ${isolate.name} did not stop within '
          '${settings.drainTimeout.inSeconds} seconds '
          '(server.isolates.drain-timeout): stopped anyway',
        );
        isolate.isolate?.kill(priority: Isolate.immediate);
        _forget(isolate);
      },
    );
  }

  void _received(_ServerIsolate isolate, Object? message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    switch (message.first) {
      case 'ready':
        isolate
          ..commands = message[1] as SendPort
          ..serving = true;
        if (!isolate.ready.isCompleted) {
          isolate.ready.complete();
        }
        _tellSize();
      case 'failed':
        if (!isolate.ready.isCompleted) {
          isolate.ready.completeError('${message[1]}');
        }
      case 'ask':
        unawaited(_answer(isolate, message));
      case 'report':
        isolate.loads = [
          for (final load in message[1] as List)
            IsolateLoad.fromJson(load as Map<Object?, Object?>),
        ];
        reports.put(isolate.name, {
          for (final MapEntry(:key, :value)
              in (message[2] as Map<Object?, Object?>).entries)
            '$key': value,
        });
        final asked = isolate.asked;
        isolate.asked = null;
        asked?.complete();
    }
  }

  // A question of another isolate for the first one: `[ask, number, id,
  // request]`, answered `[answer, number, result]` or with the error's
  // text.
  Future<void> _answer(_ServerIsolate isolate, List<Object?> message) async {
    final number = message[1];
    // The way back comes with the question: an isolate may ask while it
    // starts, before the pool knows its port.
    final back = message[4]! as SendPort;
    try {
      final asking = primary?.call();
      if (asking == null) {
        throw StateError('The first isolate has no primaryIsolate bean');
      }
      final result = await asking.ask('${message[2]}', message[3]);
      back.send(['answer', number, result, null]);
    } on Object catch (error) {
      back.send(['answer', number, null, '$error']);
    }
  }

  void _exited(_ServerIsolate isolate) {
    final expected = isolate.draining || !_running;
    final served = isolate.serving;
    _forget(isolate);
    _tellSize();
    if (expected) {
      _log.info('Isolate ${isolate.name} stopped');
      return;
    }
    if (!served) {
      return; // its failed start is reported by the spawn
    }
    final now = _clock.elapsed;
    _failures
      ..removeWhere((at) => now - at > const Duration(minutes: 1))
      ..add(now);
    if (_failures.length > 3) {
      _log.error(
        'Isolate ${isolate.name} ended unexpectedly, the fourth in a '
        'minute: not started again. $count isolates serve.',
      );
      return;
    }
    // The requests it was answering get no answer: their connections stay
    // open until the VM collects the isolate, or the client gives up.
    _log.error('Isolate ${isolate.name} ended unexpectedly: starting it again');
    final index = isolate.index;
    _queue = _queue.then((_) async {
      if (_running && !_isolates.containsKey(index) && count < max) {
        await _spawn(index);
      }
    });
  }

  void _forget(_ServerIsolate isolate) {
    if (identical(_isolates[isolate.index], isolate)) {
      _isolates.remove(isolate.index);
    }
    reports.remove(isolate.name);
    isolate.close();
  }

  void _warnLocalState() {
    if (_warned) {
      return;
    }
    _warned = true;
    final kept = {
      for (final bean in localState?.call() ?? const <IsolateLocalState>[])
        bean.isolateLocalState,
    };
    if (kept.isEmpty) {
      return;
    }
    _log.warning(
      'Each isolate keeps its own ${kept.join(', ')} in memory, and a '
      'request may reach any isolate: what one keeps the others do not '
      'see. Keep it where all of them do (a database, a shared store), or '
      'accept one copy per isolate.',
    );
  }

  /// Asks every isolate for its load and reports, and completes when they
  /// have answered, or after a second without those that did not.
  Future<void> refresh() async {
    _askedAt = _clock.elapsed;
    final answers = <Future<void>>[];
    for (final isolate in _isolates.values) {
      final commands = isolate.commands;
      if (commands == null || isolate.draining) {
        continue;
      }
      final asked = isolate.asked ??= Completer<void>();
      commands.send(const ['report']);
      answers.add(asked.future);
    }
    await Future.wait(
      answers,
    ).timeout(const Duration(seconds: 1), onTimeout: () => const []);
  }

  @override
  List<IsolateLoad> loads() {
    // Read by a task manager every second or so: asked that often, the
    // isolates answer for the next read.
    if (_isolates.isNotEmpty &&
        _clock.elapsed - _askedAt >= const Duration(seconds: 1)) {
      unawaited(refresh());
    }
    final sorted = _isolates.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return [for (final isolate in sorted) ...isolate.loads];
  }

  // One look of the scaling policy; a look that fails is said and the
  // next one tried.
  Future<void> _look() async {
    try {
      await _decide();
    } on Object catch (error, stackTrace) {
      _log.warning(
        'The scaling of the isolates failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _decide() async {
    if (!_running) {
      return;
    }
    final since = _scaledAt;
    if (since != null && _clock.elapsed - since < settings.cooldown) {
      return;
    }
    await refresh();
    if (!_running) {
      return;
    }
    final own = sampler.load();
    final Object? server = lifecycle.webServer;
    final lags = <Duration>[?own.lag];
    final longest = <Duration>[?own.maxLag];
    var active = server is WebServerActivity ? server.activeRequests : 0;
    var requests = server is WebServerActivity ? server.requestCount : 0;
    for (final isolate in _isolates.values) {
      final load = isolate.loads
          .where((load) => load.name == isolate.name)
          .firstOrNull;
      if (load == null) {
        continue;
      }
      if (load.lag case final lag?) {
        lags.add(lag);
      }
      if (load.maxLag case final lag?) {
        longest.add(lag);
      }
      active += load.active ?? 0;
      requests += (load.details['requests'] as num?)?.toInt() ?? 0;
    }
    if (lags.isEmpty) {
      return; // nothing measured yet
    }
    final now = _clock.elapsed;
    final before = _counted;
    _counted = (now, requests);
    final seconds = before == null
        ? 0.0
        : (now - before.$1).inMicroseconds / Duration.microsecondsPerSecond;
    final lag = lags.reduce((a, b) => a + b) ~/ lags.length;
    final wanted = policy.decide(
      IsolateScalingState(
        count: count,
        min: min,
        max: max,
        lag: lag,
        maxLag: longest.isEmpty ? lag : longest.reduce((a, b) => a > b ? a : b),
        activeRequests: active,
        requestsPerSecond: before == null || seconds <= 0
            ? 0
            : (requests - before.$2).clamp(0, 1 << 62) / seconds,
      ),
      now,
    );
    if (wanted != null && wanted != count) {
      await scaleTo(
        wanted,
        reason: 'auto: lag ${lag.inMicroseconds / 1000} ms, $active in flight',
      );
    }
  }

  @override
  void stop() => stopWithCallback(() {});

  @override
  void stopWithCallback(void Function() callback) {
    _running = false;
    _policyTimer?.cancel();
    _policyTimer = null;
    reports.onRefresh = null;
    final leaving = _isolates.values.toList();
    if (leaving.isEmpty) {
      callback();
      return;
    }
    _log.info('Stopping ${leaving.length} isolates');
    unawaited(Future.wait(leaving.map(_drain)).whenComplete(callback));
  }
}

// An isolate the pool started.
final class _ServerIsolate {
  _ServerIsolate(this.name, this.index);

  final String name;
  final int index;
  final messages = ReceivePort();
  final exits = ReceivePort();
  final errors = ReceivePort();
  // Whoever waits for it hears of a failed start; nobody else has to.
  final ready = Completer<void>()..future.ignore();
  final gone = Completer<void>();
  Isolate? isolate;
  SendPort? commands;
  Completer<void>? asked;
  bool serving = false;
  bool draining = false;
  List<IsolateLoad> loads = const [];

  void close() {
    messages.close();
    exits.close();
    errors.close();
    serving = false;
    asked?.complete();
    asked = null;
    if (!ready.isCompleted) {
      ready.completeError(StateError('$name ended before it was ready'));
    }
    if (!gone.isCompleted) {
      gone.complete();
    }
  }
}

/// The pool's side in an isolate it started: tells the primary when the
/// server of this isolate listens, answers its questions (the load, the
/// reports of the [IsolateReporter] beans) and, told to stop, closes the
/// context (requests finish, `@PreDestroy` methods run) and ends the
/// isolate.
///
/// It is also this isolate's [IsolateScaler]: the pool lives in the first
/// isolate, and a step asked here is sent there
/// ([PrimaryIsolate.ask]).
final class ServerIsolateWorker
    with SmartLifecycle
    implements ApplicationContextAware, IsolateScaler {
  /// The worker of this isolate.
  ServerIsolateWorker({
    required this.lifecycle,
    required this.loads,
    required this.reports,
  });

  /// This isolate's server.
  final WebServerStartStopLifecycle lifecycle;

  /// This isolate's loads: its own row and those of its task executor.
  final IsolateLoads loads;

  /// This isolate's reports.
  final IsolateReports reports;

  ApplicationContext? _context;
  ReceivePort? _commands;
  var _running = false;
  // The pool as the first isolate last told it.
  var _count = 1;
  var _min = 1;
  var _max = 1;

  @override
  void setApplicationContext(ApplicationContext context) => _context = context;

  @override
  int get phase => lifecycle.phase + 1;

  @override
  bool get isRunning => _running;

  @override
  int get count => _count;

  @override
  int get min => _min;

  @override
  int get max => _max;

  @override
  Future<int> scaleBy(int delta, {String reason = 'manual'}) =>
      scaleTo(_count + delta, reason: reason);

  @override
  Future<int> scaleTo(int count, {String reason = 'manual'}) async {
    final link = _link;
    if (link == null) {
      throw StateError('Not an isolate of a server pool');
    }
    final result = await link.ask(ServerIsolatePool.scaleHandlerId, {
      'to': count,
      'reason': '$reason, asked in ${IsolateInfo.current.name}',
    });
    return (result! as num).toInt();
  }

  @override
  void start() {
    final link = _link;
    if (_running || link == null) {
      return;
    }
    _running = true;
    final commands = _commands = ReceivePort()..listen(_command);
    unawaited(
      lifecycle.started.then(
        (server) =>
            link.toPrimary.send(['ready', commands.sendPort, server?.port]),
        onError: (Object error) =>
            link.toPrimary.send(['failed', '$error', '']),
      ),
    );
  }

  void _command(Object? message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    switch (message.first) {
      case 'report':
        _link?.toPrimary.send([
          'report',
          [for (final load in loads.all()) load.toJson()],
          reports.own(),
        ]);
      case 'pool':
        _count = message[1] as int;
        _min = message[2] as int;
        _max = message[3] as int;
      case 'stop':
        unawaited(_leave());
    }
  }

  Future<void> _leave() async {
    _commands?.close();
    _commands = null;
    final context = _context;
    try {
      if (context is ConfigurableApplicationContext && context.isActive) {
        await context.closeAsync();
      }
    } finally {
      Isolate.exit();
    }
  }

  @override
  void stop() => _running = false;
}
