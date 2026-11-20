// `@InterfaceProxy`: a generated implementation of an annotated interface
// that forwards to the handler.
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('@InterfaceProxy', () {
    const source = """
@InterfaceProxy(primary: true)
class Remote {
  const Remote(this.name);
  final String name;
}

class Tag {
  const Tag(this.value);
  final String value;
}

class Book {
  const Book(this.isbn, {this.title = ''});
  final String isbn;
  final String title;
}

@Remote('catalog')
abstract interface class CatalogClient {
  @Tag('find')
  Future<Book> find(@Tag('isbn') String isbn, {int page = 0});

  Future<List<Book>> all();

  Future<Book> create(Book book);

  Future<void> remove(String isbn);

  String version();

  void ping();

  Stream<Book> changes();

  Stream<void> pulses();
}
""";

    test('a generated implementation forwarding to the handler', () async {
      final output = await generateModule(source);
      expect(
        output,
        hasCode(r'class _$CatalogClientImpl implements CatalogClient {'),
      );
      expect(
        output,
        hasCode(r'static _$CatalogClientImpl $create(DependencyResolver r) {'),
      );
      expect(
        output,
        hasCode(
          'final metadata = InterfaceMetadata<CatalogClient>(typeName: '
          "r'CatalogClient', "
          "annotations: const [Remote(r'catalog')],",
        ),
      );
      expect(
        output,
        hasCode(
          '@override Future<Book> find(String isbn, {int page = 0}) => '
          'retypeFuture<Book>(this._handler.invoke(this._metadata.methods[0], '
          '[isbn, page]));',
        ),
      );
      expect(
        output,
        hasCode(
          "IntrospectedParameter(r'isbn', type: const ClassType<String>(), "
          'isRequired: true, '
          "annotations: const [Tag(r'isbn')])",
        ),
      );
      expect(
        output,
        hasCode(
          "IntrospectedParameter(r'page', type: const ClassType<int>(), "
          'symbol: #page)',
        ),
      );
      expect(
        output,
        hasCode(
          'call: (target, arguments) => (target as CatalogClient).find( '
          '(arguments[0] as String), page: (arguments[1] as int))',
        ),
      );
      expect(
        output,
        hasCode(
          'returnType: const ListType<Book>(ClassType<Book>()), isFuture: true',
        ),
      );
      expect(
        output,
        hasCode(
          '@override String version() '
          '=> '
          '(this._handler.invoke(this._metadata.methods[4], const []) as '
          'String);',
        ),
      );
      expect(
        output,
        hasCode(
          '@override void ping() { '
          'this._handler.invoke(this._metadata.methods[5], const []); }',
        ),
      );
      // A sync generic result (e.g. a Feign EventStream<T>): described with
      // its type argument and cast.
      expect(
        output,
        hasCode(
          'returnType: const GenericType<Stream<Book>>([ClassType<Book>()])',
        ),
      );
      expect(
        output,
        hasCode(
          '@override Stream<Book> changes() => '
          '(this._handler.invoke(this._metadata.methods[6], const []) as '
          'Stream<Book>);',
        ),
      );
      // A `void` type argument (`ResponseEntity<void>`): the handler can
      // tell it from `dynamic`.
      expect(
        output,
        hasCode(
          'returnType: const '
          'GenericType<Stream<void>>([DynamicType.forVoid()])',
        ),
      );
      // The bean: primary (from @InterfaceProxy(primary: true)), created by
      // the implementation.
      expect(
        output,
        hasCode(
          "BeanDefinition<CatalogClient>(name: r'catalogClient', "
          "source: r'package:pkg/src/service.dart#CatalogClient', "
          'primary: true,',
        ),
      );
      expect(output, hasCode(r'create: (r) => _$CatalogClientImpl.$create(r)'));
      // Book, used by the interface, is introspected for JSON.
      expect(output, hasCode('Introspection<Book>('));
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });

    test('primary and qualifiers of the annotation itself, like '
        '@FeignClient(primary: false, qualifiers: [...])', () async {
      final output = await generateModule("""
@InterfaceProxy(primary: true)
class Remote {
  const Remote(this.name, {this.primary = true, this.qualifiers = const []});
  final String name;
  final bool primary;
  final List<String> qualifiers;
}

@Remote('catalog', primary: false, qualifiers: ['books', 'catalogFeign'])
abstract interface class CatalogClient {
  Future<String> ping();
}

@Remote('stock')
abstract interface class StockClient {
  Future<String> ping();
}
""");
      expect(
        output,
        hasCode(
          "BeanDefinition<CatalogClient>(name: r'catalogClient', "
          "source: r'package:pkg/src/service.dart#CatalogClient', "
          'qualifiers: const {',
        ),
      );
      expect(output, hasCode("r'books', r'catalogFeign'"));
      expect(
        output,
        hasCode(
          "BeanDefinition<StockClient>(name: r'stockClient', "
          "source: r'package:pkg/src/service.dart#StockClient', "
          'primary: true,',
        ),
      );
    });

    test('rejects what cannot be implemented', () async {
      const remote = '''
@InterfaceProxy()
class Remote {
  const Remote();
}
''';
      await expectBuildError(
        '$remote@Remote() class NotAbstract {}',
        'must be abstract',
      );
      await expectBuildError(
        '$remote@Remote() abstract class WithBody { int count() => 1; }',
        'has a body',
      );
      await expectBuildError(
        '$remote@Remote() abstract class WithGetter { int get count; }',
        'only methods are supported',
      );
      await expectBuildError(
        '$remote@Remote() abstract class Generic { T read<T>(); }',
        'must not be generic',
      );
    });
  });
}
