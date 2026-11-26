// An application's own segments, panes and commands of the debug console
// (`@ConsoleSegment`, `@ConsolePane`, `@ConsoleCommand`): beans with
// constructor injection, registered only in the application's debug part
// (`main.spring.debug.dart`) under the console's build switches, so a
// build without them refers to the class nowhere: a segment only when
// `segments` names it or holds `*`, a pane only when `panes` does, a
// command only with the `commands` pane. A bean of the app that injects
// one fails the build, and so does a segment's or a pane's bean without
// the annotation that names it. Built next to a stub
// `spring_boot_starter_flutter` with only the console's declarations.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _stubs = {
  'spring_boot_starter_flutter|lib/spring_boot_starter_flutter.dart': '''
export 'src/debug/console/console_annotations.dart';
export 'src/debug/console/debug_console_command.dart';
export 'src/debug/console/debug_console_pane.dart';
export 'src/debug/console/debug_console_segment.dart';
''',
  'spring_boot_starter_flutter|lib/src/debug/console/console_annotations.dart':
      '''
import 'package:spring_core_dart/spring_core_dart.dart';

class ConsoleSegment extends Component implements Order {
  const ConsoleSegment(this.segment, {int order = 0}) : value = order;
  final String segment;
  @override
  final int value;
}

class ConsoleCommand extends Component implements Order {
  const ConsoleCommand(this.command, {int order = 0}) : value = order;
  final String command;
  @override
  final int value;
}

class ConsolePane extends Component implements Order {
  const ConsolePane(this.pane, {int order = 0}) : value = order;
  final String pane;
  @override
  final int value;
}
''',
  'spring_boot_starter_flutter|lib/src/debug/console/debug_console_pane.dart':
      '''
abstract class DebugConsolePane {
  const DebugConsolePane();
  String? get name => null;
  String get title;
  Object build(Object context, Object console);
}
''',
  'spring_boot_starter_flutter|lib/src/debug/console/debug_console_segment.dart':
      '''
abstract class DebugConsoleSegment {
  const DebugConsoleSegment();
  String? get name => null;
  void Function() start(void Function() changed);
  Object? read();
}
''',
  'spring_boot_starter_flutter|lib/src/debug/console/debug_console_command.dart':
      '''
abstract class DebugConsoleCommand {
  const DebugConsoleCommand();
  String? get name => null;
  String get usage;
  String get help;
  Iterable<String> run(Object call);
}
''',
};

const _header = '''
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
''';

const _extensions = '''
@Component()
class Clock {
  int get now => 0;
}

@ConsoleSegment('ping', order: 50)
class PingSegment extends DebugConsoleSegment {
  PingSegment(this.clock);

  final Clock clock;

  @override
  void Function() start(void Function() changed) => () {};

  @override
  Object? read() => clock.now;
}

@ConsoleCommand('reload')
class ReloadCommand extends DebugConsoleCommand {
  ReloadCommand(this.clock);

  final Clock clock;

  @override
  String get usage => '';

  @override
  String get help => 'Reloads.';

  @override
  Iterable<String> run(Object call) => [clock.now.toString()];
}

@ConsolePane('cart', order: 20)
class CartPane extends DebugConsolePane {
  CartPane(this.clock);

  final Clock clock;

  @override
  String get title => 'Cart';

  @override
  Object build(Object context, Object console) => clock.now;
}
''';

Future<PackageConfig> _packageConfig() async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  return PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != 'spring_boot_starter_flutter') package,
    Package(
      'spring_boot_starter_flutter',
      Uri.parse('file:///spring_boot_starter_flutter/'),
      packageUriRoot: Uri.parse('file:///spring_boot_starter_flutter/lib/'),
    ),
  ]);
}

Map<String, String> _sources(String beans, String? config, String? yaml) => {
  'pkg|lib/main.dart': _main,
  'pkg|lib/src/app.dart': '$_header$beans',
  'pkg|lib/resources/application.properties': ?config,
  'pkg|lib/resources/application.yml': ?yaml,
  ..._stubs,
};

Future<TestBuilderResult> _build(
  String beans, {
  String? config,
  String? yaml,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(generations: packageGenerations),
    _sources(beans, config, yaml),
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: await _packageConfig(),
    flattenOutput: true,
  );
}

