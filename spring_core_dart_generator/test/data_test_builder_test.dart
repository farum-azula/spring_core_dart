// Test classes marked @DataTest: what <name>.test.spring.dart declares for
// the slice of the data layer, the transaction around each test and the
// annotations that change it, and the build errors. Running the generated
// tests is covered by spring_boot_starter_data/test/data_test/.
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/test_builder.dart';
import 'package:test/test.dart';

const _app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'app.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

const _imports = '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart' as t;
import 'spring/shop.test.spring.dart';
''';

Future<TestBuilderResult> _build(
  String testClass, {
  Map<String, String> files = const {'bin/app.dart': _app},
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  return await testBuilder(
    SpringTestBuilder(),
    {
      'pkg|test/shop_test.dart':
          '$_imports\n$testClass\n'
          'void main() => runSpringTests();\n',
      for (final MapEntry(:key, :value) in files.entries) 'pkg|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

Future<String> _generated(
  String testClass, {
  Map<String, String> files = const {'bin/app.dart': _app},
}) async {
  final result = await _build(testClass, files: files);
  expect(result.errors, isEmpty);
  return result.readerWriter.testing.readString(
    AssetId('pkg', 'test/spring/shop.test.spring.dart'),
  );
}

Future<String> _error(
  String testClass, {
  Map<String, String> files = const {'bin/app.dart': _app},
}) async {
  final result = await _build(testClass, files: files);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

// One line, without the formatter's line breaks and trailing commas.
String _squash(String source) => source
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r',\s*([)\]}])'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'([(\[{])\s+'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r'\s+([)\]}])'), (m) => m[1]!);

// The generated code's own names without their `$`, so the expectations read
// like the code a user would write.
String _plainNames(String source) => source
    .replaceAll(r'$instance', 'instance')
    .replaceAll(r'$app', 'app')
    .replaceAll(r'$slice', 'slice');

/// `source` (squashed) contains [expected] (squashed the same way).
Matcher _has(String expected) => predicate<String>(
  (source) => _squash(_plainNames(source)).contains(_squash(expected)),
  'contains $expected',
);

// The application's generated file, as far as generated tests use it.
const _appSpring = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

SpringApplication get springApplication => throw UnimplementedError();
void runApplication(List<String> args) {}
''';

