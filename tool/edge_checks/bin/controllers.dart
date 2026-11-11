import 'dart:async';
import 'dart:typed_data';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';

@RestController()
class PublicController {
  PublicController(this.runtime, this.environment);

  final EdgeRuntime runtime;
  final Environment environment;

  static var _later = 0;

  @GetMapping('/hello')
  Map<String, Object?> hello(
    ServerHttpRequest request, {
    @RequestParam() String name = 'world',
  }) => {
    'message': 'hello $name',
    'platform': runtime.platform,
    'remote': request.remoteAddress,
    'greeting': environment.getProperty('greeting'),
    'path': request.path,
    'secure': request.isSecure,
  };

  @PostMapping('/echo')
  Map<String, Object?> echo(
    @RequestBody() Map<String, Object?> body,
    @RequestHeader('x-trace') String? trace,
  ) => {'body': body, 'trace': trace};

  @PostMapping('/size')
  Future<Map<String, Object?>> size(ServerHttpRequest request) async => {
    'bytes': (await request.readBodyBytes()).length,
  };

  @PostMapping('/upload')
  Future<Map<String, Object?>> upload(
    @RequestPart('file') MultipartFile file,
    @RequestParam() String title,
  ) async => {
    'name': file.originalFilename,
    'size': (await file.bytes).length,
    'title': title,
  };

  @GetMapping('/events')
  Stream<Map<String, Object?>> events() async* {
    for (var i = 1; i <= 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      yield {'tick': i};
    }
  }

  @GetMapping('/download')
  Uint8List download() => Uint8List.fromList([0, 159, 146, 150, 255, 1, 2]);

  @GetMapping('/cookies')
  ResponseEntity<String> cookies(ServerHttpResponse response) {
    response
      ..addCookie(ResponseCookie('a', '1', path: '/', httpOnly: true))
      ..addCookie(ResponseCookie('b', '2', path: '/'));
    return ResponseEntity.ok('set');
  }

  @GetMapping('/nothing')
  ResponseEntity<void> nothing() => ResponseEntity.noContent().build();

  @GetMapping('/boom')
  String boom() => throw StateError('a secret detail');

  @GetMapping('/bad-header')
  ResponseEntity<String> badHeader() =>
      ResponseEntity.status(200).header('x-bad', ['line\nbreak']).body('never');

  // Several things at once that cannot be sent.
  @GetMapping('/bad-headers')
  ResponseEntity<String> badHeaders(ServerHttpResponse response) {
    response.addCookie(ResponseCookie('c', 'ok'));
    return ResponseEntity.status(200)
        .header('x-bad-1', ['line\nbreak'])
        .header('x-bad-2', ['caf\u00e9'])
        .header('x-bad-3', ['\u0001'])
        .body('never');
  }

  // A body as long as the client reads: a megabyte a chunk.
  @GetMapping('/endless')
  Stream<List<int>> endless() async* {
    final chunk = Uint8List(1024 * 1024);
    for (var i = 0; i < 4096; i++) {
      produced++;
      yield chunk;
    }
  }

  /// The chunks [endless] has produced.
  static int produced = 0;

  @GetMapping('/produced')
  int producedCount() => produced;

  @PostMapping('/later')
  String later() {
    runtime.waitUntil(
      Future<void>.delayed(
        const Duration(milliseconds: 150),
      ).then((_) => _later++),
    );
    return 'accepted';
  }

  @GetMapping('/later')
  int laterCount() => _later;

  @GetMapping('/limited')
  @RateLimiter('2/1m', key: "#{headers['x-client']}")
  String limited() => 'ok';

  @GetMapping('/files/{name}')
  String file(@PathVariable() String name) => 'file $name';
}

@RestController()
@RequestMapping('/api')
class AccountController {
  AccountController(this.reports);

  final AdminReports reports;

  @GetMapping('/me')
  Map<String, Object?> me(Authentication authentication) => {
    'name': authentication.name,
    'authorities': [for (final a in authentication.authorities) a.authority],
  };

