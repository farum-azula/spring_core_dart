// An application lists only the starter it chooses (roadmap/dependencies.md):
// for each starter, writes an application in a temporary directory whose
// `dependencies:` hold that starter alone (dev: build_runner, the
// generator, spring_boot_starter_test, test), uses in its code everything
// that comes with the starter — Spring annotations (spring_core_dart),
// `@SpringBootApplication` (spring_boot_dart), `@Log` and the log buffer
// (logging), the auto-configurations by name, the starter's own feature,
// the transport mocks of the test starter, a test class — and runs
// `dart pub get`, the generator, `dart analyze --fatal-infos` (with
// `depend_on_referenced_packages`) and `dart test`. Any failure, a
// warning included, fails the check.
//
//   dart run tool/check_app_dependencies.dart            # every starter
//   dart run tool/check_app_dependencies.dart feign cache  # some of them
//   dart run tool/check_app_dependencies.dart --keep     # keep the apps
//   dart run tool/check_app_dependencies.dart --flutter  # the Flutter starters
//
// With --flutter it writes a Flutter app per Flutter starter instead (it
// needs the Flutter SDK: CI runs it in the `flutter` job): the starter
// alone in `dependencies`, the same core, Boot and @Log code, the
// starter's feature (the HTTP client of spring_web_dart with the Flutter
// starter, the Material or Cupertino themes and app factory with a design
// starter, a screen with the navigation starter, a scene of a model of
// the properties with the scene starter, followed state with the signals
// starter, method security and
// `withMockUser` from `testing.dart` with the Flutter security starter),
// then `flutter pub get`, the generator, `flutter analyze --fatal-infos`
// and `flutter test`.
//
// The packages of this repository come by path (dependency_overrides), so
// the check is of the code as it is, before publishing.
import 'dart:io';

import 'version.dart' as family;

/// A starter checked: the package an application lists, and the code
/// using its own feature.
final class _Starter {
  const _Starter(
    this.package, {
    this.feature = '',
    this.featureTest = '',
    this.testImports = const [],
    this.properties = '',
    this.router = false,
  });

  /// The package name (`spring_boot_starter_feign`).
  final String package;

  /// `lib/src/feature.dart` after the imports: the starter's own feature.
  final String feature;

  /// Test statements using the feature (in `main` of the test, after
  /// `app`).
  final String featureTest;

  /// More lines of the application's `application.properties`: what the
  /// feature needs to start (the address of a project).
  final String properties;

  /// More libraries the test imports (the starter's test support).
  final List<String> testImports;

  /// Whether a Flutter starter brings the router: its app shows the
  /// feature's `@ScreenRoute` screen, and no `home` of its own.
  final bool router;

  String get short => package.replaceFirst('spring_boot_starter_', '');

  String get library => 'package:$package/$package.dart';
}

