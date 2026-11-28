// @Retryable and @ConcurrencyLimit and the build: advice where a proxy
// runs it, no pause or waiting permit in a synchronous method, a limit of
// at least 1; the element type of a retried stream and the Map types of
// its arguments in the signature; and the switch: without
// spring.resilience.enabled the advisors' module is left out and the
// beans get no proxy class, with it they do.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@Service()
class Payments {
  @Retryable(maxRetries: 2)
  Future<int> charge() async => 1;
}

@Service()
class Reports {
  @ConcurrencyLimit(2)
  Future<int> make() async => 1;
}

@Service()
class Plain {
  int count() => 1;
}

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

Future<String> _application(String config) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {
      'pkg|lib/main.dart': _main,
      'pkg|lib/resources/application.yml': config,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return moduleText(result, AssetId('pkg', 'lib/spring_gen/main.spring.dart'));
}

void main() {
  group('where the annotations may go', () {
    final cases = <String, (String, List<String>)>{
      'a private method': (
        '@Component() class Orders { @Retryable() Future<void> _save() async '
            '{} Future<void> call() => _save(); }',
        ['@Retryable on Orders._save: a private member is not called'],
      ),
      'a static method': (
        '@Component() class Orders { @ConcurrencyLimit(1) static Future<int> '
            'count() async => 1; }',
        ['@ConcurrencyLimit on Orders.count: a static member'],
      ),
      'a class that is no bean': (
        'class Report { @Retryable() Future<void> run() async {} }',
        [
          '@Retryable on Report.run, and Report is no bean',
          'so nothing would be retried',
        ],
      ),
      'a field': (
        '@Component() class A { @ConcurrencyLimit(1) int count = 0; }',
        ['@ConcurrencyLimit on the field A.count'],
      ),
      'a constructor': (
        '@Component() class A { @Retryable() A(); }',
        ['@Retryable on the constructor A: a constructor is not called'],
      ),
      'a delay on a synchronous method': (
        '@Component() class A { @Retryable() int count() => 1; }',
        [
          '@Retryable on A.count with a delay (1 second unless written)',
          'and it is synchronous',
          'Write delay: Duration.zero (and no jitter or timeout)',
        ],
      ),
      'a timeout on a synchronous method': (
        '@Component() class A { @Retryable(delay: Duration.zero, timeout: '
            'Duration(seconds: 1)) int count() => 1; }',
        ['@Retryable on A.count with a timeout, and it is synchronous'],
      ),
      'a jitter text on a synchronous method': (
        '@Component() class A { @Retryable(delay: Duration.zero, '
            "jitterString: '5ms') void run() {} }",
        ['with a jitterString'],
      ),
      'a class with a synchronous method': (
        '@Component() @Retryable() class A { Future<void> load() async {} '
            'int count() => 1; }',
        [
          '@Retryable on class A with a delay (1 second unless written)',
          'and A.count is synchronous',
          'give count a @Retryable of its own',
        ],
      ),
      'BLOCK on a synchronous method': (
        '@Component() class A { @ConcurrencyLimit(2) int count() => 1; }',
        [
          '@ConcurrencyLimit on A.count waits for a permit',
          '(ThrottlePolicy.block), and A.count does not return a Future',
          'policy: ThrottlePolicy.reject',
        ],
      ),
      'BLOCK on a stream method': (
        '@Component() class A { @ConcurrencyLimit(2) Stream<int> feed() => '
            'const Stream.empty(); }',
        ['A.feed does not return a Future'],
      ),
      'a limit below 1': (
        '@Component() class A { @ConcurrencyLimit(0) Future<void> run() '
            'async {} }',
        ['@ConcurrencyLimit(0) on A.run: the limit is how many calls'],
      ),
    };
    for (final MapEntry(key: name, value: (source, messages))
        in cases.entries) {
      test(name, () async {
        final result = await buildPackage({
          'lib/src/beans.dart': scanRoot,
          'lib/src/service.dart': '$coreImport$source',
        }, proxyMode: ProxyMode.all);
        expect(result.succeeded, isFalse);
        final errors = result.errors.join('\n');
        for (final message in messages) {
          expect(errors, contains(message));
        }
      });
    }

    test('in their places they build', () async {
      final output = await generateModule('''
@Service()
@ConcurrencyLimit(4, policy: ThrottlePolicy.reject)
class Payments {
  @Retryable(includes: [StateError])
  Future<int> charge() async => 1;

  @Retryable(delay: Duration.zero)
  int count() => 1;

  @ConcurrencyLimit(1, policy: ThrottlePolicy.reject)
  int once() => 1;

  @Retryable()
  Stream<String> feed(Map<String, int> prices) => const Stream.empty();
}
''', proxyMode: ProxyMode.all);
      expect(output, hasCode('returnTypeArguments: [TypeCapture<String>()]'));
      expect(
        output,
        hasCode('parameterMapTypes: [MapTypes<String, int>()]'),
      );
    });
  });

  group('the switch', () {
    test('off: no advisor module, no proxy class', () async {
      final module = await _application(
        'spring:\n  application:\n    '
        'name: x\n',
      );
      expect(module, isNot(contains('springBootResilienceAutoConfiguration')));
      expect(module, isNot(contains('PaymentsProxy')));
      expect(module, isNot(contains('ReportsProxy')));
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('on: the module, and a proxy for the beans marked only', () async {
      final module = await _application(
        'spring:\n  resilience:\n    enabled: true\n',
      );
      expect(module, contains('springBootResilienceAutoConfiguration'));
      expect(module, contains('PaymentsProxy'));
      expect(module, contains('ReportsProxy'));
      expect(module, isNot(contains('PlainProxy')));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