  @GetMapping('/admin')
  String admin() => reports.all();
}

/// What does NOT suit a function, here so that the tests see the starter
/// warn about it: a method on a timer (it does not run between requests)
/// and values cached in the memory of one short-lived instance. Do not
/// copy it: a schedule is an `EdgeScheduledHandler`, shared values belong
/// in a store.
@Service()
class Rates {
  var _loads = 0;

  @Scheduled(fixedRateString: '1h', initialDelayString: '1h')
  void refresh() => _loads = 0;

  @Cacheable('rates')
  int rate(String currency) => ++_loads;
}

@RestController()
class RatesController {
  RatesController(this.rates);

  final Rates rates;

  // The same answer for a currency while the instance lives.
  @GetMapping('/rates/{currency}')
  int rate(@PathVariable() String currency) => rates.rate(currency);
}

/// What the platform's schedule ran (a Cloudflare cron trigger, an
/// EventBridge schedule).
@Component()
class ScheduleLog implements EdgeScheduledHandler {
  final seen = <String>[];

  @override
  Future<void> onScheduled(EdgeScheduledEvent event) async {
    if (event.schedule == 'fail') {
      throw StateError('the scheduled work failed');
    }
    seen.add('${event.platform}:${event.schedule}');
  }
}

/// A Worker's bindings: the KV namespace `SETTINGS` and the D1 database
/// `DB` (not there on the other platforms: the bean is missing).
@RestController()
class BindingsController {
  BindingsController(this.schedule, this.bindings, this.warnings);

  final ScheduleLog schedule;
  final CloudflareBindings? bindings;
  final EdgeWarnings? warnings;

  /// What the starter said at start about this application.
  @GetMapping('/warnings')
  List<String> warned() => warnings?.found ?? const [];

  CloudflareBindings get _bindings =>
      bindings ??
      (throw ResponseStatusException(HttpStatus.notFound, 'Not a Worker'));

  @GetMapping('/scheduled')
  List<String> scheduled() => schedule.seen;

  @PutMapping('/kv/{key}')
  Future<List<String>> put(
    @PathVariable() String key,
    @RequestBody() String value,
  ) async {
    final settings = _bindings.kv('SETTINGS');
    await settings.put(key, value);
    return await settings.keys(prefix: key);
  }

  @GetMapping('/kv/{key}')
  Future<Map<String, Object?>> get(@PathVariable() String key) async => {
    'value': await _bindings.kv('SETTINGS').get(key),
    'missing': await _bindings.kv('SETTINGS').get('$key-missing'),
    'bound': [_bindings.has('SETTINGS'), _bindings.has('NOPE')],
  };

  @PostMapping('/d1/notes')
  Future<Map<String, Object?>> note(@RequestBody() String text) async {
    final db = _bindings.d1('DB');
    await db.execute(
      'create table if not exists notes '
      '(id integer primary key, text text not null, pinned integer)',
    );
    final changed = await db.execute(
      'insert into notes (text, pinned) values (?1, ?2)',
      [text, null],
    );
    return {
      'changed': changed,
      'notes': await db.query(
        'select text, pinned from notes where text = ?1',
        [text],
      ),
    };
  }

  // The buckets of the rate limiter, when it counts in D1.
  @GetMapping('/d1/buckets')
  Future<List<Map<String, Object?>>> buckets() =>
      _bindings.d1('DB').query('select key, allowed from rate_limit');
}

@Service()
class AdminReports {
  @PreAuthorize("hasRole('ADMIN')")
  String all() => 'every report';
}

@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain apiChain(HttpSecurity http) => http
      .authorizeHttpRequests(
        (auth) => auth
            .requestMatchers('/api/**')
            .authenticated()
            .anyRequest()
            .permitAll(),
      )
      .sessionManagement(
        (session) =>
            session.sessionCreationPolicy(SessionCreationPolicy.stateless),
      )
      .csrf((csrf) => csrf.disable())
      .oauth2ResourceServer((server) => server.jwt())
      .build();
}
