// Clients using what Spring Cloud OpenFeign's SpringMvcContract reads
// (Map parameters, cookies, Spring's header syntax, @FeignClient
// attributes), with the code the generator writes for them.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

import 'catalog.dart' show Book, bookIntrospection;

@FeignClient(
  'contract',
  url: 'https://api.neon.test',
  contextId: 'contract-v2',
  dismiss404: true,
)
abstract interface class ContractClient {
  @GetMapping('/books')
  Future<String> filter(
    @RequestParam() Map<String, Object?> filters, {
    @RequestParam('page') int? page,
  });

  @GetMapping('/headers')
  Future<String> headers(@RequestHeader('ignored') Map<String, Object?> all);

  @GetMapping('/files/{path}')
  Future<String> file(@PathVariable() String path);

  @GetMapping('/cart')
  Future<String> cart(
    @CookieValue('SESSION') String session, [
    @CookieValue() String? theme,
  ]);

  @GetMapping.of(
    path: '/static',
    headers: [
      'X-Shop=neon',
      r'X-Expr=${shop.name:books}',
      'X-Token=a=b',
      '!X-Debug',
      'X-Mode!=test',
      'X-Present',
    ],
  )
  Future<String> statics();

  @DeleteMapping('/books/{isbn}')
  Future<void> delete(@PathVariable() String isbn);

  @GetMapping('/books/{isbn}')
  Future<Book?> find(@PathVariable() String isbn);

  @GetMapping('/search')
  Future<String> search(@RequestParam('q') Object query);
}

@FeignClient('invalid', url: 'https://invalid.test')
abstract interface class InvalidClient {
  @GetMapping('/a')
  Future<String> byBook(@RequestParam('book') Book book);

  @GetMapping('/b')
  Future<String> byBooks(@RequestHeader('X-Books') List<Book> books);

  @GetMapping('/c')
  Future<String> byMap(@RequestParam() Map<String, Book> books);

  @GetMapping('/d/{id}')
  Future<String> byPathMap(@PathVariable('id') Map<String, String> id);

  @GetMapping.of(path: '/e', headers: ['X-Old: syntax'])
  Future<String> oldHeaders();
}

// ---- generated ----

class ContractClientImpl implements ContractClient {
  ContractClientImpl(this._handler, this._metadata);

  static ContractClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<ContractClient>(
      typeName: 'ContractClient',
      annotations: const [
        FeignClient(
          'contract',
          url: 'https://api.neon.test',
          contextId: 'contract-v2',
          dismiss404: true,
        ),
      ],
      methods: [
        ProxyMethod(
          'filter',
          parameters: const [
            BeanParameter(
              'filters',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
              annotations: [RequestParam()],
            ),
            BeanParameter(
              'page',
              type: ClassType<int>(nullable: true),
              symbol: #page,
              annotations: [RequestParam('page')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/books')],
          call: (target, arguments) => (target as ContractClient).filter(
            arguments[0]! as Map<String, Object?>,
            page: arguments[1] as int?,
          ),
        ),
        ProxyMethod(
          'headers',
          parameters: const [
            BeanParameter(
              'all',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
              annotations: [RequestHeader('ignored')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/headers')],
          call: (target, arguments) => (target as ContractClient).headers(
            arguments[0]! as Map<String, Object?>,
          ),
        ),
        ProxyMethod(
          'file',
          parameters: const [
            BeanParameter(
              'path',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/files/{path}')],
          call: (target, arguments) =>
              (target as ContractClient).file(arguments[0]! as String),
        ),
        ProxyMethod(
          'cart',
          parameters: const [
            BeanParameter(
              'session',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [CookieValue('SESSION')],
            ),
            BeanParameter(
              'theme',
              type: ClassType<String>(nullable: true),
              annotations: [CookieValue()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/cart')],
          call: (target, arguments) => (target as ContractClient).cart(
            arguments[0]! as String,
            arguments[1] as String?,
          ),
        ),
        ProxyMethod(
          'statics',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            GetMapping.of(
              path: '/static',
              headers: [
                'X-Shop=neon',
                r'X-Expr=${shop.name:books}',
                'X-Token=a=b',
                '!X-Debug',
                'X-Mode!=test',
                'X-Present',
              ],
            ),
          ],
          call: (target, arguments) => (target as ContractClient).statics(),
        ),
        ProxyMethod(
          'delete',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const DynamicType(),
          isFuture: true,
          isVoid: true,
          annotations: const [DeleteMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as ContractClient).delete(arguments[0]! as String),
        ),
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
          returnType: const ClassType<Book>(nullable: true),
          isFuture: true,
          annotations: const [GetMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as ContractClient).find(arguments[0]! as String),
        ),
        ProxyMethod(
          'search',
          parameters: const [
            BeanParameter(
              'query',
              type: DynamicType(),
              isRequired: true,
              annotations: [RequestParam('q')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/search')],
          call: (target, arguments) =>
              (target as ContractClient).search(arguments[0]!),
        ),
      ],
    );
    return ContractClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<ContractClient> _metadata;

  @override
  Future<String> filter(Map<String, Object?> filters, {int? page}) =>
      retypeFuture<String>(
        _handler.invoke(_metadata.methods[0], [filters, page]),
      );

  @override
  Future<String> headers(Map<String, Object?> all) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [all]));

  @override
  Future<String> file(String path) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], [path]));

  @override
  Future<String> cart(String session, [String? theme]) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[3], [session, theme]),
  );

  @override
  Future<String> statics() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[4], const []));

  @override
  Future<void> delete(String isbn) =>
      retypeFuture<void>(_handler.invoke(_metadata.methods[5], [isbn]));

  @override
  Future<Book?> find(String isbn) =>
      retypeFuture<Book?>(_handler.invoke(_metadata.methods[6], [isbn]));

  @override
  Future<String> search(Object query) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[7], [query]));
}

class InvalidClientImpl implements InvalidClient {
  InvalidClientImpl(this._handler, this._metadata);

