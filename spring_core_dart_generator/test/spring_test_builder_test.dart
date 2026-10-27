// Test classes (@SpringBootTest): what <name>.test.spring.dart declares
// for each annotation, and the build errors. Running the generated tests
// is covered by example/server_guide/test/*_class_test.dart.
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

// The generated code's own names without their `$` (`$instance` →
// `instance`), so the expectations read like the code a user would write;
// 'generated names cannot clash' checks the real names.
String _plainNames(String source) => source
    .replaceAll(r'$instance', 'instance')
    .replaceAll(r'$app', 'app')
    .replaceAll(r'$logs', 'logs');

/// `source` (squashed) contains [expected] (squashed the same way).
Matcher _has(String expected) => predicate<String>(
  (source) => _squash(_plainNames(source)).contains(_squash(expected)),
  'contains $expected',
);

void main() {
  test('a file without @SpringBootTest classes gets no output', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    final result = await testBuilder(
      SpringTestBuilder(),
      {
        'pkg|test/plain_test.dart': 'void main() {}\n',
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

  test('imports the test file, its imports and the application', () async {
    final source = await _generated('''
@SpringBootTest()
class ShopTest {}
''');
    expect(source, _has("import 'package:test/test.dart' as t;"));
    expect(source, _has("import '../shop_test.dart';"));
    expect(source, _has("import '../../bin/app.spring.dart' as _app0;"));
    expect(source, isNot(contains('shop.test.spring.dart')));
    // Copied imports may be unused here: a warning type=lint does not
    // cover (an app analyzed with --fatal-warnings would fail).
    expect(source, contains('unused_import'));
    expect(
      source,
      _has(
        "_sbt.group('ShopTest', () { final instance = ShopTest(); "
        'final app = _sbt.springBootTest(_app0.springApplication); });',
      ),
    );
  });

  test('an application in lib/ is imported as a package', () async {
    final source = await _generated(
      '@SpringBootTest()\nclass ShopTest {}\n',
      files: {'lib/main.dart': _app},
    );
    expect(source, _has("import 'package:pkg/main.spring.dart' as _app0;"));
  });

  test('the class annotations become springBootTest arguments', () async {
    final source = _squash(
      await _generated('''
@SpringBootTest(
  args: ['--a=1'],
  properties: {'b': 2},
  resourceDirectories: ['test/data'],
)
@ActiveProfiles(['dev', 'test'])
@TestPropertySource(properties: {'c': 3}, locations: ['classpath:x.properties'])
@TestEnvironment({'D': '4'})
class ShopTest {
  @DynamicPropertySource()
  static void one(DynamicPropertyRegistry registry) {}

  @DynamicPropertySource()
  static void two(DynamicPropertyRegistry registry) {}

  @ContextInitializer()
  static void init(ConfigurableApplicationContext context) {}
}
'''),
    );
    expect(source, _has("args: ['--a=1'],"));
    expect(source, _has("properties: {...{'b': 2}, ...{'c': 3}},"));
    expect(source, _has("propertyFiles: ['classpath:x.properties'],"));
    expect(source, _has("resourceDirectories: ['test/data'],"));
    expect(source, _has("profiles: ['dev', 'test'],"));
    expect(source, _has("systemEnvironment: {'D': '4'},"));
    expect(
      source,
      _has(
        'dynamicProperties: (registry) { ShopTest.one(registry); '
        'ShopTest.two(registry); },',
      ),
    );
    expect(
      source,
      _has(
        'initializers: [_sbt.ApplicationContextInitializer.of(ShopTest.init)]',
      ),
    );
  });

  test('a web environment, MockMvc and @LocalServerPort', () async {
    final source = _squash(
      await _generated('''
@SpringBootTest(webEnvironment: WebEnvironment.randomPort)
@AutoConfigureMockMvc()
class ApiTest {
  @Autowired()
  late MockMvc mvc;

  @LocalServerPort()
  late int port;
}
'''),
    );
    expect(source, _has('webEnvironment: WebEnvironment.randomPort'));
    expect(source, _has('instance.mvc = app.mockMvc;'));
    expect(source, _has('instance.port = app.localServerPort;'));
  });

  test('fields are injected before every test, by kind', () async {
    final source = _squash(
      await _generated(r'''
@SpringBootTest()
class ShopTest {
  @Autowired()
  late Checkout checkout;

  @Autowired()
  @Qualifier('offline')
  late PaymentGateway offline;

  @Autowired()
  late Mailer? mailer;

  @Autowired()
  late List<PaymentGateway> gateways;

  @Autowired()
  late ApplicationContext context;

  @Autowired()
  late SpringBootTestContext app;

  @Autowired()
  late Environment environment;

  @Value(r'${shop.name}')
  late String name;

  @Value(r'${shop.missing}')
  late String? missing;

  @CapturedOutput()
  late CapturedLogs logs;
}
'''),
    );
    expect(source, _has('final logs = _sbt.captureLogs();'));
    expect(
      source,
      _has(
        '_sbt.setUp(() { instance.checkout = app.getBean(); '
        "instance.offline = app.getBean(qualifier: 'offline'); "
        'instance.mailer = app.findBean(); '
        'instance.gateways = app.getBeans(); '
        'instance.context = app.context; '
        'instance.app = app; '
        'instance.environment = app.environment; '
        r"instance.name = app.value(r'${shop.name}'); "
        r"instance.missing = app.optionalValue(r'${shop.missing}'); "
        'instance.logs = logs; });',
      ),
    );
  });

  test('@TestBean fields become overrides', () async {
    final source = _squash(
      await _generated('''
@SpringBootTest()
class ShopTest {
  @TestBean(name: 'sandbox')
  final gateway = FakeGateway();

  @TestBean()
  final Clock? clock = FixedClock();

  @TestBean(type: PaymentGateway)
  final FakeGateway other = FakeGateway();
}
'''),
    );
    expect(
      source,
      _has(
        'overrides: [ _sbt.BeanOverride.named(instance.gateway, name: '
        "'sandbox'), "
        '_sbt.BeanOverride<Clock>(instance.clock), '
        '_sbt.BeanOverride<PaymentGateway>(instance.other), ]',
      ),
    );
  });

  test('tests, names, lifecycle and options', () async {
    final source = _squash(
      await _generated(r'''
@SpringBootTest()
@DirtiesContext()
@Tag('shop')
class ShopTest {
  @BeforeAll()
  static Future<void> start() async {}

  @AfterAll()
  static void stop() {}

  @BeforeEach()
  void before() {}

  @AfterEach()
  Future<void> after() async {}

  @Test()
  void paysThroughTheFake() {}

  @Test('named')
  @DirtiesContext()
  Future<void> second() async {}

  @Test()
  @DisplayName("it's \$5")
  @Disabled('later')
  @Tag('slow')
  @Tag('db')
  @TestOptions(timeout: t.Timeout(Duration(seconds: 5)), retry: 2)
  void third() {}

  @Test()
  @Disabled()
  void fourth() {}
}
'''),
    );
    expect(source, _has('_sbt.setUpAll(() => ShopTest.start());'));
    expect(source, _has('_sbt.tearDownAll(() => ShopTest.stop());'));
    // Before the context: tearDownAll runs in reverse order.
    expect(
      source.indexOf('tearDownAll'),
      lessThan(source.indexOf('springBootTest(')),
    );
    expect(source, _has('_sbt.setUp(app.markDirty);'));
    expect(source, _has('_sbt.setUp(() => instance.before());'));
    expect(source, _has('_sbt.tearDown(() => instance.after());'));
    expect(
      source,
      _has(
        "_sbt.test('pays through the fake', () => "
        'instance.paysThroughTheFake());',
      ),
    );
    expect(
      source,
      _has(
        "_sbt.test('named', () { app.markDirty(); return instance.second(); "
        '});',
      ),
    );
    expect(
      source,
      _has(
        r'''_sbt.test("it's \$5", () => instance.third(), skip: 'later', '''
        "tags: ['slow', 'db'], timeout: t.Timeout(Duration(seconds: 5)), "
        'retry: 2);',
      ),
    );
    expect(
      source,
      _has("_sbt.test('fourth', () => instance.fourth(), skip: true);"),
    );
    expect(source, _has("}, tags: ['shop']);"));
  });

  test('@Nested fields become groups with the same context', () async {
    final source = _squash(
      await _generated('''
@SpringBootTest()
class ShopTest {
  @Test()
  void first() {}

  @Nested('with one book')
  final withOneBook = WithOneBook();

  @Nested()
  final emptyBasket = EmptyBasket();
}

class WithOneBook {
  @Autowired()
  late Basket basket;

  @BeforeEach()
  void add() {}

  @Test()
  void costs() {}

  @Nested()
  final deeper = Deeper();
}

class Deeper {
  @Test()
  void works() {}
}

@Disabled('soon')
class EmptyBasket {
  @Test()
  void isEmpty() {}
}
'''),
    );
    expect(
      source,
      _has(
        "_sbt.group('with one book', () { _sbt.setUp(() { "
        'instance.withOneBook.basket = app.getBean(); }); '
        '_sbt.setUp(() => instance.withOneBook.add()); '
        "_sbt.test('costs', () => instance.withOneBook.costs()); "
        "_sbt.group('deeper', () { "
        "_sbt.test('works', () => instance.withOneBook.deeper.works()); }); "
        '});',
      ),
    );
    expect(
      source,
      _has(
        "_sbt.group('empty basket', () { "
        "_sbt.test('is empty', () => instance.emptyBasket.isEmpty()); "
        "}, skip: 'soon');",
      ),
    );
    // In the order of the class.
    expect(
      source.indexOf("'first'"),
      lessThan(source.indexOf("'with one book'")),
    );
  });

  test(
    'relative imports of the test are re-pointed from test/spring/',
    () async {
      final source = await _generated(
        "import 'support.dart';\nimport '../tool/fixtures.dart' as f;\n"
        '@SpringBootTest()\nclass ShopTest {}\n',
      );
      expect(source, _has("import '../support.dart';"));
      expect(source, _has("import '../../tool/fixtures.dart' as f;"));
    },
  );

  test('a test in a folder keeps the folder under test/spring/', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    final result = await testBuilder(
      SpringTestBuilder(),
      {
        'pkg|test/orders/basket_test.dart':
            "import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';\n"
            "import '../spring/orders/basket.test.spring.dart';\n"
            "import 'helpers.dart';\n"
            '@SpringBootTest()\nclass BasketTest {}\n',
        'pkg|bin/app.dart': _app,
      },
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    expect(result.errors, isEmpty);
    final source = result.readerWriter.testing.readString(
      AssetId('pkg', 'test/spring/orders/basket.test.spring.dart'),
    );
    expect(source, _has("import '../../orders/basket_test.dart';"));
    expect(source, _has("import '../../orders/helpers.dart';"));
    expect(source, _has("import '../../../bin/app.spring.dart' as _app0;"));
    expect(source, isNot(contains('basket.test.spring.dart')));
    expect(
      springTestOutput(AssetId('pkg', 'test/orders/basket_test.dart')).path,
      'test/spring/orders/basket.test.spring.dart',
    );
  });

  test('two test classes in one file', () async {
    final source = await _generated('''
@SpringBootTest()
class ATest {}

@SpringBootTest()
class BTest {}
''');
    expect(source, _has("_sbt.group('ATest'"));
    expect(source, _has("_sbt.group('BTest'"));
  });

  group('the application', () {
    test('several entry points: one is named', () async {
      final source = await _generated(
        "@SpringBootTest(application: 'bin/admin.dart')\nclass ShopTest {}\n",
        files: {'bin/app.dart': _app, 'bin/admin.dart': _app},
      );
      expect(source, _has("import '../../bin/admin.spring.dart' as _app0;"));
    });

    test('several entry points without a name fail', () async {
      expect(
        await _error(
          '@SpringBootTest()\nclass ShopTest {}\n',
          files: {'bin/app.dart': _app, 'bin/admin.dart': _app},
        ),
        allOf(
          contains('Several applications in this package'),
          contains("@SpringBootTest(application: 'bin/admin.dart')"),
        ),
      );
    });

    test('no entry point fails', () async {
      expect(
        await _error('@SpringBootTest()\nclass ShopTest {}\n', files: {}),
        contains('No application in this package'),
      );
    });

    test('a named file that is not an entry point fails', () async {
      expect(
        await _error(
          "@SpringBootTest(application: 'bin/nope.dart')\nclass ShopTest {}\n",
        ),
        contains("'bin/nope.dart' is not an entry point"),
      );
    });

    test('a comment mentioning the annotation is not an entry point', () async {
      final source = await _generated(
        '@SpringBootTest()\nclass ShopTest {}\n',
        files: {
          'bin/app.dart': _app,
          'lib/doc.dart': '/// @SpringBootApplication()\nvoid f() {}\n',
        },
      );
      expect(source, _has('../bin/app.spring.dart'));
    });
  });

  group('build errors', () {
    final cases = {
      '@Autowired()\n  Checkout checkout = Checkout();':
          "@Autowired field 'checkout' must be late and not final",
      '@Autowired()\n  late final Checkout checkout;':
          "@Autowired field 'checkout' must be late and not final",
      '@Autowired()\n  late Checkout _checkout;': "'_checkout' is private",
      '@Autowired()\n  late var checkout;':
          "@Autowired field 'checkout' needs its type written",
      '@TestBean()\n  late PaymentGateway gateway;':
          "@TestBean field 'gateway' needs a value",
      '@TestBean()\n  final gateway = FakeGateway();':
          "@TestBean field 'gateway' needs the type of the bean it replaces",
      '@BeforeAll()\n  void start() {}':
          '@BeforeAll method start must be static',
      '@AfterAll()\n  void stop() {}': '@AfterAll method stop must be static',
      '@DynamicPropertySource()\n  void p(DynamicPropertyRegistry r) {}':
          '@DynamicPropertySource method p must be static',
      '@BeforeEach()\n  static void b() {}':
          '@BeforeEach method b must not be static',
      '@Test()\n  void pays(int amount) {}': '@Test method pays has parameters',
      '@Test()\n  void _pays() {}': "'_pays' is private",
      "@Test()\n  @ActiveProfiles(['x'])\n  void pays() {}":
          '@ActiveProfiles on a method: it belongs to the class',
      '@Disabled()\n  void helper() {}':
          '@Disabled on helper, which is not a @Test method',
      '@Nested()\n  final inner = Missing();':
          "@Nested field 'inner' must be created with a class of this file",
      'ShopTest(this.x);\n  final int x;':
          "'ShopTest' needs a constructor without required parameters",
    };
    for (final MapEntry(key: member, value: message) in cases.entries) {
      test(message, () async {
        final error = await _error(
          '@SpringBootTest()\nclass ShopTest {\n  $member\n}\n',
        );
        expect(error, contains(message));
        expect(error, contains('test/shop_test.dart:'));
      });
    }

    test('@TestBean in a @Nested class', () async {
      expect(
        await _error('''
@SpringBootTest()
class ShopTest {
  @Nested()
  final inner = Inner();
}

class Inner {
  @TestBean()
  final PaymentGateway gateway = FakeGateway();
}
'''),
        contains("@TestBean field 'gateway' in a @Nested class"),
      );
    });
  });

  test('a test file not importing its generated file gets a warning', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    final logs = <String>[];
    await testBuilder(
      SpringTestBuilder(),
      {
        'pkg|test/shop_test.dart':
            "import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';\n"
            '@SpringBootTest()\nclass ShopTest {}\n',
        'pkg|bin/app.dart': _app,
      },
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
      onLog: (record) => logs.add(record.message),
    );
    expect(
      logs.join('\n'),
      contains(
        "does not import 'spring/shop.test.spring.dart': add import "
        "'spring/shop.test.spring.dart';",
      ),
    );
  });

  group('review fixes', () {
    test("generated names cannot clash with the user's", () async {
      final source = await _generated('''
@SpringBootTest()
class ShopTest {
  @TestBean(type: Clock)
  final FixedClock clock = FixedClock();
}
''');
      expect(source, contains(r'final $instance = ShopTest();'));
      expect(source, contains(r'final $app = _sbt.springBootTest('));
    });

    test('@CapturedOutput in a @Nested class', () async {
      final source = await _generated('''
@SpringBootTest()
class OuterTest {
  @Nested()
  final inner = Inner();
}

class Inner {
  @CapturedOutput()
  late CapturedLogs logs;

  @Test()
  void t() {}
}
''');
      expect(source, contains(r'final $logs = _sbt.captureLogs();'));
      expect(source, contains(r'$instance.inner.logs = $logs;'));
    });

    test('static members in member annotations are qualified', () async {
      final source = await _generated('''
@SpringBootTest()
class ShopTest {
  static const slow = 'slow';
  static const name = 'sandbox';

  @TestBean(name: name)
  final gateway = FakeGateway();

  @Test()
  @Tag(slow)
  void works() {}
}
''');
      expect(source, contains('tags: [ShopTest.slow]'));
      expect(source, contains('name: ShopTest.name'));
    });

    test('a private name in an annotation fails the build', () async {
      expect(
        await _error('''
const _env = {'A': 'b'};

@SpringBootTest()
@TestEnvironment(_env)
class ShopTest {}
'''),
        contains("'_env' is private to the test file"),
      );
    });

    test('Set, Map and ObjectProvider fields', () async {
      final source = await _generated('''
@SpringBootTest()
class ShopTest {
  @Autowired()
  late Set<Gateway> set;

  @Autowired()
  late Map<String, Gateway> map;

  @Autowired()
  late ObjectProvider<Gateway> provider;
}
''');
      expect(source, contains(r'$app.getBeans<Gateway>().toSet()'));
      expect(source, contains(r'$app.context.getBeansOfType<Gateway>()'));
      expect(source, contains(r'$app.context.getBeanProvider()'));
    });

    test('members of a superclass in the file are inherited', () async {
      final source = await _generated('''
class BaseTest {
  @Autowired()
  late Checkout checkout;

  @BeforeAll()
  static void start() {}

  @Test()
  void inherited() {}
}

@SpringBootTest()
class ShopTest extends BaseTest {
  @Test()
  void own() {}
}
''');
      expect(source, contains(r'$instance.checkout = $app.getBean();'));
      expect(source, contains('_sbt.setUpAll(() => BaseTest.start());'));
      expect(source, contains(r'() => $instance.inherited()'));
      expect(source.indexOf("'inherited'"), lessThan(source.indexOf("'own'")));
    });

    test('a class the generated code cannot create fails the build', () async {
      expect(
        await _error('@SpringBootTest()\nclass _ShopTest {}\n'),
        contains("'_ShopTest' is private"),
      );
      expect(
        await _error(
          '@SpringBootTest()\nclass ShopTest {\n  ShopTest.create();\n}\n',
        ),
        contains("'ShopTest' has no unnamed constructor"),
      );
    });

    test('conditional imports are re-pointed too', () async {
      final source = await _generated(
        "import 'helper.dart' if (dart.library.io) 'helper_io.dart';\n"
        '@SpringBootTest()\nclass ShopTest {}\n',
      );
      expect(
        source,
        contains(
          "import '../helper.dart' if (dart.library.io) '../helper_io.dart';",
        ),
      );
    });

    test('test names split acronyms', () async {
      final source = await _generated('''
@SpringBootTest()
class ShopTest {
  @Test()
  void addsABook() {}

  @Test()
  void readsURLService() {}
}
''');
      expect(source, contains("'adds a book'"));
      expect(source, contains("'reads url service'"));
    });

    test('the entry point is found as syntax, not by text', () async {
      final source = await _generated(
        '@SpringBootTest()\nclass ShopTest {}\n',
        files: {
          'bin/app.dart':
              "import 'package:spring_boot_dart/spring_boot_dart.dart';\n"
              "import 'app.spring.dart';\n"
              "@pragma('vm:entry-point') @SpringBootApplication()\n"
              'void main(List<String> args) => runApplication(args);\n',
          'lib/template.dart': "const template = '''\n@SpringBootApplication()\nvoid main() {}\n''';\n",
        },
      );
      expect(source, contains("import '../../bin/app.spring.dart' as _app0;"));
    });

    test('annotations on a @Nested field apply to its group', () async {
      final source = await _generated('''
@SpringBootTest()
class ShopTest {
  @Nested()
  @Disabled('off')
  @Tag('slow')
  @DirtiesContext()
  final inner = Inner();
}

class Inner {
  @Test()
  void t() {}
}
''');
      expect(source, contains(r'_sbt.setUp($app.markDirty);'));
      expect(source, contains("skip: 'off'"));
      expect(source, contains("tags: ['slow']"));
    });
  });
}
