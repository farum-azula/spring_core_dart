import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

// Records the order in which definitions are looked at (conditions run when
// the module is registered).
final class _Recorder implements Condition {
  const _Recorder(this.log, this.name);
  final List<String> log;
  final String name;

  @override
  bool matches(ConditionContext context) {
    log.add(name);
    return true;
  }
}

final class _Bean {
  const _Bean(this.name);
  final String name;
}

// A module with one bean per entry of [classes] (each created by the
// auto-configuration class of that name), or one bean named like the module.
BeanModule _module(String name, List<String> log, [List<String>? classes]) =>
    BeanModule(name, [
      for (final owner in classes ?? [name])
        BeanDefinition<_Bean>(
          name: '$name.$owner',
          source: 'package:t/t.dart#$owner',
          create: (_) => _Bean(owner),
          conditions: [_Recorder(log, '$name.$owner')],
        ),
    ]);

const AutoConfigurationModule Function({
  List<String> after,
  List<String> before,
  int order,
  String? requires,
})
_meta = AutoConfigurationModule.new;

// Registers one `_Bean` named [name].
final class _NamedRegistrar implements BeanRegistrar {
  _NamedRegistrar(this.name);
  final String name;

  @override
  void register(BeanRegistry registry, Environment environment) =>
      registry.registerBean<_Bean>((_) => _Bean(name), name: name);
}

ConfigurableApplicationContext _run(
  List<BeanModule> autoConfigurations, {
  Map<BeanModule, AutoConfigurationModule> metadata = const {},
  List<Type> exclude = const [],
  List<String> excludeName = const [],
  List<String> args = const [],
}) => SpringApplication(
  [],
  autoConfigurations: autoConfigurations,
  autoConfigurationMetadata: metadata,
  exclude: exclude,
  excludeName: excludeName,
  out: (_) {},
).run(args, systemEnvironment: const {});

class CacheAutoConfiguration {}