const _starters = [
  _Starter('spring_boot_starter_logging'),
  _Starter(
    'spring_boot_starter_cache',
    feature: '''
@Service()
class Prices {
  var computed = 0;

  @Cacheable('prices')
  Future<double> price(String isbn) async {
    computed++;
    return 12.5;
  }
}
''',
    featureTest: '''
  test('@Cacheable works', () async {
    final prices = app.getBean<Prices>();
    await prices.price('1');
    await prices.price('1');
    expect(prices.computed, 1);
  });
''',
  ),
  // No database driver: the repositories keep their data in memory, so the
  // check needs nothing but the starter (an application on SQLite or
  // PostgreSQL also lists `sqlite3` or `postgres` itself).
  _Starter(
    'spring_boot_starter_data',
    feature: '''
@Table('books')
class Book {
  Book({required this.title, this.id});

  @Id()
  int? id;

  String title;
}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}

@Service()
class Shelf {
  Shelf(this.books);

  final BookRepository books;

  @Transactional()
  Future<void> add(String title) async {
    await books.save(Book(title: title));
  }
}
''',
    featureTest: '''
  test('repositories and @Transactional come with the starter', () async {
    await app.getBean<Shelf>().add('Dune');
    final found = await app.getBean<BookRepository>().findByTitle('Dune');
    expect(found, hasLength(1));
  });
''',
  ),
  _Starter(
    'spring_boot_starter_scheduling',
    feature: r'''
@Component()
class Ticks {
  var ticks = 0;

  @Scheduled(fixedDelayString: r'${ticks.delay:1h}')
  void tick() => ticks++;
}
''',
    featureTest: '''
  test('@Scheduled beans and the TaskScheduler come with the starter', () {
    expect(app.getBean<Ticks>().ticks, greaterThanOrEqualTo(0));
    expect(app, hasSingleBean<TaskScheduler>());
  });
''',
  ),
  _Starter(
    'spring_boot_starter_feign',
    feature: r'''
@FeignClient('books', url: r'${books.url:http://books.test}')
abstract interface class BooksClient {
  @GetMapping('/books/{isbn}')
  Future<Map<String, Object?>> find(@PathVariable() String isbn);
}
''',
    featureTest: '''
  group('MockHttpTransport from the test starter', () {
    final server = MockHttpTransport()
      ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'});
    final books = springBootTest(
      springApplication,
      overrides: [BeanOverride<HttpTransport>(server)],
    );

    test('the client goes through it', () async {
      expect(await books.getBean<BooksClient>().find('1'), {'isbn': '1'});
    });
  });
''',
  ),
  _Starter(
    'spring_boot_starter_websocket',
    feature: r'''
@WebSocketClient('chat', url: r'${chat.url:ws://chat.test/ws}')
abstract interface class ChatSocket {
  @OnMessage()
  Stream<String> messages();

  @SendMessage()
  Future<void> send(String message);
}
''',
    featureTest: '''
  test('MockWebSocketTransport from the test starter', () {
    expect(MockWebSocketTransport(), isA<WebSocketTransport>());
    expect(app, hasSingleBean<ChatSocket>());
  });
''',
  ),
  _Starter(
    'spring_boot_starter_supabase',
    // A declared function or bucket needs the project it belongs to.
    properties:
        'spring.supabase.url=https://abcd.supabase.co\n'
        'spring.supabase.anon-key=anon-key\n',
    feature: '''
@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('hello')
  Future<Map<String, Object?>> hello(@RequestBody() Map<String, Object?> body);
}

@StorageBucket('avatars')
abstract interface class Avatars {
  @PublicUrl('{userId}/avatar.png')
  Uri link(String userId);
}
''',
    featureTest: r'''
  group('Supabase through the MockHttpTransport of the test starter', () {
    final server = MockHttpTransport()
      ..when(HttpMethod.post, '/functions/v1/hello')
          .respond(200, json: {'message': 'Hello'});
    final supabase = springBootTest(
      springApplication,
      properties: {
        'spring.supabase.url': 'https://abcd.supabase.co',
        'spring.supabase.anon-key': 'anon-key',
      },
      overrides: [BeanOverride<HttpTransport>(server)],
    );

    test('a function and a bucket come with the starter', () async {
      expect(
        await supabase.getBean<Functions>().hello({'name': 'Ada'}),
        {'message': 'Hello'},
      );
      expect(
        '${supabase.getBean<Avatars>().link('u1')}',
        'https://abcd.supabase.co/storage/v1/object/public/avatars/u1/avatar.png',
      );
    });
  });
''',
  ),
  _Starter(
    'spring_boot_starter_web',
    feature: r'''
class Greeting {
  const Greeting({required this.text});
  final String text;
}

@RestController()
@RequestMapping('/api/greetings')
class GreetingController {
  @GetMapping('/{name}')
  Greeting greet(@PathVariable() String name) => Greeting(text: 'Hello, $name');
}
''',
    featureTest: '''
  test('@RestController through MockMvc from the test starter', () async {
    await app.mockMvc
        .get('/api/greetings/Ada')
        .andExpect(status: 200, json: {'text': 'Hello, Ada'});
    expect(app, hasSingleBean<GreetingController>());
  });
''',
  ),
  _Starter(
    'spring_boot_starter_edge',
    feature: '''
@RestController()
class TasksController {
  TasksController(this.runtime);
  final EdgeRuntime runtime;

  @PostMapping('/tasks')
  String accept() {
    runtime.waitUntil(Future<void>.value());
    return runtime.platform ?? 'server';
  }
}
''',
    featureTest: '''
  test('the web starter comes with it, and the runtime bean', () async {
    await app.mockMvc.post('/tasks').andExpect(status: 200, body: 'server');
    expect(app, hasSingleBean<EdgeRuntime>());
    expect(app, hasSingleBean<TasksController>());
  });
''',
  ),
  _Starter(
    'spring_boot_starter_oauth2_client',
    feature: '''
@Service()
class Partner {
  Partner(this.authorizedClients);
  // Only with a registration.
  final OAuth2AuthorizedClientManager? authorizedClients;
}
''',
    featureTest: '''
  group('the OAuth2 client from the properties', () {
    final sso = springBootTest(
      springApplication,
      properties: {
        'greeting.name': 'Ada',
        'spring.security.oauth2.client.registration.github.client-id': 'gh',
      },
      overrides: [BeanOverride<HttpTransport>(MockHttpTransport())],
    );

    test('registrations, the authorized clients and their manager', () async {
      final github = await sso
          .getBean<ClientRegistrationRepository>()
          .findByRegistrationId('github');
      expect(github?.clientId, 'gh');
      expect(sso.getBean<Partner>().authorizedClients, isNotNull);
      expect(
        sso.getBean<OAuth2AuthorizedClientService>(),
        isA<InMemoryOAuth2AuthorizedClientService>(),
      );
      expect(sha256Base64Url('x'), hasLength(43));
    });
  });
''',
  ),
  _Starter(
    'spring_boot_starter_actuator',
    feature: '''
@Component()
class InboxHealthIndicator extends HealthIndicator {
  @override
  Future<Health> health() async =>
      Health.up().withDetail('pending', 3).build();
}
''',
    featureTest: '''
  test('/actuator/health through the web starter, with an indicator', () async {
    await app.mockMvc
        .get('/actuator/health')
        .andExpect(status: 200, json: {'status': 'UP'});
    expect(app, hasSingleBean<InboxHealthIndicator>());
  });
''',
  ),
  _Starter(
    'spring_boot_starter_security',
    testImports: ['package:spring_boot_starter_security/testing.dart'],
    feature: '''
@RestController()
@RequestMapping('/api')
class MeController {
  @GetMapping('/me')
  String me(Authentication authentication) => authentication.name;
}

@Service()
class Reports {
  @PreAuthorize("hasRole('ADMIN')")
  Future<String> monthly() async => 'report';
}

@Configuration()
class SecurityConfig {
  @Bean()
  SecurityFilterChain filterChain(HttpSecurity http) => http
      .authorizeHttpRequests((auth) => auth.anyRequest().authenticated())
      .httpBasic()
      .build();

  @Bean()
  UserDetailsService users() => InMemoryUserDetailsManager([
    User.withUsername('ada').password('{noop}secret').roles(['USER']).build(),
  ]);
}
''',
    featureTest: '''
  test('the filter chain, users, method security and the test helpers',
      () async {
    await app.mockMvc.get('/api/me').andExpect(status: 401);
    await app.mockMvc
        .perform(MockRequestBuilder(HttpMethod.get, '/api/me')
          ..with_(httpBasic('ada', 'secret')))
        .andExpect(status: 200, body: 'ada');
    await expectLater(
      withMockUser(() => app.getBean<Reports>().monthly()),
      throwsA(isA<AccessDeniedException>()),
    );
    expect(
      await withMockUser(
        () => app.getBean<Reports>().monthly(),
        roles: ['ADMIN'],
      ),
      'report',
    );
  });
''',
  ),
];

