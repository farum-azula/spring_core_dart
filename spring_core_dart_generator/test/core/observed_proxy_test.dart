// @Observed and the build: without spring.observations.annotations.enabled
// the advisor's module is left out and the bean marked @Observed gets no
// proxy class; with it, the bean gets one and the module is in the app.
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@Service()
class Catalog {
  @Observed(name: 'catalog.load')
  Future<int> load() async => 1;
}

@Service()
class Plain {
  int count() => 1;
}

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

Future<String> _module(String config) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {
      'pkg|lib/main.dart': _main,
      'pkg|lib/resources/application.yml': config,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(
    result.outputs.singleWhere(
      (o) => o.path == 'lib/spring_gen/main.spring.dart',
    ),
  );
}

void main() {
  test('off: no advisor module, no proxy class', () async {
    final module = await _module('spring:\n  application:\n    name: x\n');
    expect(
      module,
      isNot(contains('springBootObservedAnnotationsAutoConfiguration')),
    );
    expect(module, isNot(contains('CatalogProxy')));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('on: the module and a proxy for the bean marked only', () async {
    final module = await _module(
      'spring:\n  observations:\n    annotations:\n      enabled: true\n',
    );
    expect(module, contains('springBootObservedAnnotationsAutoConfiguration'));
    expect(module, contains('CatalogProxy'));
    expect(module, isNot(contains('PlainProxy')));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
