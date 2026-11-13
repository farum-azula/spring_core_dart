// The generator for spring_boot_starter_flutter_signals: a bean with a
// @Signal, @Computed or @Effect member gets a proxy that extends it, with
// every member kept and its own calls advised; the type arguments of its
// getters are written for typed collections; a misplaced annotation fails
// the build. The starter is stubbed: the generator knows it by address.
import 'dart:isolate';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _starter = 'spring_boot_starter_flutter_signals';

const _stubs = {
  '$_starter|lib/src/annotations.dart': '''
import 'package:spring_core_dart/spring_core_dart.dart';

@ProxyTargetClass()
class Signal {
  const Signal();
}

@ProxyTargetClass()
class Computed {
  const Computed();
}

@BeanMethodAnnotation()
@ProxyTargetClass()
class Effect {
  const Effect();
}
''',
  '$_starter|lib/$_starter.dart': '''
export 'src/annotations.dart';
''',
};

const _header =
    '''
import 'package:$_starter/$_starter.dart';
import 'package:spring_core_dart/spring_core_dart.dart';
''';

Future<PackageConfig> _packageConfig() async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  return PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != _starter) package,
    Package(
      _starter,
      Uri.parse('file:///$_starter/'),
      packageUriRoot: Uri.parse('file:///$_starter/lib/'),
    ),
  ]);
}

Future<TestBuilderResult> _build(String beans) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
      ..._stubs,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: await _packageConfig(),
    flattenOutput: true,
  );
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