/// The Flutter starters, checked with `--flutter`.
const _flutterStarters = [
  _Starter(
    'spring_boot_starter_flutter',
    feature: '''
// spring_web_dart comes with the starter: an app sending its own requests
// declares its transport without another dependency.
@Configuration()
class Network {
  @Bean()
  HttpTransport httpTransport() => platformHttpTransport();
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => const Text('home');
}
''',
    featureTest: '''
  test('spring_web_dart comes with the starter', () {
    expect(app, hasSingleBean<Network>());
    expect(app.getBean<HttpTransport>(), isA<HttpTransport>());
  });
''',
  ),
  // No design library in the app's pubspec: the starter's beans and the
  // app type are enough for a MaterialApp around a widget of its own.
  _Starter(
    'spring_boot_starter_flutter_material',
    properties: 'spring.flutter.app.type=material\n',
    feature: '''
class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => const Text('home');
}

@Component()
class Palette {
  Palette(this.themes);

  final MaterialThemes themes;
}
''',
    featureTest: '''
  test('Material comes with the starter', () {
    expect(app.getBean<Palette>().themes, isA<MaterialThemes>());
    expect(app.getBean<MaterialAppFactory>(), isA<SpringAppFactory>());
    expect(const Home().key, isNull);
  });
''',
  ),
  _Starter(
    'spring_boot_starter_flutter_cupertino',
    properties: 'spring.flutter.app.type=cupertino\n',
    feature: '''
class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => const Text('home');
}

@Component()
class Palette {
  Palette(this.themes);

  final CupertinoThemes themes;
}
''',
    featureTest: '''
  test('Cupertino comes with the starter', () {
    expect(app.getBean<Palette>().themes, isA<CupertinoThemes>());
    expect(app.getBean<CupertinoAppFactory>(), isA<SpringAppFactory>());
    expect(const Home().key, isNull);
  });
''',
  ),
  _Starter(
    'spring_boot_starter_flutter_navigation',
    router: true,
    feature: '''
@ScreenRoute('/', title: 'Home')
class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => Text(context.route.uri.path);
}
''',
    featureTest: '''
  test('the screens come with the starter', () {
    expect(app.getBean<RouteTemplate>(), isA<RouteTemplate>());
    expect(const Home().key, isNull);
  });
''',
  ),
  // signals_core is not in the app's pubspec: the annotations, the
  // widgets and `untracked` come with the starter.
  _Starter(
    'spring_boot_starter_flutter_signals',
    feature: r'''
@Component()
class Basket {
  @Signal()
  List<String> items = [];

  @Signal()
  String? coupon;

  @Computed()
  int get count => items.length;

  int saved = -1;

  @Effect()
  void save() {
    untracked(() => coupon);
    saved = count;
  }

  void add(String item) => items.add(item);
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) =>
      Watch((context) => Text('${context.bean<Basket>().count}'));
}
''',
    featureTest: '''
  test('followed state comes with the starter', () {
    final basket = app.getBean<Basket>()..add('Dune');
    expect(basket.count, 1);
    expect(basket.saved, 1);
    expect(app.getBean<SignalBeans>().find(basket), isNotNull);
    expect(const Home().key, isNull);
  });
''',
  ),
  // flutter_scene is not in the app's pubspec: the starter's own scene
  // widgets and beans are enough for a scene of the properties' models.
  _Starter(
    'spring_boot_starter_flutter_scene',
    properties:
        'spring.flutter.scene.models.hero.source=asset:assets/hero.glb\n',
    feature: '''
class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => const SpringSceneView.declarative(
    placeholder: Text('home'),
    children: [SpringSceneModel('hero')],
  );
}

@Component()
class Showroom {
  Showroom(this.models);

  final ObjectProvider<SceneModels> models;
}
''',
    featureTest: '''
  test('the scenes come with the starter', () {
    final models = app.getBean<Showroom>().models.getObject();
    expect(models['hero'].state, SceneModelState.idle);
    expect(app.getBean<SceneEngine>().state, SceneEngineState.idle);
    expect(const Home().key, isNull);
  });
''',
  ),
  _Starter(
    'spring_boot_starter_flutter_security',
    router: true,
    testImports: ['package:spring_boot_starter_flutter_security/testing.dart'],
    feature: '''
@Service()
class Reports {
  @PreAuthorize("hasRole('ADMIN')")
  Future<String> monthly() async => 'report';
}

@ScreenRoute('/', title: 'Home')
class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) => const Text('home');
}
''',
    featureTest: '''
  test('method security and withMockUser from testing.dart', () async {
    await expectLater(
      withMockUser(() => app.getBean<Reports>().monthly()),
      throwsA(isA<AccessDeniedException>()),
    );
    expect(
      await withMockUser(
        () => app.getBean<Reports>().monthly(),
        roles: ['ADMIN'],
      ),
      'report',
    );
  });
''',
  ),
];