void main() {
  late List<String> log;
  setUp(() => log = []);

  group('order', () {
    test('modules are sorted by name, not by the order they are listed', () {
      _run([_module('c', log), _module('a', log), _module('b', log)]).close();
      expect(log, ['a.a', 'b.b', 'c.c']);
    });

    test('order comes before the name; equal orders stay alphabetical', () {
      final a = _module('a', log);
      final b = _module('b', log);
      final c = _module('c', log);
      final d = _module('d', log);
      _run(
        [a, b, c, d],
        metadata: {a: _meta(order: 2), b: _meta(order: -1), c: _meta(order: 2)},
      ).close();
      expect(log, ['b.b', 'd.d', 'a.a', 'c.c']);
    });

    test('after puts a module behind another one', () {
      final a = _module('a', log);
      _run(
        [a, _module('b', log)],
        metadata: {
          a: _meta(after: ['b']),
        },
      ).close();
      expect(log, ['b.b', 'a.a']);
    });

    test('before puts a module in front of another one', () {
      final z = _module('z', log);
      _run(
        [_module('a', log), z],
        metadata: {
          z: _meta(before: ['a']),
        },
      ).close();
      expect(log, ['z.z', 'a.a']);
    });

    test('constraints win over order and chain', () {
      final a = _module('a', log);
      final b = _module('b', log);
      final c = _module('c', log);
      _run(
        [a, b, c],
        metadata: {
          a: _meta(after: ['b']),
          b: _meta(after: ['c']),
          c: _meta(order: 100),
        },
      ).close();
      expect(log, ['c.c', 'b.b', 'a.a']);
    });

    test('an auto-configuration class can be named in before / after', () {
      final a = _module('a', log);
      final b = _module('b', log, ['CacheAutoConfiguration']);
      _run(
        [a, b],
        metadata: {
          a: _meta(after: ['CacheAutoConfiguration']),
        },
      ).close();
      expect(log, ['b.CacheAutoConfiguration', 'a.a']);
    });

    test('names of modules that are not there are ignored', () {
      final a = _module('a', log);
      _run(
        [a],
        metadata: {
          a: _meta(after: ['nope'], before: ['nada']),
        },
      ).close();
      expect(log, ['a.a']);
    });

    test('a cycle stops the start naming both modules', () {
      final a = _module('a', log);
      final b = _module('b', log);
      expect(
        () => _run(
          [a, b],
          metadata: {
            a: _meta(after: ['b']),
            b: _meta(after: ['a']),
          },
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('AutoConfigure cycle detected between'),
              contains('a'),
            ),
          ),
        ),
      );
      expect(log, isEmpty);
    });

    test('before constraints can make a cycle too', () {
      final a = _module('a', log);
      final b = _module('b', log);
      expect(
        () => _run(
          [a, b],
          metadata: {
            a: _meta(before: ['b']),
            b: _meta(before: ['a']),
          },
        ),
        throwsStateError,
      );
    });
  });

  group('exclusion', () {
    test('exclude removes a class of auto-configuration by type', () {
      final both = _module('both', log, [
        'CacheAutoConfiguration',
        'OtherAutoConfiguration',
      ]);
      final context = _run([both], exclude: [CacheAutoConfiguration]);
      expect(log, ['both.OtherAutoConfiguration']);
      expect(context.containsBean('both.CacheAutoConfiguration'), isFalse);
      expect(context.containsBean('both.OtherAutoConfiguration'), isTrue);
      context.close();
    });

    test('excluding one class of a module keeps the imports of the others', () {
      final module = BeanModule(
        'both',
        [
          for (final owner in [
            'CacheAutoConfiguration',
            'OtherAutoConfiguration',
          ])
            BeanDefinition<_Bean>(
              name: owner,
              source: 'package:t/t.dart#$owner',
              create: (_) => _Bean(owner),
            ),
        ],
        registrars: [
          for (final owner in [
            'CacheAutoConfiguration',
            'OtherAutoConfiguration',
          ])
            ImportDeclaration(
              () => _NamedRegistrar('$owner.registered'),
              importer: 'package:t/t.dart#$owner',
            ),
        ],
      );
      final context = _run([module], exclude: [CacheAutoConfiguration]);
      expect(context.getBeanNamesForType(_Bean), [
        'OtherAutoConfiguration',
        'OtherAutoConfiguration.registered',
      ]);
      context.close();
    });

    test('excludeName removes a module by name and a class by name', () {
      final context = _run(
        [
          _module('a', log),
          _module('b', log),
          _module('c', log, ['CacheAutoConfiguration']),
        ],
        excludeName: ['a', 'CacheAutoConfiguration'],
      );
      expect(log, ['b.b']);
      context.close();
    });

    test('the qualified source of a class excludes it too', () {
      final context = _run(
        [
          _module('a', log, ['CacheAutoConfiguration']),
        ],
        excludeName: ['package:t/t.dart#CacheAutoConfiguration'],
      );
      expect(log, isEmpty);
      context.close();
    });

    test('spring.autoconfigure.exclude is comma-separated', () {
      final context = _run(
        [_module('a', log), _module('b', log), _module('c', log)],
        args: ['--spring.autoconfigure.exclude=a, c'],
      );
      expect(log, ['b.b']);
      context.close();
    });

    test('spring.autoconfigure.exclude takes indexed keys', () {
      final context =
          SpringApplication(
            [],
            autoConfigurations: [_module('a', log), _module('b', log)],
            out: (_) {},
          ).run(
            const [],
            systemEnvironment: const {},
            properties: const {'spring.autoconfigure.exclude[0]': 'a'},
          );
      expect(log, ['b.b']);
      context.close();
    });

    test('a type that is no auto-configuration fails the start', () {
      expect(
        () => _run([_module('a', log)], exclude: [CacheAutoConfiguration]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('CacheAutoConfiguration'),
          ),
        ),
      );
    });

    test('an unknown name is ignored', () {
      _run([_module('a', log)], excludeName: ['nope']).close();
      expect(log, ['a.a']);
    });

    test('exclusions apply before any condition runs', () {
      final context = _run(
        [_module('a', log), _module('b', log)],
        excludeName: ['a'],
      );
      expect(log, isNot(contains('a.a')));
      context.close();
    });
  });

  test('the built-in auto-configurations can be excluded one by one', () {
    final context = _run(
      [springBootAutoConfiguration],
      excludeName: ['JacksonAutoConfiguration'],
    );
    expect(context.containsBean('jacksonJsonMapper'), isFalse);
    expect(context.containsBean('defaultValidator'), isTrue);
    context.close();
  });
}
