// Clients with a mapping without a path and parameters with Spring's
// `required` / `defaultValue`, with the code the generator writes for them.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

/// `@GetMapping()` uses the base path of the client (`url` + `path`).
@FeignClient('params', url: 'https://api.neon.test', path: '/api')
abstract interface class ParamsClient {
  @GetMapping()
  Future<String> root();

  @GetMapping('/search')
  Future<String> search(
    @RequestParam('q') String query, {
    @RequestParam.of(name: 'sort', defaultValue: 'asc') String? sort,
    @RequestParam.of(name: 'page', required: false) int? page,
    @RequestParam('lang') String? lang,
    @RequestHeader.of(name: 'X-Tenant', defaultValue: 'public') String? tenant,
    @RequestHeader('X-Trace') String? trace,
  });

  @GetMapping('/books/{isbn}/pages')
  Future<String> pages(
    @PathVariable.of(name: 'isbn', required: false) String? isbn,
  );

  /// A nullable path variable is still required.
  @GetMapping('/loose/{id}')
  Future<String> loose(@PathVariable() String? id);

  @GetMapping('/strict/{id}')
  Future<String> strict(
    @PathVariable() String id,
    @RequestParam('q') String query,
    @RequestHeader('X-Id') String requestId,
  );

  @GetMapping('/lenient')
  Future<String> lenient(
    @RequestParam.of(name: 'q', required: false) String query,
    @RequestHeader.of(name: 'X-Q', required: false) String header,
  );
}

/// No `path`: `@GetMapping()` is the `url` itself.
@FeignClient('root', url: 'https://api.neon.test')
abstract interface class RootClient {
  @GetMapping()
  Future<String> index();

  @PostMapping()
  Future<String> create(@RequestBody() String text);
}

// ---- generated ----

class ParamsClientImpl implements ParamsClient {
  ParamsClientImpl(this._handler, this._metadata);

  static ParamsClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<ParamsClient>(
      typeName: 'ParamsClient',
      annotations: const [
        FeignClient('params', url: 'https://api.neon.test', path: '/api'),
      ],
      methods: [
        ProxyMethod(
          'root',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping()],
          call: (target, arguments) => (target as ParamsClient).root(),
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
              'sort',
              type: ClassType<String>(nullable: true),
              symbol: #sort,
              annotations: [RequestParam.of(name: 'sort', defaultValue: 'asc')],
            ),
            BeanParameter(
              'page',
              type: ClassType<int>(nullable: true),
              symbol: #page,
              annotations: [RequestParam.of(name: 'page', required: false)],
            ),
            BeanParameter(
              'lang',
              type: ClassType<String>(nullable: true),
              symbol: #lang,
              annotations: [RequestParam('lang')],
            ),
            BeanParameter(
              'tenant',
              type: ClassType<String>(nullable: true),
              symbol: #tenant,
              annotations: [
                RequestHeader.of(name: 'X-Tenant', defaultValue: 'public'),
              ],
            ),
            BeanParameter(
              'trace',
              type: ClassType<String>(nullable: true),
              symbol: #trace,
              annotations: [RequestHeader('X-Trace')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/search')],
          call: (target, arguments) => (target as ParamsClient).search(
            arguments[0]! as String,
            sort: arguments[1] as String?,
            page: arguments[2] as int?,
            lang: arguments[3] as String?,
            tenant: arguments[4] as String?,
            trace: arguments[5] as String?,
          ),
        ),
        ProxyMethod(
          'pages',
          parameters: const [
            BeanParameter(
              'isbn',
              type: ClassType<String>(nullable: true),
              isRequired: true,
              annotations: [PathVariable.of(name: 'isbn', required: false)],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/books/{isbn}/pages')],
          call: (target, arguments) =>
              (target as ParamsClient).pages(arguments[0] as String?),
        ),
        ProxyMethod(
          'loose',
          parameters: const [
            BeanParameter(
              'id',
              type: ClassType<String>(nullable: true),
              isRequired: true,
              annotations: [PathVariable()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/loose/{id}')],
          call: (target, arguments) =>
              (target as ParamsClient).loose(arguments[0] as String?),
        ),
        ProxyMethod(
          'strict',
          parameters: const [
            BeanParameter(
              'id',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [PathVariable()],
            ),
            BeanParameter(
              'query',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestParam('q')],
            ),
            BeanParameter(
              'requestId',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestHeader('X-Id')],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/strict/{id}')],
          call: (target, arguments) => (target as ParamsClient).strict(
            arguments[0]! as String,
            arguments[1]! as String,
            arguments[2]! as String,
          ),
        ),
        ProxyMethod(
          'lenient',
          parameters: const [
            BeanParameter(
              'query',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestParam.of(name: 'q', required: false)],
            ),
            BeanParameter(
              'header',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestHeader.of(name: 'X-Q', required: false)],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping('/lenient')],
          call: (target, arguments) => (target as ParamsClient).lenient(
            arguments[0]! as String,
            arguments[1]! as String,
          ),
        ),
      ],
    );
    return ParamsClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<ParamsClient> _metadata;

  @override
  Future<String> root() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));

  @override
  Future<String> search(
    String query, {
    String? sort,
    int? page,
    String? lang,
    String? tenant,
    String? trace,
  }) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[1], [
      query,
      sort,
      page,
      lang,
      tenant,
      trace,
    ]),
  );

  @override
  Future<String> pages(String? isbn) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], [isbn]));

  @override
  Future<String> loose(String? id) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[3], [id]));

  // The parameters below accept null, which the type system keeps from
  // the generated code, so a test can reach the check of the handler.
  @override
  Future<String> strict(String? id, String? query, String? requestId) =>
      retypeFuture<String>(
        _handler.invoke(_metadata.methods[4], [id, query, requestId]),
      );

  @override
  Future<String> lenient(String? query, String? header) => retypeFuture<String>(
    _handler.invoke(_metadata.methods[5], [query, header]),
  );
}

class RootClientImpl implements RootClient {
  RootClientImpl(this._handler, this._metadata);

  static RootClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<RootClient>(
      typeName: 'RootClient',
      annotations: const [FeignClient('root', url: 'https://api.neon.test')],
      methods: [
        ProxyMethod(
          'index',
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [GetMapping()],
          call: (target, arguments) => (target as RootClient).index(),
        ),
        ProxyMethod(
          'create',
          parameters: const [
            BeanParameter(
              'text',
              type: ClassType<String>(),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [PostMapping()],
          call: (target, arguments) =>
              (target as RootClient).create(arguments[0]! as String),
        ),
      ],
    );
    return RootClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<RootClient> _metadata;

  @override
  Future<String> index() =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], const []));

  @override
  Future<String> create(String text) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [text]));
}

/// The module with [ParamsClient] and [RootClient].
final parametersModule = BeanModule('parameters', [
  BeanDefinition<ParamsClient>(
    name: 'paramsClient',
    primary: true,
    create: ParamsClientImpl.$create,
  ),
  BeanDefinition<RootClient>(
    name: 'rootClient',
    primary: true,
    create: RootClientImpl.$create,
  ),
]);
