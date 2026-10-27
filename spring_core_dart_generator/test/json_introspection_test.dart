import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

// The introspection the generator writes for JSON: generic classes
// (`Page<T>`), class names, and the classes JSON annotations name.

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _header = "import 'package:spring_core_dart/spring_core_dart.dart';\n";

const _models = '''
@Introspected()
class Page<T> {
  Page(this.content, {this.first, this.total = 0, this.extra = const []});
  final List<T> extra;
  final List<T> content;
  final T? first;
  final int total;
  T? pick(int index) => content[index];
  List<T> all() => content;
}

@Introspected()
class Pair<K, V> {
  Pair(this.key, this.value);
  final K key;
  final V value;
}

class Base {}

@Introspected()
class Bounded<T extends Base> {
  Bounded(this.items);
  final List<T> items;
}

class Book {
  Book(this.title);
  final String title;
}

@Introspected()
class Shelf {
  Shelf(this.page);
  final Page<Book> page;
}

class Public {}

@Introspected()
@JsonTypeInfo(property: 'kind', defaultImpl: Dog)
@JsonSubTypes([JsonSubType(Dog, name: 'dog')])
abstract class Animal {
  Animal(this.name);
  @JsonView([Public])
  final String name;
}

class Dog extends Animal {
  Dog(super.name);
}
''';

Future<(String, List<String>)> _generate(String source) async {
  final sources = {
    'lib/src/beans.dart': _scan,
    'lib/src/models.dart': '$_header$source',
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final output = result.readerWriter.testing.readString(result.outputs.single);
  final errors = await resolveSources<List<String>>(
    {
      for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value,
      'pkg|lib/src/beans.spring.dart': output,
    },
    (resolver) async {
      final library = await resolver.libraryFor(
        AssetId('pkg', 'lib/src/beans.spring.dart'),
      );
      final result = await library.session.getErrors(
        library.firstFragment.source.fullName,
      );
      return [
        if (result case ErrorsResult(:final diagnostics))
          for (final diagnostic in diagnostics)
            if (diagnostic.severity == Severity.error) diagnostic.message,
      ];
    },
    rootPackage: 'pkg',
    resolverFor: 'pkg|lib/src/beans.spring.dart',
    readAllSourcesFromFilesystem: true,
  );
  return (_normalize(output), errors);
}

String _normalize(String code) => code
    .replaceAll(RegExp(r'\b_i\d+\.'), '')
    .replaceAll(RegExp(r'\s'), '')
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m[1]!);

Matcher _has(String code) => contains(_normalize(code));

void main() {
  late final String output;
  late final List<String> errors;

  setUpAll(() async {
    (output, errors) = await _generate(_models);
  });

  test('the generated code compiles', () {
    expect(errors, isEmpty);
  });

  test('a generic class: erased, plus specialize with captured types', () {
    // Raw: type parameters are dynamic.
    expect(
      output,
      _has("BeanIntrospection<Page<dynamic>>(className: r'Page',"),
    );
    expect(
      output,
      _has(
        "BeanProperty<Page<dynamic>>(r'content', type: List<dynamic>, "
        'typeInfo: const ListType<dynamic>(DynamicType()),',
      ),
    );
    expect(
      output,
      _has(
        "BeanProperty<Page<dynamic>>(r'first', type: dynamic, nullable: true, "
        'typeInfo: const DynamicType(),',
      ),
    );
    // Specialized: the TypeInfo of each type argument.
    expect(
      output,
      _has(
        'specialize: (arguments) => arguments[0].capture(<T>() => '
        "BeanIntrospection<Page<T>>(className: r'Page',",
      ),
    );
    expect(
      output,
      _has(
        "BeanProperty<Page<T>>(r'content', type: List<T>, "
        'typeInfo: ListType<T>((arguments[0] as TypeInfo<T>)),',
      ),
    );
    expect(
      output,
      _has(
        "BeanParameter(r'first', type: (arguments[0] as "
        'TypeInfo<T>).asNullable(), '
        'symbol: #first)',
      ),
    );
    // A direct constructor call (dart2js cannot Function.apply named
    // arguments to `Page<T>.new`); absent optional ones get the defaults.
    expect(
      output,
      _has(
        'create: (positional, named) => Page<T>((positional[0] as List<T>), '
        'first: named.containsKey(#first) ? (named[#first] as T?) : null, '
        'total: named.containsKey(#total) ? (named[#total] as int) : 0, '
        'extra: named.containsKey(#extra) ? (named[#extra] as List<T>) : const '
        '[])',
      ),
    );
    expect(output, isNot(contains('Function.apply(Page')));
    // Method types that use T are not const.
    expect(output, _has("BeanMethod<Page<T>>(r'pick', parameterTypes: [int],"));
  });

  test('two type parameters are captured in order', () {
    expect(
      output,
      _has(
        'specialize: (arguments) => arguments[0].capture(<K>() => '
        'arguments[1].capture(<V>() => BeanIntrospection<Pair<K, V>>(',
      ),
    );
    expect(output, _has('typeInfo: (arguments[1] as TypeInfo<V>)'));
  });

  test('bounded type parameters: erased to the bound, not specialized', () {
    expect(
      output,
      _has(
        "BeanIntrospection<Bounded<Base>>(className: r'Bounded', "
        "properties: [BeanProperty<Bounded<Base>>(r'items', type: List<Base>, "
        'typeInfo: const ListType<Base>(ClassType<Base>()),',
      ),
    );
    expect(output, isNot(contains('BeanIntrospection<Bounded<T>>')));
  });

  test('a generic property type is described with its arguments', () {
    expect(
      output,
      _has(
        "BeanProperty<Shelf>(r'page', type: Page<Book>, "
        'typeInfo: const GenericType<Page<Book>>([ClassType<Book>()]),',
      ),
    );
  });

  test('classes named by @JsonSubTypes, defaultImpl and @JsonView', () {
    expect(output, _has("BeanIntrospection<Dog>(className: r'Dog',"));
    expect(output, _has("BeanIntrospection<Public>(className: r'Public',"));
    expect(
      output,
      _has(
        "annotations: const [JsonTypeInfo(property: r'kind', defaultImpl: "
        'Dog), '
        "JsonSubTypes([JsonSubType(Dog, name: r'dog')])]",
      ),
    );
  });
}
