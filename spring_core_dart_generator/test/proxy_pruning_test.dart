// Proxies only where something advises: an application with no aspect,
// whose only advice is the starters' annotation-driven advisors
// (`@Transactional`, `@Cacheable`, `@Validated`), gets proxy classes for the
// beans carrying those annotations and for nothing else.
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

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

@ConfigurationProperties('shop')
@Validated()
class ShopSettings {
  String name = '';
}

// Private members: a subclass proxy (the bean is created as it).
@Service()
class Counted {
  int _n = 0;
  int next() => ++_n;
}

@Service()
class CountedOrders {
  int _n = 0;
  @Transactional()
  Future<int> place() async => ++_n;
  int count() => _n;
}

@Service()
class MixedOrders {
  @Transactional()
  Future<void> place() async {}
  int count() => 0;
  String get label => '';
}
''';

Future<String> _build(String beans) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {'pkg|bin/main.dart': _main, 'pkg|lib/src/beans.dart': beans},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return readerWriter.testing.readString(
    result.outputs.singleWhere(
      (o) => o.path == 'bin/spring_gen/main.spring.dart',
    ),
  );
}

const _advised = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

class Tag {
  const Tag();
}

class Counter implements MethodInterceptor {
  const Counter();
  @override
  Object? invoke(MethodInvocation invocation) => invocation.proceed();
}

@Service()
class BookController {
  int list() => 0;
}

@Service()
class Mail {
  int send() => 0;
}

@Service()
class Labelled {
  @Tag()
  int run() => 0;
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
    result.outputs.singleWhere(
      (o) => o.path == 'bin/spring_gen/main.spring.dart',
    ),
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

  test('a subclass proxy nothing advises is pruned too', () {
    expect(output, isNot(proxyOf('Counted')));
    final normalized = output.replaceAll(RegExp(r'\b_i\d+\.|\s'), '');
    // Created as its own class.
    expect(normalized, contains('create:(r)=>Counted()'));
    expect(
      normalized,
      matches(
        RegExp(
          r'BeanDefinition<Counted>\((?:(?!BeanDefinition<).)*'
          r'AopProxyFactory\.pruned\(\)',
        ),
      ),
    );
    // An advised one keeps it, and is created as the generated subclass.
    expect(output, proxyOf('CountedOrders'));
    expect(normalized, contains(r'create:(r)=>_$CountedOrdersProxy()'));
  });

  test('only the members advice may match run through it', () {
    final normalized = output.replaceAll(RegExp(r'\b_i\d+\.|\s'), '');
    String proxy(String name) => normalized
        .split(RegExp(r'class_\$|///Beansfound'))
        .singleWhere((part) => part.startsWith('${name}Proxy'));
    // A wrapper forwards the others to the target, without signatures.
    final mixed = proxy('MixedOrders');
    expect(mixed, contains('this.aopInvoker.invokeAsync<void>('));
    expect(mixed, contains('intcount()=>this._target.count();'));
    expect(mixed, contains('Stringgetlabel=>this._target.label;'));
    expect(normalized, contains("MethodSignature.of(r'place',"));
    expect(normalized, isNot(contains("MethodSignature.of(r'count',")));
    expect(normalized, isNot(contains("MethodSignature.of(r'label',")));
    // A subclass inherits them.
    final counted = proxy('CountedOrders');
    expect(counted, contains('place()'));
    expect(counted, isNot(contains('count()')));
  });

  test('the annotations of the starters keep the proxy', () {
    expect(output, proxyOf('Orders'));
    expect(output, proxyOf('ClassLevel'));
    expect(output, proxyOf('Prices'));
    expect(output, proxyOf('Checked'));
  });

  test('@Validated on configuration properties keeps no proxy', () {
    // It validates the bound values at startup; method validation leaves
    // configuration properties out.
    expect(output, isNot(proxyOf('ShopSettings')));
  });

  test('a subclass of an advised annotation keeps the proxy', () {
    expect(output, proxyOf('Admin'));
  });

  test('a pruned bean is marked, for an advisor added at run time', () {
    // `AopProxyFactory.prunedReason` says why at run time.
    expect(
      output.replaceAll(RegExp(r'\b_i\d+\.|\s'), ''),
      matches(
        RegExp(
          r'BeanDefinition<Plain>\((?:(?!BeanDefinition<).)*'
          r'AopProxyFactory\.pruned\(\)',
        ),
      ),
    );
  });

  group('advisor beans of the application', () {
    Matcher proxyOf(String name) => contains('class _\$${name}Proxy');

    test('a constant expression: only the beans it matches', () async {
      final output = await _build('''
$_advised
@Configuration()
class Metrics {
  @Bean()
  PointcutAdvisor metricsAdvisor() => DefaultPointcutAdvisor(
    ExpressionPointcut('within(*Controller)'),
    const Counter(),
  );
}
''');
      expect(output, proxyOf('BookController'));
      expect(output, isNot(proxyOf('Mail')));
      expect(output, isNot(proxyOf('Labelled')));
    });

    test('an annotation pointcut: the beans with the annotation', () async {
      final output = await _build('''
$_advised
@Configuration()
class Tags {
  @Bean()
  PointcutAdvisor tagsAdvisor() => DefaultPointcutAdvisor(
    const AnnotationMatchingPointcut<Tag>(),
    const Counter(),
  );
}
''');
      expect(output, proxyOf('Labelled'));
      expect(output, isNot(proxyOf('Mail')));
      expect(output, isNot(proxyOf('BookController')));
    });

    test(
      'an expression the build cannot read: every bean keeps its proxy',
      () async {
        final output = await _build('''
$_advised
const where = 'within(*Controller)';

@Configuration()
class Metrics {
  final expression = where;

  @Bean()
  PointcutAdvisor metricsAdvisor() => DefaultPointcutAdvisor(
    ExpressionPointcut(expression),
    const Counter(),
  );
}
''');
        expect(output, proxyOf('Mail'));
        expect(output, proxyOf('BookController'));
      },
    );
  });

  group('@ComponentScan modules', () {
    const scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';
    const beans = '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

@Service()
class Plain {
  int next() => 0;
}

@Service()
class Orders {
  @Transactional()
  Future<void> place() async {}
}
''';

    Future<String> module({required bool application}) async {
      final readerWriter = TestReaderWriter(
        rootPackage: 'pkg',
        flattenOutput: true,
      );
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        SpringBuilder(),
        {
          if (application)
            'pkg|pubspec.yaml':
                'name: pkg\npublish_to: none\n'
                'dependencies:\n  spring_boot_starter_data: any\n',
          'pkg|lib/src/scan.dart': scan.replaceAll(
            'beans.spring',
            'scan.spring',
          ),
          'pkg|lib/src/beans.dart': beans,
        },
        rootPackage: 'pkg',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.errors, isEmpty);
      return readerWriter.testing.readString(
        result.outputs.singleWhere(
          (o) => o.path == 'lib/spring_gen/src/scan.spring.dart',
        ),
      );
    }

    test('of an application are pruned: nothing imports them', () async {
      final output = await module(application: true);
      expect(output, contains(r'class _$OrdersProxy'));
      expect(output, isNot(contains(r'class _$PlainProxy')));
    });

    test('of a library keep every proxy: any module may import them', () async {
      final output = await module(application: false);
      expect(output, contains(r'class _$OrdersProxy'));
      expect(output, contains(r'class _$PlainProxy'));
    });
  });
}