void main() {
  test(
    'a @DataTest class starts the slice and runs in a transaction',
    () async {
      final source = await _generated('''
@DataTest()
class ShopTest {
  @Autowired()
  late BookRepository books;

  @Test()
  Future<void> savesABook() async {}
}
''');
      expect(
        source,
        _has(
          "import 'package:spring_boot_starter_data/testing.dart' as _data;",
        ),
      );
      expect(
        source,
        _has(
          "_sbt.group('ShopTest', () { final instance = ShopTest(); "
          'final slice = _data.DataTestSetup(_app0.springApplication); '
          'final app = _sbt.springBootTest(_app0.springApplication, '
          'properties: slice.properties, initializers: [slice.initializer]); '
          '_sbt.setUp(() { instance.books = app.getBean(); }); '
          "_sbt.test('saves a book', () => "
          '_data.runInTestTransaction(app.context, '
          '() => instance.savesABook())); '
          '});',
        ),
      );
      expect(source, contains('from the @DataTest classes of shop_test.dart'));
      expect(
        source,
        contains('Declares the tests of the `@DataTest` classes of'),
      );
    },
  );

  test('a file with both kinds of classes names both', () async {
    final source = await _generated('''
@SpringBootTest()
class WholeTest {
  @Test()
  void works() {}
}

@DataTest()
class SliceTest {
  @Test()
  void works() {}
}
''');
    expect(source, contains('from the @SpringBootTest and @DataTest classes'));
    // Only the slice's tests run in a transaction.
    expect(
      source,
      _has("_sbt.test('works', () => instance.works());"),
    );
    expect(
      source,
      _has(
        "_sbt.test('works', () => "
        '_data.runInTestTransaction(app.context, () => instance.works()));',
      ),
    );
  });

  test('the options of @DataTest and the shared annotations', () async {
    final source = _squash(
      await _generated('''
@DataTest(
  args: ['--a=1'],
  properties: {'b': 2},
  resourceDirectories: ['test/data'],
  include: [PaymentGateway, Clock],
  replaceDatabase: false,
)
@ActiveProfiles(['test'])
@TestPropertySource(properties: {'c': 3}, locations: ['classpath:x.properties'])
class ShopTest {
  @DynamicPropertySource()
  static void props(DynamicPropertyRegistry registry) {}

  @ContextInitializer()
  static void init(ConfigurableApplicationContext context) {}

  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();
}
'''),
    );
    expect(
      source,
      _has(
        'final slice = _data.DataTestSetup(_app0.springApplication, '
        'include: [PaymentGateway, Clock], replaceDatabase: false);',
      ),
    );
    expect(source, _has("args: ['--a=1'],"));
    // The slice's properties first: the test's own may replace them.
    expect(
      source,
      _has("properties: {...slice.properties, ...{'b': 2}, ...{'c': 3}},"),
    );
    expect(source, _has("propertyFiles: ['classpath:x.properties'],"));
    expect(source, _has("resourceDirectories: ['test/data'],"));
    expect(source, _has("profiles: ['test'],"));
    expect(source, _has('dynamicProperties: ShopTest.props,'));
    expect(
      source,
      _has(
        'initializers: [slice.initializer, '
        '_sbt.ApplicationContextInitializer.of(ShopTest.init)]',
      ),
    );
    expect(source, _has("name: 'sandbox'"));
  });

  test('@BeforeEach and @AfterEach run inside the transaction', () async {
    final source = _squash(
      await _generated('''
@DataTest()
class ShopTest {
  @BeforeAll()
  static Future<void> start() async {}

  @BeforeEach()
  void one() {}

  @BeforeEach()
  Future<void> two() async {}

  @AfterEach()
  void clean() {}

  @AfterEach()
  void cleanMore() {}

  @Test()
  void first() {}

  @Test('second')
  @Tag('db')
  void other() {}
}
'''),
    );
    // Not registered with setUp and tearDown: those cannot be in the
    // transaction.
    expect(source, isNot(contains('_sbt.setUp(() => instance.one())')));
    expect(source, isNot(contains('_sbt.tearDown')));
    // BeforeAll stays outside, with the context.
    expect(source, _has('_sbt.setUpAll(() => ShopTest.start());'));
    // @AfterEach in tearDown's order: the last declared first.
    expect(
      source,
      _has(
        "_sbt.test('first', () => _data.runInTestTransaction(app.context, "
        '() => instance.first(), '
        'before: [() => instance.one(), () => instance.two()], '
        'after: [() => instance.cleanMore(), () => instance.clean()]));',
      ),
    );
    expect(
      source,
      _has(
        "_sbt.test('second', () => _data.runInTestTransaction(app.context, "
        '() => instance.other(), '
        'before: [() => instance.one(), () => instance.two()], '
        'after: [() => instance.cleanMore(), () => instance.clean()]), '
        "tags: ['db']);",
      ),
    );
  });

  test('@DirtiesContext, @Disabled and options stay on the test', () async {
    final source = _squash(
      await _generated('''
@DataTest()
class ShopTest {
  @Test()
  @DirtiesContext()
  Future<void> dirties() async {}

  @Test()
  @Disabled('later')
  void skipped() {}
}
'''),
    );
    expect(
      source,
      _has(
        "_sbt.test('dirties', () { app.markDirty(); return "
        '_data.runInTestTransaction(app.context, '
        '() => instance.dirties()); });',
      ),
    );
    expect(
      source,
      _has(
        "_sbt.test('skipped', () => _data.runInTestTransaction(app.context, "
        "() => instance.skipped()), skip: 'later');",
      ),
    );
  });

  test(
    '@DataTest(transactionManager:) names the manager of every test',
    () async {
      final source = await _generated('''
@DataTest(transactionManager: 'archive')
class ShopTest {
  @Test()
  @Commit()
  void committed() {}

  @Test()
  void rolledBack() {}
}
''');
      expect(
        source,
        _has(
          "_sbt.test('committed', () => _data.runInTestTransaction( "
          'app.context, () => instance.committed(), rollback: false, '
          "transactionManager: 'archive'));",
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('rolled back', () => _data.runInTestTransaction( "
          'app.context, () => instance.rolledBack(), '
          "transactionManager: 'archive'));",
        ),
      );
    },
  );

  group('rollback or commit', () {
    test('@Commit and @Rollback(false) commit, the innermost wins', () async {
      final source = _squash(
        await _generated('''
@DataTest()
class ShopTest {
  @Test()
  @Commit()
  void committed() {}

  @Test()
  @Rollback(false)
  void alsoCommitted() {}

  @Test()
  @Rollback()
  void rolledBack() {}

  @Test()
  @Rollback(keep)
  void byConstant() {}

  static const keep = true;

  @Test()
  void byDefault() {}
}
'''),
      );
      expect(
        source,
        _has(
          "_sbt.test('committed', () => _data.runInTestTransaction( "
          'app.context, () => instance.committed(), rollback: false));',
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('also committed', () => _data.runInTestTransaction( "
          'app.context, () => instance.alsoCommitted(), rollback: false));',
        ),
      );
      // Said so: nothing to add.
      expect(
        source,
        _has(
          "_sbt.test('rolled back', () => _data.runInTestTransaction( "
          'app.context, () => instance.rolledBack()));',
        ),
      );
      // A constant of the class is written with its class's name.
      expect(
        source,
        _has(
          "_sbt.test('by constant', () => _data.runInTestTransaction( "
          'app.context, () => instance.byConstant(), '
          'rollback: ShopTest.keep));',
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('by default', () => _data.runInTestTransaction( "
          'app.context, () => instance.byDefault()));',
        ),
      );
    });

    test('on the class: every test commits, a method may roll back', () async {
      final source = _squash(
        await _generated('''
@DataTest()
@Commit()
class ShopTest {
  @Test()
  void committed() {}

  @Test()
  @Rollback()
  void rolledBack() {}
}
'''),
      );
      expect(
        source,
        _has(
          "_sbt.test('committed', () => _data.runInTestTransaction( "
          'app.context, () => instance.committed(), rollback: false));',
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('rolled back', () => _data.runInTestTransaction( "
          'app.context, () => instance.rolledBack()));',
        ),
      );
    });

    test('a @Nested group has the transaction of its tests, with every '
        'level of lifecycle methods', () async {
      final source = _squash(
        await _generated('''
@DataTest()
class ShopTest {
  @BeforeEach()
  void outerBefore() {}

  @AfterEach()
  void outerAfter() {}

  @Test()
  void first() {}

  @Nested('with a book')
  final withBook = WithBook();

  @Nested()
  @Commit()
  final committing = Committing();

  @Nested()
  final deeper = Deeper();
}

class WithBook {
  @BeforeEach()
  void add() {}

  @AfterEach()
  void remove() {}

  @Test()
  void costs() {}

  @Nested()
  final inner = Inner();
}

class Inner {
  @Test()
  void works() {}
}

class Committing {
  @Test()
  void keeps() {}
}

@Commit()
class Deeper {
  @Test()
  void keeps() {}

  @Test()
  @Rollback()
  void undoes() {}
}
'''),
      );
      expect(
        source,
        _has(
          "_sbt.group('with a book', () { "
          "_sbt.test('costs', () => _data.runInTestTransaction( "
          'app.context, () => instance.withBook.costs(), '
          'before: [() => instance.outerBefore(), '
          '() => instance.withBook.add()], '
          'after: [() => instance.withBook.remove(), '
          '() => instance.outerAfter()])); ',
        ),
      );
      // The level of a deeper group: all three, outer first and last.
      expect(
        source,
        _has(
          "_sbt.group('inner', () { _sbt.test('works', "
          '() => _data.runInTestTransaction(app.context, '
          '() => instance.withBook.inner.works(), '
          'before: [() => instance.outerBefore(), '
          '() => instance.withBook.add()], '
          'after: [() => instance.withBook.remove(), '
          '() => instance.outerAfter()])); });',
        ),
      );
      // A @Commit on the field, and one on the nested class.
      expect(
        source,
        _has(
          "_sbt.test('keeps', () => _data.runInTestTransaction( "
          'app.context, () => instance.committing.keeps(), '
          'rollback: false, before: [() => instance.outerBefore()], '
          'after: [() => instance.outerAfter()]));',
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('keeps', () => _data.runInTestTransaction( "
          'app.context, () => instance.deeper.keeps(), '
          'rollback: false, before: [() => instance.outerBefore()], '
          'after: [() => instance.outerAfter()]));',
        ),
      );
      expect(
        source,
        _has(
          "_sbt.test('undoes', () => _data.runInTestTransaction( "
          'app.context, () => instance.deeper.undoes(), '
          'before: [() => instance.outerBefore()], '
          'after: [() => instance.outerAfter()]));',
        ),
      );
    });
  });

  group('the application', () {
    test('a @DataTest names an application anywhere in the package', () async {
      final source = await _generated(
        "@DataTest(application: 'test/data/app/data_app.dart')\n"
        'class ShopTest {}\n',
        files: {
          'bin/app.dart': _app,
          'bin/other.dart': _app,
          'test/data/app/data_app.dart': _app,
        },
      );
      expect(
        source,
        _has("import '../data/app/data_app.spring.dart' as _app0;"),
      );
    });

    test('a path that is no entry point fails', () async {
      expect(
        await _error(
          "@DataTest(application: 'test/data/app/data_app.dart')\n"
          'class ShopTest {}\n',
          files: {
            'bin/app.dart': _app,
            'test/data/app/data_app.dart': 'void main() {}\n',
          },
        ),
        contains(
          "'test/data/app/data_app.dart' is not an entry point with "
          '@SpringBootApplication of this package (bin/app.dart)',
        ),
      );
    });

    test(
      'several applications ask for the name, no application fails',
      () async {
        expect(
          await _error(
            '@DataTest()\nclass ShopTest {}\n',
            files: {'bin/app.dart': _app, 'bin/admin.dart': _app},
          ),
          allOf(
            contains('Several applications in this package'),
            contains("@DataTest(application: 'bin/admin.dart')"),
          ),
        );
        expect(
          await _error('@DataTest()\nclass ShopTest {}\n', files: {}),
          contains('@DataTest needs a @SpringBootApplication entry point'),
        );
      },
    );

    test('@SpringBootTest names an application anywhere too', () async {
      final source = await _generated(
        "@SpringBootTest(application: 'example/main.dart')\n"
        'class ShopTest {}\n',
        files: {'bin/app.dart': _app, 'example/main.dart': _app},
      );
      expect(source, _has("import '../../example/main.spring.dart' as _app0;"));
    });
  });

  group('build errors', () {
    test('@DataTest with @SpringBootTest', () async {
      expect(
        await _error('@DataTest()\n@SpringBootTest()\nclass ShopTest {}\n'),
        allOf(
          contains('@DataTest and @SpringBootTest on one class'),
          contains('test/shop_test.dart:'),
        ),
      );
    });

    test('@DataTest on a method', () async {
      expect(
        await _error('''
@DataTest()
class ShopTest {
  @DataTest()
  @Test()
  void pays() {}
}
'''),
        contains('@DataTest on a method: it belongs to the class'),
      );
    });

    final misplaced = {
      '@SpringBootTest()\nclass ShopTest {\n  @Test()\n  @Commit()\n'
              '  void pays() {}\n}\n':
          '@Commit needs a @DataTest class',
      '@SpringBootTest()\n@Rollback(false)\nclass ShopTest {}\n':
          '@Rollback needs a @DataTest class',
      '@SpringBootTest()\nclass ShopTest {\n  @Nested()\n  @Commit()\n'
              '  final inner = Inner();\n}\nclass Inner {}\n':
          '@Commit needs a @DataTest class',
      '@DataTest()\nclass ShopTest {\n  @Commit()\n  void helper() {}\n}\n':
          '@Commit on helper, which is not a @Test method',
      '@DataTest()\nclass ShopTest {\n  @Rollback()\n  final x = 1;\n}\n':
          '@Rollback on the field x, which is not @Nested',
      '@DataTest()\nclass ShopTest {\n  @Test()\n  @Commit()\n'
              '  @Rollback()\n  void pays() {}\n}\n':
          '@Commit and @Rollback on the same element',
    };
    for (final MapEntry(key: testClass, value: message) in misplaced.entries) {
      test(message, () async {
        final error = await _error(testClass);
        expect(error, contains(message));
        expect(error, contains('test/shop_test.dart:'));
      });
    }
  });

  test('a test file without a test class gets no output', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    final result = await testBuilder(
      SpringTestBuilder(),
      {
        // Mentions the annotation, declares none.
        'pkg|test/plain_test.dart':
            '// @DataTest() is for classes.\nvoid main() {}\n',
        'pkg|bin/app.dart': _app,
      },
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(
      result.readerWriter.testing.assets.where(
        (a) => a.path.endsWith('.test.spring.dart'),
      ),
      isEmpty,
    );
  });

  // The generated file calls the data starter's real API.
  test('the generated file compiles against the starters', () async {
    const testClass = '''
@DataTest(include: [Clock], replaceDatabase: false)
@Rollback(false)
@ActiveProfiles(['test'])
class ShopTest {
  @Autowired()
  late Clock clock;

  @BeforeEach()
  void before() {}

  @AfterEach()
  Future<void> after() async {}

  @Test()
  Future<void> first() async {}

  @Test()
  @Rollback()
  void second() {}

  @Nested()
  @Commit()
  final inner = Inner();
}

class Inner {
  @BeforeEach()
  void prepare() {}

  @Test()
  void works() {}
}

abstract class Clock {}
''';
    final source = await _generated(testClass);
    final errors = await resolveSources<List<String>>(
      {
        'pkg|bin/app.spring.dart': _appSpring,
        'pkg|test/shop_test.dart':
            '$_imports\n$testClass\nvoid main() => runSpringTests();\n',
        'pkg|test/spring/shop.test.spring.dart': source,
      },
      (resolver) async {
        final messages = <String>[];
        for (final path in [
          'test/shop_test.dart',
          'test/spring/shop.test.spring.dart',
        ]) {
          final library = await resolver.libraryFor(AssetId('pkg', path));
          final result = await library.session.getErrors(
            library.firstFragment.source.fullName,
          );
          if (result case ErrorsResult(:final diagnostics)) {
            messages.addAll([
              for (final diagnostic in diagnostics)
                if (diagnostic.severity == Severity.error)
                  '$path: ${diagnostic.message}',
            ]);
          }
        }
        return messages;
      },
      rootPackage: 'pkg',
      resolverFor: 'pkg|test/spring/shop.test.spring.dart',
      readAllSourcesFromFilesystem: true,
    );
    expect(errors, isEmpty, reason: source);
  });
}