const _module = 'lib/spring_gen/main.spring.dart';
const _debugPart = 'lib/spring_gen/main.spring.debug.dart';

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

/// The application's library and its debug part (normalized), after
/// checking that they compile.
Future<({String module, String debug})> _generate({
  String beans = _extensions,
  String? config,
  String? yaml,
}) async {
  final result = await _build(beans, config: config, yaml: yaml);
  expect(result.errors, isEmpty);
  final text = moduleText(result, AssetId('pkg', _module));
  final files = moduleSources(text);
  final errors = await resolveSources<List<String>>(
    {..._sources(beans, config, yaml), ...files},
    (resolver) async {
      final library = await resolver.libraryFor(AssetId('pkg', _module));
      final errors = await moduleErrors(library);
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$_module',
    packageConfig: await _packageConfig(),
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: text);
  return (
    module: _normalize(files['pkg|$_module']!),
    debug: _normalize(files['pkg|$_debugPart'] ?? ''),
  );
}

Future<String> _errors(String beans, {String? config}) async {
  final result = await _build(beans, config: config);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

const _console = 'spring.flutter.debug.console.enabled';
const _panesKey = 'spring.flutter.debug.console.panes';
const _commandsPane = '$_panesKey=commands';
const _segmentsKey = 'spring.flutter.debug.console.segments';
const _shown = '$_console=true\n$_segmentsKey=fps,ping';

void main() {
  group('without the console', () {
    for (final (what, config) in [
      ('not set', null),
      ('false', '$_console=false\n$_commandsPane'),
    ]) {
      test('$what: the classes are no beans, nothing refers to them', () async {
        final (:module, :debug) = await _generate(config: config);
        for (final code in [module, debug]) {
          expect(code, isNot(contains('PingSegment')));
          expect(code, isNot(contains('ReloadCommand')));
          expect(code, isNot(contains('CartPane')));
          expect(code, isNot(contains('debugConsole')));
        }
        // The other beans as ever.
        expect(module, contains('BeanDefinition<Clock>('));
      });
    }
  });

  test('with the console and `segments` naming it: the segment in the '
      'debug part, constructor injection, its order and its annotation (the '
      "console's one source of its name), spread into the beans in every "
      'build; the command needs the input too', () async {
    final (:module, :debug) = await _generate(config: _shown);
    expect(
      debug,
      contains(r'List<BeanDefinition<Object>>get_$debugConsoleSegments=>['),
    );
    expect(debug, contains('BeanDefinition<PingSegment>('));
    expect(debug, contains('PingSegment(r.dependency<Clock>('));
    expect(debug, contains('order:50'));
    expect(
      debug,
      contains("annotations:const[ConsoleSegment(r'ping',order:50)]"),
    );
    expect(module, contains(r'..._$debugConsoleSegments'));
    expect(module, isNot(contains(r')..._$debugConsoleSegments')));
    // The library itself never names the class.
    expect(module, isNot(contains('PingSegment')));
    expect(module + debug, isNot(contains('ReloadCommand')));
  });

  test(
    'with the console and its commands pane: the command in the debug part '
    'too',
    () async {
      final (:module, :debug) = await _generate(
        config: '$_console=true\n$_commandsPane',
      );
      expect(debug, contains(r'get_$debugConsoleCommands=>['));
      expect(debug, contains('ReloadCommand(r.dependency<Clock>('));
      expect(module, contains(r'..._$debugConsoleCommands'));
      expect(module, isNot(contains('ReloadCommand')));
    },
  );

  group('a bean of the app that injects one fails the build', () {
    const injecting =
        '''
$_extensions
@Component()
class Dashboard {
  Dashboard(this.ping);
  final PingSegment ping;
}
''';

    for (final (what, config) in [
      ('with the console', _shown),
      ('without it', null),
    ]) {
      test(what, () async {
        final errors = await _errors(injecting, config: config);
        expect(errors, contains('The bean dashboard injects PingSegment'));
        expect(errors, contains('@ConsoleSegment'));
        expect(errors, contains(_console));
      });
    }

    test('a segment may inject another console extension', () async {
      final (:module, :debug) = await _generate(
        beans:
            '''
$_extensions
@ConsoleSegment('pong')
class PongSegment extends DebugConsoleSegment {
  PongSegment(this.ping);
  final PingSegment ping;
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => ping.read();
}
''',
        config: '$_console=true\n$_segmentsKey=pong,ping',
      );
      expect(debug, contains('PongSegment(r.dependency<PingSegment>('));
      expect(module, isNot(contains('PongSegment')));
    });
  });

  test(
    'a class that does not implement its interface fails the build',
    () async {
      final errors = await _errors('''
@ConsoleSegment('odd')
class OddSegment {}
''', config: '$_console=true');
      expect(errors, contains('@ConsoleSegment on OddSegment'));
      expect(errors, contains('implements DebugConsoleSegment'));
    },
  );

  group('`segments` picks the segments the build has', () {
    for (final (what, segments) in [
      ("not set (its default names only the framework's)", null),
      ('set without it', 'fps,filter'),
      ('empty', ''),
    ]) {
      test('$what: no registration, nothing refers to the class', () async {
        final (:module, :debug) = await _generate(
          config: [
            '$_console=true',
            _commandsPane,
            if (segments != null) '$_segmentsKey=$segments',
          ].join('\n'),
        );
        expect(module + debug, isNot(contains('PingSegment')));
        expect(module + debug, isNot(contains('debugConsoleSegments')));
        // The command comes with the commands pane, whatever `segments`
        // says.
        expect(debug, contains('ReloadCommand(r.dependency<Clock>('));
      });
    }

    test('* stands for it', () async {
      final (:module, :debug) = await _generate(
        config: '$_console=true\n$_segmentsKey=fps,*',
      );
      expect(debug, contains('BeanDefinition<PingSegment>('));
      expect(module, contains(r'..._$debugConsoleSegments'));
    });

    test('a YAML list names it', () async {
      final (:module, :debug) = await _generate(
        yaml: '''
spring:
  flutter:
    debug:
      console:
        enabled: true
        segments:
          - fps
          - ping
''',
      );
      expect(debug, contains('BeanDefinition<PingSegment>('));
      expect(module, contains(r'..._$debugConsoleSegments'));
    });

    test(
      'a segment that injects one `segments` leaves out fails the build',
      () async {
        final errors = await _errors('''
$_extensions
@ConsoleSegment('pong')
class PongSegment extends DebugConsoleSegment {
  PongSegment(this.ping);
  final PingSegment ping;
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => ping.read();
}
''', config: '$_console=true\n$_segmentsKey=pong');
        expect(errors, contains('PingSegment, which this build leaves out'));
        expect(errors, contains("naming 'ping'"));
      },
    );
  });

  group('`panes` picks the panes the build has', () {
    for (final (what, panes) in [
      ('not set (its default names none)', null),
      ('set without it', 'commands'),
      ('empty', ''),
    ]) {
      test('$what: no registration, nothing refers to the class', () async {
        final (:module, :debug) = await _generate(
          config: [
            '$_console=true',
            if (panes != null) '$_panesKey=$panes',
          ].join('\n'),
        );
        expect(module + debug, isNot(contains('CartPane')));
        expect(module + debug, isNot(contains('debugConsolePanes')));
      });
    }

    for (final (what, panes) in [('naming it', 'cart'), ('holding *', '*')]) {
      test('$what: the pane in the debug part, constructor injection, its '
          'order and its annotation, spread into the beans', () async {
        final (:module, :debug) = await _generate(
          config: '$_console=true\n$_panesKey=$panes',
        );
        expect(
          debug,
          contains(r'List<BeanDefinition<Object>>get_$debugConsolePanes=>['),
        );
        expect(debug, contains('CartPane(r.dependency<Clock>('));
        expect(debug, contains('order:20'));
        expect(
          debug,
          contains("annotations:const[ConsolePane(r'cart',order:20)]"),
        );
        expect(module, contains(r'..._$debugConsolePanes'));
        expect(module, isNot(contains('CartPane')));
      });
    }

    test('without the console: no code, even named', () async {
      final (:module, :debug) = await _generate(config: '$_panesKey=cart,*');
      expect(module + debug, isNot(contains('CartPane')));
    });

    test('the commands come with the `commands` pane only: another pane '
        'named leaves them out', () async {
      final (:module, :debug) = await _generate(
        config: '$_console=true\n$_panesKey=cart',
      );
      expect(debug, contains('CartPane(r.dependency<Clock>('));
      expect(module + debug, isNot(contains('ReloadCommand')));
    });

    for (final (what, config) in [
      ('with the pane', '$_console=true\n$_panesKey=cart'),
      ('without it', null),
    ]) {
      test(
        'a bean of the app that injects one fails the build, $what',
        () async {
          final errors = await _errors('''
$_extensions
@Component()
class Checkout {
  Checkout(this.cart);
  final CartPane cart;
}
''', config: config);
          expect(errors, contains('The bean checkout injects CartPane'));
          expect(errors, contains('@ConsolePane'));
          expect(errors, contains(_panesKey));
        },
      );
    }

    test(
      'a class that does not implement DebugConsolePane fails the build',
      () async {
        final errors = await _errors('''
@ConsolePane('odd')
class OddPane {}
''', config: '$_console=true\n$_panesKey=*');
        expect(errors, contains('@ConsolePane on OddPane'));
        expect(errors, contains('implements DebugConsolePane'));
      },
    );

    test('a pane bean with neither the annotation nor a name getter fails '
        'the build', () async {
      final errors = await _errors('''
@Component()
class Nameless extends DebugConsolePane {
  @override
  String get title => 'Nameless';
  @override
  Object build(Object context, Object console) => 0;
}
''', config: '$_console=true\n$_panesKey=*');
      expect(errors, contains('The bean nameless is a DebugConsolePane'));
      expect(errors, contains('neither @ConsolePane nor a name getter'));
    });

    test('a name getter that disagrees with the annotation fails the '
        'build', () async {
      final errors = await _errors('''
@ConsolePane('cart')
class Odd extends DebugConsolePane {
  @override
  String get name => 'basket';
  @override
  String get title => 'Odd';
  @override
  Object build(Object context, Object console) => 0;
}
''', config: '$_console=true\n$_panesKey=cart');
      expect(errors, contains("name getter says 'basket'"));
    });

    test('an empty name fails the build', () async {
      final errors = await _errors('''
@ConsolePane('')
class Blank extends DebugConsolePane {
  @override
  String get title => 'Blank';
  @override
  Object build(Object context, Object console) => 0;
}
''', config: '$_console=true\n$_panesKey=*');
      expect(errors, contains('its name is empty'));
    });
  });

  group("the name: the annotation's, else the getter", () {
    test('a segment bean with neither fails the build', () async {
      final errors = await _errors('''
@Component()
class Nameless extends DebugConsoleSegment {
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => null;
}
''', config: _shown);
      expect(errors, contains('The bean nameless is a DebugConsoleSegment'));
      expect(errors, contains('neither @ConsoleSegment nor a name getter'));
    });

    test('a command bean named by its getter is no error', () async {
      final result = await _build('''
@Component()
class Plain extends DebugConsoleCommand {
  @override
  String get name => 'plain';
  @override
  String get usage => '';
  @override
  String get help => '';
  @override
  Iterable<String> run(Object call) => const [];
}
''', config: '$_console=true\n$_commandsPane');
      expect(result.errors, isEmpty);
    });

    test('a getter that agrees with the annotation is no error', () async {
      final result = await _build('''
@ConsoleSegment('same')
class Same extends DebugConsoleSegment {
  @override
  final String name = 'same';
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => null;
}
''', config: _shown);
      expect(result.errors, isEmpty);
    });

    for (final (what, getter) in [
      ('a getter', "String get name => 'other';"),
      ('a field', "final String name = 'other';"),
    ]) {
      test('$what that disagrees with the annotation fails the build, '
          'shown or not', () async {
        for (final config in [_shown, '$_console=true']) {
          final errors = await _errors('''
@ConsoleSegment('ping')
class Odd extends DebugConsoleSegment {
  @override
  $getter
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => null;
}
''', config: config);
          expect(errors, contains("name getter says 'other'"));
        }
      });
    }

    test('an empty name fails the build', () async {
      final errors = await _errors('''
@ConsoleSegment(' ')
class Blank extends DebugConsoleSegment {
  @override
  void Function() start(void Function() changed) => () {};
  @override
  Object? read() => null;
}
''', config: _shown);
      expect(errors, contains('its name is empty'));
    });
  });
}
