// Clients and models as an application writes them, with the code the
// generator writes for them (introspection and the interface
// implementations), so the starter is tested without code generation.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

class Book {
  const Book({required this.isbn, required this.title});
  final String isbn;
  final String title;
}

@FeignClient('catalog', url: r'${catalog.url}', path: '/v1')
abstract interface class CatalogClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetMapping('/books')
  Future<List<Book>> search(
    @RequestParam('q') String query, {
    @RequestParam('page') int? page,
    @RequestHeader('X-Trace') String? trace,
  });

  @PostMapping('/books')
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable('isbn') String id);

  @GetMapping('/books/{isbn}/details')
  Future<Book?> maybe(@PathVariable() String isbn);

  @GetMapping('/ping', headers: [r'X-Shop=${shop.name:neon}'])
  Future<String> ping();
}

@FeignClient('backup', url: 'http://backup.test', fallback: BackupFallback)
abstract interface class BackupClient {
  @GetMapping('/motd')
  Future<String> motd();
}

class BackupFallback implements BackupClient {
  @override
  Future<String> motd() async => 'offline';
}

@FeignClient('broken', url: 'http://broken.test')
abstract interface class BrokenClient {
  @GetMapping('/books/{isbn}')
  Future<Book> find(@PathVariable('id') String isbn);

  Future<String> noMapping();
}

// ---- generated ----

final bookIntrospection = BeanIntrospection<Book>(
  properties: [
    BeanProperty<Book>(
      'isbn',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.isbn,
    ),
    BeanProperty<Book>(
      'title',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.title,
    ),
  ],
  constructor: BeanConstructor<Book>(
    parameters: const [
      BeanParameter(
        'isbn',
        type: ClassType<String>(),
        symbol: #isbn,
        isRequired: true,
      ),
      BeanParameter(
        'title',
        type: ClassType<String>(),
        symbol: #title,
        isRequired: true,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Book.new, positional, named) as Book,
  ),
);

class CatalogClientImpl implements CatalogClient {
  CatalogClientImpl(this._handler, this._metadata);

  static CatalogClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<CatalogClient>(
      typeName: 'CatalogClient',
      annotations: const [
        FeignClient('catalog', url: r'${catalog.url}', path: '/v1'),
      ],
      methods: [
        ProxyMethod(
          'find',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const ClassType<Book>(),
          isFuture: true,
          annotations: const [GetMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as CatalogClient).find(arguments[0]! as String),
        ),
        ProxyMethod(
          'search',
          parameters: const [
            BeanParameter(
              'query',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestParam('q')],
            ),
            BeanParameter(
              'page',
              type: ClassType<int>(nullable: true),
              symbol: #page,
              annotations: [RequestParam('page')],
            ),
            BeanParameter(
              'trace',
              type: ClassType<String>(nullable: true),
              symbol: #trace,
              annotations: [RequestHeader('X-Trace')],
            ),
          ],
          returnType: const ListType<Book>(ClassType<Book>()),
          isFuture: true,
          annotations: const [GetMapping('/books')],
          call: (target, arguments) => (target as CatalogClient).search(
            arguments[0]! as String,
            page: arguments[1] as int?,
            trace: arguments[2] as String?,
          ),
        ),
        ProxyMethod(
          'create',
          parameters: const [
            BeanParameter(
              'book',
              type: ClassType<Book>(),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const GenericType<ResponseEntity<Book>>([
            ClassType<Book>(),
          ]),
          isFuture: true,
          annotations: const [PostMapping('/books')],
          call: (target, arguments) =>
              (target as CatalogClient).create(arguments[0]! as Book),
        ),
        ProxyMethod(
          'delete',
          parameters: const [
            BeanParameter(
              'id',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable('isbn')],
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [DeleteMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as CatalogClient).delete(arguments[0]! as String),
        ),
        ProxyMethod(
          'maybe',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const ClassType<Book>(nullable: true),
          isFuture: true,
          annotations: const [GetMapping('/books/{isbn}/details')],
          call: (target, arguments) =>
              (target as CatalogClient).maybe(arguments[0]! as String),
        ),
        ProxyMethod(
          'ping',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            GetMapping('/ping', headers: [r'X-Shop=${shop.name:neon}']),
          ],
          call: (target, arguments) => (target as CatalogClient).ping(),
        ),
      ],
    );
    return CatalogClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<CatalogClient> _metadata;

  @override
  Future<Book> find(String isbn) =>
      retypeFuture<Book>(_handler.invoke(_metadata.methods[0], [isbn]));

  @override
  Future<List<Book>> search(String query, {int? page, String? trace}) =>
      retypeFuture<List<Book>>(
        _handler.invoke(_metadata.methods[1], [query, page, trace]),
      );

  @override
  Future<ResponseEntity<Book>> create(Book book) =>
      retypeFuture<ResponseEntity<Book>>(
        _handler.invoke(_metadata.methods[2], [book]),
      );

  @override
  Future<void> delete(String id) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[3], [id]));

  @override
  Future<Book?> maybe(String isbn) =>
      retypeFuture<Book?>(_handler.invoke(_metadata.methods[4], [isbn]));

  @override
  Future<String> ping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[5], const []));
}

class BackupClientImpl implements BackupClient {
  BackupClientImpl(this._handler, this._metadata);

  static BackupClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<BackupClient>(
      typeName: 'BackupClient',
      annotations: const [
        FeignClient(
          'backup',
          url: 'http://backup.test',
          fallback: BackupFallback,
        ),
      ],
      methods: [
        ProxyMethod(
          'motd',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/motd')],
          call: (target, arguments) => (target as BackupClient).motd(),
        ),
      ],
    );
    return BackupClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<BackupClient> _metadata;

  @override
  Future<String> motd() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));
}

class BrokenClientImpl implements BrokenClient {
  BrokenClientImpl(this._handler, this._metadata);

  static BrokenClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<BrokenClient>(
      typeName: 'BrokenClient',
      annotations: const [FeignClient('broken', url: 'http://broken.test')],
      methods: [
        ProxyMethod(
          'find',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable('id')],
            ),
          ],
          returnType: const ClassType<Book>(),
          isFuture: true,
          annotations: const [GetMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as BrokenClient).find(arguments[0]! as String),
        ),
        ProxyMethod(
          'noMapping',
          returnType: const ClassType<String>(),
          isFuture: true,
          call: (target, arguments) => (target as BrokenClient).noMapping(),
        ),
      ],
    );
    return BrokenClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<BrokenClient> _metadata;

  @override
  Future<Book> find(String isbn) =>
      retypeFuture<Book>(_handler.invoke(_metadata.methods[0], [isbn]));

  @override
  Future<String> noMapping() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], const []));
}

/// The application module: the clients (primary, like the generator makes
/// them) and the fallback bean.
final appModule = BeanModule(
  'app',
  [
    BeanDefinition<CatalogClient>(
      name: 'catalogClient',
      primary: true,
      create: CatalogClientImpl.$create,
    ),
    BeanDefinition<BackupClient>(
      name: 'backupClient',
      primary: true,
      create: BackupClientImpl.$create,
    ),
    BeanDefinition<BackupFallback>(
      name: 'backupFallback',
      types: const [BackupFallback, BackupClient],
      create: (_) => BackupFallback(),
    ),
  ],
  introspections: [bookIntrospection],
);

/// A module with an invalid client.
final brokenModule = BeanModule('broken', [
  BeanDefinition<BrokenClient>(
    name: 'brokenClient',
    primary: true,
    create: BrokenClientImpl.$create,
  ),
]);