/// The generated module of [beans] (normalized), after checking that it
/// compiles against the stubs.
Future<String> _generate(String beans) async {
  final result = await _build(beans);
  expect(result.errors, isEmpty);
  const path = 'lib/spring_gen/src/beans.spring.dart';
  final output = result.readerWriter.testing.readString(
    result.outputs.singleWhere((o) => o.path == path),
  );
  final errors = await resolveSources<List<String>>(
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': '$_header$beans',
      'pkg|$path': output,
      ..._stubs,
    },
    (resolver) async {
      final library = await resolver.libraryFor(AssetId('pkg', path));
      final errors = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (errors case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|$path',
    packageConfig: await _packageConfig(),
    readAllSourcesFromFilesystem: true,
  );
  expect(errors, isEmpty, reason: output);
  return _normalize(output);
}

Future<String> _errors(String beans) async {
  final result = await _build(beans);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  group('the proxy of a bean with followed state', () {
    test('extends the class though it has no private member, keeps every '
        'member and advises its own calls', () async {
      final output = await _generate('''
class Book {
  const Book(this.title);
  final String title;
}

@Component()
class Basket {
  @Signal()
  List<Book> items = [];

  @Signal()
  String? coupon;

  @Computed()
  int get count => items.length;

  @Effect()
  void save() {}

  // No annotation: still in the proxy, so its assignments are one change.
  void clear() => coupon = null;
}
''');
      expect(output, _has(r'class _$BasketProxy extends Basket with'));
      expect(output, _has('adviseSelfCalls: true'));
      // Every member, also the one without an annotation.
      expect(output, _has('@override void clear()'));
      expect(output, _has('@override set coupon(String? value)'));
      expect(output, _has('@override int get count'));
      // The element type of the list, for a typed collection.
      expect(
        output,
        _has('returnTypeArguments: [TypeCapture<Book>()]'),
      );
      // The effect is found as an annotated method.
      expect(output, _has('annotations: [Effect()]'));
    });

    test('a bean without such a member is as before', () async {
      final output = await _generate('''
@Component()
class Plain {
  int count = 0;

  int twice() => count * 2;
}
''');
      expect(output, isNot(_has('adviseSelfCalls')));
      expect(output, isNot(_has('TypeCapture')));
    });

    test('the type arguments of a map, and none for a plain type', () async {
      final output = await _generate('''
@Component()
class Prices {
  @Signal()
  Map<String, double> byIsbn = {};

  @Signal()
  int total = 0;
}
''');
      expect(
        output,
        _has(
          'returnTypeArguments: [TypeCapture<String>(), TypeCapture<double>()]',
        ),
      );
      expect(_normalize('TypeCapture<').allMatches(output), hasLength(2));
    });

    test('a class that cannot be extended fails the build', () async {
      final errors = await _errors('''
@Component()
final class Basket {
  @Signal()
  int count = 0;
}
''');
      expect(errors, contains('@Signal on a member of Basket'));
      expect(errors, contains('final'));
    });
  });

  group('a misplaced annotation', () {
    Future<String> inBean(String members) => _errors('''
@Component()
class Basket {
$members
}
''');

    test('@Signal on a private field', () async {
      expect(
        await inBean(
          '@Signal()\n  int _count = 0;\n  int get count => _count;',
        ),
        allOf(
          contains('@Signal on the private field Basket._count'),
          contains('Make the field public'),
        ),
      );
    });

    test('@Signal on a final field', () async {
      expect(
        await inBean('@Signal()\n  final int count = 0;'),
        contains('@Signal on the final field Basket.count'),
      );
    });

    test('@Signal on a getter', () async {
      expect(
        await inBean('@Signal()\n  int get count => 0;'),
        allOf(
          contains('@Signal on the getter Basket.count'),
          contains('@Computed'),
        ),
      );
    });

    test('@Computed with parameters', () async {
      expect(
        await inBean('@Computed()\n  int priceOf(String isbn) => 0;'),
        contains('@Computed on Basket.priceOf, which takes parameters'),
      );
    });

    test('@Computed on a field', () async {
      expect(
        await inBean('@Computed()\n  int total = 0;'),
        contains('@Computed on the field Basket.total'),
      );
    });

    test('@Effect with parameters, or with a value', () async {
      expect(
        await inBean('@Effect()\n  void save(int count) {}'),
        contains('@Effect on Basket.save, which takes parameters'),
      );
      expect(
        await inBean('@Effect()\n  int save() => 0;'),
        contains('@Effect on Basket.save, which returns a value'),
      );
    });

    test('in a @Configuration class', () async {
      final errors = await _errors('''
@Configuration()
class Config {
  @Signal()
  int count = 0;
}
''');
      expect(
        errors,
        allOf(
          contains('@Configuration class Config'),
          contains('Move the state into a component'),
        ),
      );
    });
  });

  group('an annotation where no proxy follows it', () {
    test('a class that is no bean', () async {
      expect(
        await _errors('''
class Plain {
  @Signal()
  int count = 0;
}
'''),
        allOf(
          contains('@Signal on Plain.count, and Plain is no bean'),
          contains('Annotate Plain as a component, or make it abstract'),
        ),
      );
    });

    test('a base of a component is no mistake, abstract or not, nor is a '
        'mixin', () async {
      final output = await _generate('''
abstract class Counted {
  @Signal()
  int count = 0;
}

class Named {
  @Signal()
  String name = '';
}

mixin Priced {
  @Computed()
  int get price => 1;
}

@Component()
class Basket extends Counted with Priced {}

@Component()
class Customer extends Named {}
''');
      expect(output, _has('@override set count(int value)'));
      expect(output, _has('@override int get price'));
      expect(output, _has('@override set name(String value)'));
      expect('adviseSelfCalls:true'.allMatches(output), hasLength(2));
    });

    test('a mixin is checked like a class', () async {
      expect(
        await _errors('''
mixin Counting {
  @Signal()
  int _count = 0;
  int get count => _count;
}

@Component()
class Basket with Counting {}
'''),
        contains('@Signal on the private field Counting._count'),
      );
    });

    test('an enum, an extension, the top level', () async {
      final errors = await _errors('''
enum Mode {
  day,
  night;

  @Computed()
  int get twice => index * 2;
}

@Component()
class Basket {}

extension on Basket {
  @Computed()
  int get size => 0;
}

@Signal()
int count = 0;

@Effect()
void save() {}
''');
      expect(
        errors,
        allOf(
          contains('@Computed on twice, in the enum Mode'),
          contains('@Computed on size, in the extension on Basket'),
          contains('@Signal on count, in the top level of'),
          contains('@Effect on save, in the top level of'),
          contains('it goes on a member of a component class'),
        ),
      );
    });

    test('a bean the container does not proxy', () async {
      expect(
        await _errors('''
@Aspect()
@Component()
class Audit {
  @Signal()
  int calls = 0;
}
'''),
        allOf(
          contains(
            '@Signal on a member of Audit, a bean the container does '
            'not proxy',
          ),
          contains('Move the member into a component of its own'),
        ),
      );
      expect(
        await _errors('''
@Component()
class Renamer implements BeanFactoryPostProcessor {
  @Signal()
  int seen = 0;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {}
}
'''),
        contains(
          '@Signal on a member of Renamer, a bean the container does '
          'not proxy',
        ),
      );
    });

    test('the result of a @Bean method', () async {
      expect(
        await _errors('''
abstract class Base {}

class Basket extends Base {
  @Signal()
  int count = 0;
}

@Configuration()
class Config {
  @Bean()
  Basket basket() => Basket();
}
'''),
        allOf(
          contains(
            '@Signal on a member of Basket needs a proxy that '
            'extends Basket',
          ),
          contains('not as the result of a @Bean method'),
          isNot(contains('is no bean')),
        ),
      );
    });

    test('a @ConfigurationProperties class', () async {
      expect(
        await _errors('''
@ConfigurationProperties('shop')
class ShopProperties {
  @Signal()
  int limit = 0;
}
'''),
        allOf(
          contains('@ConfigurationProperties class ShopProperties'),
          contains('Keep the state in a component that reads ShopProperties'),
        ),
      );
    });

    test('a repository: its methods are written by the generator', () async {
      expect(
        await _errors('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

abstract interface class BookRepository implements DataRepository<Book, int> {
  @Computed()
  Future<List<Book>> findByTitle(String title);
}
'''),
        allOf(
          contains(
            '@Computed on the abstract method '
            'BookRepository.findByTitle',
          ),
          contains(
            'the method of a repository or of an HTTP client is '
            'written by the generator',
          ),
          contains(
            '@Computed on a member of BookRepository, whose '
            'implementation is generated',
          ),
        ),
      );
    });

    test(
      'a component that reads a repository in a computed getter builds',
      () async {
        final output = await _generate('''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

class Book {
  Book({this.id, required this.title});
  int? id;
  String title;
}

abstract interface class BookRepository implements DataRepository<Book, int> {
  Future<List<Book>> findByTitle(String title);
}

@Service()
class Books {
  Books(this.repository);
  final BookRepository repository;

  @Signal()
  String query = '';

  @Computed()
  Future<List<Book>> get found => repository.findByTitle(query);
}

@Repository()
class Notes {
  @Signal()
  List<String> lines = [];
}
''');
        expect('adviseSelfCalls:true'.allMatches(output), hasLength(2));
      },
    );

    test('an HTTP client', () async {
      expect(
        await _errors('''
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

@FeignClient(name: 'books', url: 'http://localhost')
abstract interface class BooksClient {
  @Computed()
  @GetMapping('/books')
  Future<List<String>> books();
}
'''),
        allOf(
          contains('@Computed on the abstract method BooksClient.books'),
          contains(
            '@Computed on a member of BooksClient, whose '
            'implementation is generated',
          ),
        ),
      );
    });

    test('an abstract member', () async {
      expect(
        await _errors('''
abstract class Counted {
  @Signal()
  abstract int count;
}
'''),
        contains('@Signal on the abstract field Counted.count'),
      );
      expect(
        await _errors('''
abstract class Counted {
  @Computed()
  int get twice;
}
'''),
        contains('@Computed on the abstract getter Counted.twice'),
      );
    });

    test('an override without the annotation', () async {
      const base = '''
abstract class Counted {
  @Signal()
  int count = 0;

  @Computed()
  int get twice => count * 2;

  @Effect()
  void save() {}
}
''';
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  int count = 5;
}
'''),
        allOf(
          contains(
            'Basket.count overrides the @Signal field Counted.count '
            'without its annotation',
          ),
          contains('Repeat the annotation on Basket.count'),
        ),
      );
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  int get twice => 1;
}
'''),
        contains('Basket.twice overrides the @Computed getter Counted.twice'),
      );
      expect(
        await _errors('''
$base
@Component()
class Basket extends Counted {
  @override
  void save() {}
}
'''),
        contains('Basket.save overrides the @Effect method Counted.save'),
      );
      await _generate('''
$base
@Component()
class Basket extends Counted {
  @override
  @Signal()
  int count = 5;

  @override
  @Computed()
  int get twice => 1;

  @override
  @Effect()
  void save() {}
}
''');
    });

    test('a member the proxy cannot override', () async {
      expect(
        await _errors('''
class _Hidden {}

@Component()
class Basket {
  @Signal()
  _Hidden? hidden;
}
'''),
        contains(
          '@Signal on Basket.hidden: the proxy of Basket cannot '
          'override it',
        ),
      );
      expect(
        await _errors('''
@Component()
class Basket {
  @Signal()
  int count = 0;

  @Computed()
  int operator -() => -count;
}
'''),
        contains(
          '@Computed on Basket.-: the proxy of Basket cannot '
          'override it',
        ),
      );
    });

    test('a generic class: the way out is not an interface', () async {
      expect(
        await _errors('''
@Component()
class Store<T> {
  @Signal()
  T? value;
}
'''),
        allOf(
          contains(
            'It cannot be made, because Store is generic. Remove its '
            'type parameters.',
          ),
          isNot(contains('add an interface')),
        ),
      );
    });
  });
}
