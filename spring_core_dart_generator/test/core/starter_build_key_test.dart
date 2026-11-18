// A starter's part of the module build with a build key
// (`StarterGeneration.build`), as an auto-configuration module has one: the
// application's configuration puts the part's code in every build (`true`),
// in none (`false`), or, when it does not set the key, as `whenMissing`
// says; in debug and profile builds only, its code is under the constant a
// release build compiles away.
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/module_emitter.dart';
import 'package:spring_core_dart_generator/src/core/spring_builder.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _guard = "if(!constbool.fromEnvironment('dart.vm.product'))";

// A bean the part makes.
final class _ClockCreation extends StarterCreation {}

// A part that writes in every slot: a bean of its own (`Clock`), a bean
// definition, a statement, a class, a declaration, a part file with its
// introspections and a resource.
final class _ClockGeneration extends StarterGeneration {
  const _ClockGeneration(this.build);

  @override
  final StarterBuild? build;

  @override
  String get package => 'pkg';

  @override
  bool claimClass(ClassElement element, ModuleScan scan) {
    if (element.name != 'Clock') {
      return false;
    }
    scan.addGeneratedBean(element, _ClockCreation());
    return true;
  }

  @override
  Iterable<Spec> classes(ModuleEmission emission) => [
    Class((c) => c..name = r'_$ClockImpl'),
  ];

  @override
  Expression? beanCreation(BeanModel bean, ModuleEmission emission) =>
      bean.creation is _ClockCreation
      ? refer(r'_$ClockImpl').newInstance([])
      : null;

  @override
  Iterable<Expression> beanDefinitions(ModuleEmission emission) => [
    refer('clockTicks').call([]),
  ];

  @override
  Iterable<Code> moduleStatements(ModuleEmission emission) => [
    refer('startClock').call([]).statement,
  ];

  @override
  Iterable<Spec> declarations(ModuleEmission emission) => [
    Method(
      (m) => m
        ..name = 'startClock'
        ..returns = refer('void')
        ..body = const Code(''),
    ),
  ];

  @override
  Future<ModuleParts> moduleParts(BuildStep buildStep) async =>
      const ModuleParts(
        ['clock.part.dart'],
        [],
        introspections: [r'_$clockIntrospections'],
        resources: {'clock.txt': (text: 'tick', base64: null)},
      );
}

// The module of a package with `abstract class Clock {}`, built with the
// part keyed by [build] and the configuration [files] (by path below
// lib/resources/); its source without whitespace, and the log.
Future<(String, List<String>)> _module(
  StarterBuild? build, {
  Map<String, String> files = const {},
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final logs = <String>[];
  final result = await testBuilder(
    SpringBuilder(
      generations: [_ClockGeneration(build)],
      proxyMode: ProxyMode.none,
    ),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/clock.dart': 'abstract class Clock {}\n',
      for (final MapEntry(:key, :value) in files.entries)
        'pkg|lib/resources/$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.errors, isEmpty);
  final source = result.readerWriter.testing.readString(
    result.outputs.singleWhere(
      (o) => o.path == 'lib/spring_gen/src/beans.spring.dart',
    ),
  );
  return (source.replaceAll(RegExp(r'\s+'), ''), logs);
}

Map<String, String> _yaml(String enabled) => {
  'application.yml': 'clock:\n  enabled: $enabled\n',
};

const _key = StarterBuild('clock.enabled');

final _clockBean = RegExp(r'BeanDefinition<(_i\d+\.)?Clock>');

// The part's code in every build: no condition anywhere.
void _expectAlways(String module) {
  expect(module, isNot(contains('dart.vm.product')));
  expect(module, contains(_clockBean));
  expect(module, contains(r'create:(r)=>_$ClockImpl()'));
  expect(module, contains('clockTicks()'));
  expect(module, contains('{startClock();return'));
  expect(module, contains(r'..._$clockIntrospections'));
  expect(module, contains("r'clock.txt':"));
  expect(module, contains(r'class_$ClockImpl{}'));
  expect(module, contains('voidstartClock(){}'));
  expect(module, contains("part'clock.part.dart';"));
}

// None of the part's code: it did not run (Clock is no bean either).
void _expectNever(String module) {
  expect(module, isNot(contains(_clockBean)));
  for (final text in [
    'ClockImpl',
    'clockTicks',
    'startClock',
    'clockIntrospections',
    'clock.txt',
    'clock.part.dart',
    'dart.vm.product',
  ]) {
    expect(module, isNot(contains(text)), reason: text);
  }
}

// The part's code in debug and profile builds only: what can be under the
// constant is, the declarations are not.
void _expectNotInRelease(String module) {
  expect(
    module,
    contains(
      RegExp(
        '${RegExp.escape(_guard)}'
        r'(_i\d+\.)?BeanDefinition<(_i\d+\.)?Clock>',
      ),
    ),
  );
  expect(module, contains('${_guard}clockTicks()'));
  expect(module, contains('$_guard{startClock();}return'));
  expect(
    module,
    contains(
      '$_guard...'
      r'_$clockIntrospections',
    ),
  );
  expect(module, contains("${_guard}r'clock.txt':"));
  expect(module, contains(r'class_$ClockImpl{}'));
  expect(module, contains('voidstartClock(){}'));
  expect(module, contains("part'clock.part.dart';"));
}

void main() {
  test('a part without a key is in every build', () async {
    final (module, _) = await _module(null, files: _yaml('false'));
    _expectAlways(module);
  });

  group('the key set', () {
    test('true: the part is in every build', () async {
      final (module, _) = await _module(_key, files: _yaml('true'));
      _expectAlways(module);
    });

    test('false: the part does not run, its code is in no build', () async {
      final (module, _) = await _module(_key, files: _yaml('false'));
      _expectNever(module);
    });

    test('in application.properties too', () async {
      final (module, _) = await _module(
        _key,
        files: {'application.properties': 'clock.enabled=FALSE\n'},
      );
      _expectNever(module);
    });
  });

  group('the key not set', () {
    test('whenMissing notInRelease (the default): under the constant a '
        'release build compiles away', () async {
      final (module, _) = await _module(_key);
      _expectNotInRelease(module);
    });

    test('whenMissing always: in every build', () async {
      final (module, _) = await _module(
        const StarterBuild(
          'clock.enabled',
          whenMissing: BuildInclusion.always,
        ),
      );
      _expectAlways(module);
    });

    test('whenMissing never: in no build', () async {
      final (module, _) = await _module(
        const StarterBuild('clock.enabled', whenMissing: BuildInclusion.never),
        files: {'application.yml': 'other: 1\n'},
      );
      _expectNever(module);
    });

    test('set only in a profile: warned about, decided as not set', () async {
      final (module, logs) = await _module(
        const StarterBuild('clock.enabled', whenMissing: BuildInclusion.never),
        files: {'application-dev.yml': 'clock:\n  enabled: true\n'},
      );
      _expectNever(module);
      expect(
        logs,
        contains(
          endsWith(
            "pkg's generator part: clock.enabled is set only in "
            'application-dev.yml, which the build does not read: it decides by '
            'application.yml or application.properties without a profile. The '
            'part is built as when it is not set.',
          ),
        ),
      );
    });

    test('neither true nor false: warned about, decided as not set', () async {
      final (module, logs) = await _module(_key, files: _yaml('maybe'));
      _expectNotInRelease(module);
      expect(
        logs,
        contains(
          endsWith(
            "pkg's generator part: clock.enabled is 'maybe', not true or "
            'false; the part is built as when it is not set.',
          ),
        ),
      );
    });
  });
}