Future<void> main(List<String> args) async {
  final repository = File.fromUri(Platform.script).parent.parent.absolute.path;
  final keep = args.contains('--keep');
  final flutter = args.contains('--flutter');
  final wanted = args.where((a) => !a.startsWith('--')).toSet();
  final starters = [
    for (final starter in flutter ? _flutterStarters : _starters)
      if (wanted.isEmpty || wanted.contains(starter.short)) starter,
  ];
  final failures = <String>[];
  for (final starter in starters) {
    final directory = Directory.systemTemp.createTempSync(
      'app_${starter.short}_',
    );
    (flutter ? _writeFlutter : _write)(directory.path, repository, starter);
    stdout.writeln('== ${starter.package}: ${directory.path}');
    final steps = flutter
        ? [
            ['flutter', 'pub', 'get'],
            ['dart', 'run', 'build_runner', 'build'],
            ['flutter', 'analyze', '--fatal-infos', '--fatal-warnings'],
            ['flutter', 'test'],
          ]
        : [
            ['dart', 'pub', 'get'],
            ['dart', 'run', 'build_runner', 'build'],
            ['dart', 'analyze', '--fatal-infos', '--fatal-warnings'],
            ['dart', 'test'],
          ];
    for (final step in steps) {
      final result = Process.runSync(
        step.first,
        step.skip(1).toList(),
        workingDirectory: directory.path,
      );
      final ok = result.exitCode == 0;
      stdout.writeln('  ${ok ? 'ok  ' : 'FAIL'} ${step.join(' ')}');
      if (!ok) {
        failures.add('${starter.package}: ${step.join(' ')}');
        stdout
          ..writeln(result.stdout)
          ..writeln(result.stderr);
        break;
      }
    }
    if (!keep) {
      directory.deleteSync(recursive: true);
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln('\nFailed:\n${failures.map((f) => '  $f').join('\n')}');
    exit(1);
  }
  stdout.writeln(
    '\nEvery starter is the only dependency its application needs.',
  );
}

void _write(String directory, String repository, _Starter starter) {
  void file(String path, String text) => File('$directory/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  // The Flutter packages need the Flutter SDK, which a Dart application
  // cannot resolve, even as an unused override.
  final overrides = [
    for (final package in family.family)
      if (!package.startsWith('spring_boot_starter_flutter'))
        '  $package:\n    path: $repository/$package',
  ].join('\n');
  file('pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: ^3.13.0

dependencies:
  ${starter.package}: any

dev_dependencies:
  build_runner: ^2.17.0
  spring_boot_starter_test: any
  spring_core_dart_generator: any
  test: ^1.33.0

dependency_overrides:
$overrides
''');
  file('analysis_options.yaml', '''
linter:
  rules:
    - depend_on_referenced_packages
''');
  file(
    'lib/resources/application.properties',
    'greeting.name=World\n${starter.properties}',
  );
  file('lib/app.dart', '''
import '${starter.library}';

import 'spring_gen/app.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''');
  file('bin/main.dart', '''
import 'package:app/app.dart' as app;

void main(List<String> args) => app.main(args);
''');
  file(
    'lib/src/greeter.dart',
    r'''
import 'package:STARTER';

import 'package:app/spring_gen/app.spring.dart';

/// spring_core_dart's annotations, the logger of @Log.
@Service()
@Log(topic: 'app.greeter')
class Greeter {
  Greeter(@Value(r'${greeting.name}') this.name);

  final String name;

  String greet() {
    log.info('greeting $name');
    return 'Hello, $name';
  }
}
'''
        .replaceFirst('package:STARTER', starter.library),
  );
  if (starter.feature.isNotEmpty) {
    file(
      'lib/src/feature.dart',
      "import '${starter.library}';\n\n${starter.feature}",
    );
  }
  file('test/app_test.dart', '''
import '${starter.library}';
import 'package:${starter.package}/spring_auto_configuration.dart';
import 'package:app/spring_gen/app.spring.dart';
import 'package:app/src/greeter.dart';
${starter.feature.isEmpty ? '' : "import 'package:app/src/feature.dart';"}
${starter.testImports.map((library) => "import '$library';").join('\n')}
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';
void main() {
  final logs = captureLogs();
  final app = springBootTest(
    springApplication,
    properties: {'greeting.name': 'Ada'},
  );

  test('core, Boot and @Log come with the starter', () {
    expect(app.getBean<Greeter>().greet(), 'Hello, Ada');
    expect(logs.messages, contains('greeting Ada'));
    expect(app, hasSingleBean<LogBuffer>());
  });

  test('the auto-configurations by name', () {
    const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
        .run((context) => expect(context, hasSingleBean<LogBuffer>()));
  });

${starter.featureTest}}
''');
  file('test/greeter_class_test.dart', '''
import 'package:app/src/greeter.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'spring_gen/greeter_class.test.spring.dart';

@SpringBootTest(properties: {'greeting.name': 'Bo'})
class GreeterTest {
  @Autowired()
  late Greeter greeter;

  @Test()
  void greets() => expect(greeter.greet(), 'Hello, Bo');
}

void main() => runSpringTests();
''');
}

/// A Flutter app on [starter] alone, in [directory].
void _writeFlutter(String directory, String repository, _Starter starter) {
  void file(String path, String text) => File('$directory/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  final overrides = [
    for (final package in family.family)
      '  $package:\n    path: $repository/$package',
  ].join('\n');
  file('pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: ^3.13.0

dependencies:
  flutter:
    sdk: flutter
  ${starter.package}: any

dev_dependencies:
  build_runner: ^2.17.0
  flutter_test:
    sdk: flutter
  spring_boot_starter_test: any
  spring_core_dart_generator: any

dependency_overrides:
$overrides
''');
  file('analysis_options.yaml', '''
linter:
  rules:
    - depend_on_referenced_packages
''');
  file(
    'lib/resources/application.properties',
    'greeting.name=World\n${starter.properties}',
  );
  final router = starter.router;
  file('lib/main.dart', '''
import 'package:flutter/widgets.dart';
import '${starter.library}';

${router ? '' : "import 'package:app/src/feature.dart';\n"}import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,${router ? '' : '\n    home: const Home(),'}
  ),
);
''');
  file(
    'lib/src/greeter.dart',
    r'''
import 'package:STARTER';

import 'package:app/spring_gen/main.spring.dart';

/// spring_core_dart's annotations, the logger of @Log.
@Service()
@Log(topic: 'app.greeter')
class Greeter {
  Greeter(@Value(r'${greeting.name}') this.name);

  final String name;

  String greet() {
    log.info('greeting $name');
    return 'Hello, $name';
  }
}
'''
        .replaceFirst('package:STARTER', starter.library),
  );
  file(
    'lib/src/feature.dart',
    "import 'package:flutter/widgets.dart';\n"
        "import '${starter.library}';\n\n${starter.feature}",
  );
  file('test/app_test.dart', '''
import 'package:app/spring_gen/main.spring.dart';
import 'package:app/src/feature.dart';
import 'package:app/src/greeter.dart';
import 'package:flutter_test/flutter_test.dart';
import '${starter.library}';
${starter.testImports.map((library) => "import '$library';").join('\n')}
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    hide Size;

void main() {
  final app = springBootTest(
    springApplication,
    properties: {'greeting.name': 'Ada'},
  );

  test('core, Boot and @Log come with the starter', () {
    expect(app.getBean<Greeter>().greet(), 'Hello, Ada');
    expect(app, hasSingleBean<LogBuffer>());
  });

${starter.featureTest}}
''');
}
