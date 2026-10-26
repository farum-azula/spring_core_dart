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
//
// The packages of this repository come by path (dependency_overrides), so
// the check is of the code as it is, before publishing.
import 'dart:io';

import 'version.dart' as family;

/// A starter checked: the package an application lists, and the code
/// using its own feature.
final class _Starter {
  const _Starter(this.package, {this.feature = '', this.featureTest = ''});

  /// The package name (`spring_boot_starter_feign`).
  final String package;

  /// `lib/src/feature.dart` after the imports: the starter's own feature.
  final String feature;

  /// Test statements using the feature (in `main` of the test, after
  /// `app`).
  final String featureTest;

  String get short => package.replaceFirst('spring_boot_starter_', '');

  String get library => 'package:$package/$package.dart';
}

const _starters = [
  _Starter('spring_boot_starter_logging'),
  _Starter(
    'spring_boot_starter_cache',
    feature: r'''
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
    featureTest: r'''
  test('@Cacheable works', () async {
    final prices = app.getBean<Prices>();
    await prices.price('1');
    await prices.price('1');
    expect(prices.computed, 1);
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
    featureTest: r'''
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
    featureTest: r'''
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
    featureTest: r'''
  test('MockWebSocketTransport from the test starter', () {
    expect(MockWebSocketTransport(), isA<WebSocketTransport>());
    expect(app, hasSingleBean<ChatSocket>());
  });
''',
  ),
];

Future<void> main(List<String> args) async {
  final repository = File.fromUri(Platform.script).parent.parent.absolute.path;
  final keep = args.contains('--keep');
  final wanted = args.where((a) => !a.startsWith('--')).toSet();
  final starters = [
    for (final starter in _starters)
      if (wanted.isEmpty || wanted.contains(starter.short)) starter,
  ];
  final failures = <String>[];
  for (final starter in starters) {
    final directory = Directory.systemTemp.createTempSync(
      'app_${starter.short}_',
    );
    _write(directory.path, repository, starter);
    stdout.writeln('== ${starter.package}: ${directory.path}');
    final steps = [
      ['dart', 'pub', 'get'],
      ['dart', 'run', 'build_runner', 'build', '--delete-conflicting-outputs'],
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

  final overrides = [
    for (final package in family.family)
      if (package != 'spring_boot_starter_flutter')
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
  file('lib/resources/application.properties', 'greeting.name=World\n');
  file('lib/app.dart', '''
import '${starter.library}';

import 'app.spring.dart';

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

import 'package:app/app.spring.dart';

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
import 'package:app/app.spring.dart';
import 'package:app/src/greeter.dart';
${starter.feature.isEmpty ? '' : "import 'package:app/src/feature.dart';"}
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

import 'spring/greeter_class.test.spring.dart';

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