  static InvalidClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<InvalidClient>(
      typeName: 'InvalidClient',
      annotations: const [FeignClient('invalid', url: 'https://invalid.test')],
      methods: [
        ProxyMethod(
          'byBook',
          parameters: const [
            BeanParameter(
              'book',
              type: ClassType<Book>(),
              isRequired: true,
              annotations: [RequestParam('book')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/a')],
          call: (target, arguments) =>
              (target as InvalidClient).byBook(arguments[0]! as Book),
        ),
        ProxyMethod(
          'byBooks',
          parameters: const [
            BeanParameter(
              'books',
              type: ListType<Book>(ClassType<Book>()),
              isRequired: true,
              annotations: [RequestHeader('X-Books')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/b')],
          call: (target, arguments) =>
              (target as InvalidClient).byBooks(arguments[0]! as List<Book>),
        ),
        ProxyMethod(
          'byMap',
          parameters: const [
            BeanParameter(
              'books',
              type: MapType<String, Book>(
                ClassType<String>(),
                ClassType<Book>(),
              ),
              isRequired: true,
              annotations: [RequestParam()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/c')],
          call: (target, arguments) => (target as InvalidClient).byMap(
            arguments[0]! as Map<String, Book>,
          ),
        ),
        ProxyMethod(
          'byPathMap',
          parameters: const [
            BeanParameter(
              'id',
              type: MapType<String, String>(
                ClassType<String>(),
                ClassType<String>(),
              ),
              isRequired: true,
              annotations: [PathVariable('id')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/d/{id}')],
          call: (target, arguments) => (target as InvalidClient).byPathMap(
            arguments[0]! as Map<String, String>,
          ),
        ),
        ProxyMethod(
          'oldHeaders',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            GetMapping.of(path: '/e', headers: ['X-Old: syntax']),
          ],
          call: (target, arguments) => (target as InvalidClient).oldHeaders(),
        ),
      ],
    );
    return InvalidClientImpl(
      InterfaceProxies.handlerFor(r, metadata),
      metadata,
    );
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<InvalidClient> _metadata;

  @override
  Future<String> byBook(Book book) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], [book]));

  @override
  Future<String> byBooks(List<Book> books) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [books]));

  @override
  Future<String> byMap(Map<String, Book> books) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], [books]));

  @override
  Future<String> byPathMap(Map<String, String> id) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[3], [id]));

  @override
  Future<String> oldHeaders() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[4], const []));
}

/// The module with [ContractClient].
final contractModule = BeanModule(
  'contract',
  [
    BeanDefinition<ContractClient>(
      name: 'contractClient',
      primary: true,
      create: ContractClientImpl.$create,
    ),
  ],
  introspections: [bookIntrospection],
);

/// A module with [InvalidClient], whose parameters cannot be sent.
final invalidModule = BeanModule(
  'invalid',
  [
    BeanDefinition<InvalidClient>(
      name: 'invalidClient',
      primary: true,
      create: InvalidClientImpl.$create,
    ),
  ],
  introspections: [bookIntrospection],
);
