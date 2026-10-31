// Proxies only where something advises: an application with no aspect,
// whose only advice is the starters' annotation-driven advisors
// (`@Transactional`, `@Cacheable`, `@Validated`), gets proxy classes for the
// beans carrying those annotations and for nothing else.
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _beans = '''
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Tag {
  const Tag();
}

class AdminTransactional extends Transactional {
  const AdminTransactional();
}

@Service()
class Plain {
  int next() => 0;
}

@Service()
class Overrides implements Comparable<Overrides> {
  @override
  int compareTo(Overrides other) => 0;

  @Deprecated('use next')
  int old() => 0;
}

@Service()
class Tagged {
  @Tag()
  int tagged() => 0;
}

@Service()
class Orders {
  @Transactional()
  Future<void> place() async {}
}

@Transactional()
@Service()
class ClassLevel {
  Future<void> place() async {}
}

@Service()
class Admin {
  @AdminTransactional()
  Future<void> run() async {}
}

@Service()
class Prices {
  @Cacheable('prices')
  int price(int id) => id;
}

@Validated()
@Service()
class Checked {
  int check(int value) => value;
}
''';

Future<String> _app() async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {'pkg|bin/main.dart': _main, 'pkg|lib/src/beans.dart': _beans},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return readerWriter.testing.readString(
    result.outputs.singleWhere((o) => o.path == 'bin/main.spring.dart'),
  );
}

void main() {
  late String output;

  setUpAll(() async => output = await _app());

  Matcher proxyOf(String name) => contains('class _\$${name}Proxy');

  test('no proxy class for a bean nothing advises', () {
    expect(output, isNot(proxyOf('Plain')));
  });

  test('@override and @Deprecated keep no proxy', () {
    expect(output, isNot(proxyOf('Overrides')));
  });

  test('an annotation no advisor matches keeps no proxy', () {
    expect(output, isNot(proxyOf('Tagged')));
  });

  test('the annotations of the starters keep the proxy', () {
    expect(output, proxyOf('Orders'));
    expect(output, proxyOf('ClassLevel'));
    expect(output, proxyOf('Prices'));
    expect(output, proxyOf('Checked'));
  });

  test('a subclass of an advised annotation keeps the proxy', () {
    expect(output, proxyOf('Admin'));
  });

  test('a pruned bean says why, for an advisor added at run time', () {
    expect(
      output,
      contains(
        'the build found no pointcut of the application that matches '
        'Plain',
      ),
    );
  });
}
