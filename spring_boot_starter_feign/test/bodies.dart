// A client with form bodies, `ResponseEntity<void>` and raw responses,
// with the code the generator writes for it.
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';

import 'catalog.dart';

@FeignClient('forms', url: 'http://forms.test')
abstract interface class FormClient {
  @PostMapping.of(path: '/login', consumes: MediaType.applicationFormUrlencoded)
  Future<String> login(@RequestBody() Map<String, Object?> form);

  @PostMapping.of(
    path: '/books',
    consumes: 'application/x-www-form-urlencoded; charset=ISO-8859-1',
  )
  Future<String> book(@RequestBody() Book book);

  @PostMapping.of(
    path: '/header',
    headers: ['Content-Type=application/x-www-form-urlencoded'],
  )
  Future<String> header(@RequestBody() Map<String, Object?> form);

  @DeleteMapping('/books/{isbn}')
  Future<ResponseEntity<void>> delete(@PathVariable() String isbn);

  @GetMapping('/raw')
  Future<HttpResponse> raw();
}

// ---- generated ----

class FormClientImpl implements FormClient {
  FormClientImpl(this._handler, this._metadata);

  static FormClientImpl $create(DependencyResolver r) {
    final metadata = InterfaceMetadata<FormClient>(
      typeName: 'FormClient',
      annotations: const [FeignClient('forms', url: 'http://forms.test')],
      methods: [
        ProxyMethod(
          'login',
          parameters: const [
            BeanParameter(
              'form',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            PostMapping.of(
              path: '/login',
              consumes: MediaType.applicationFormUrlencoded,
            ),
          ],
          call: (target, arguments) => (target as FormClient).login(
            arguments[0]! as Map<String, Object?>,
          ),
        ),
        ProxyMethod(
          'book',
          parameters: const [
            BeanParameter(
              'book',
              type: ClassType<Book>(),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            PostMapping.of(
              path: '/books',
              consumes: 'application/x-www-form-urlencoded; charset=ISO-8859-1',
            ),
          ],
          call: (target, arguments) =>
              (target as FormClient).book(arguments[0]! as Book),
        ),
        ProxyMethod(
          'header',
          parameters: const [
            BeanParameter(
              'form',
              type: MapType<String, Object?>(
                ClassType<String>(),
                DynamicType(),
              ),
              isRequired: true,
              annotations: [RequestBody()],
            ),
          ],
          returnType: const ClassType<String>(),
          isFuture: true,
          annotations: const [
            PostMapping.of(
              path: '/header',
              headers: ['Content-Type=application/x-www-form-urlencoded'],
            ),
          ],
          call: (target, arguments) => (target as FormClient).header(
            arguments[0]! as Map<String, Object?>,
          ),
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
          returnType: const GenericType<ResponseEntity<void>>([
            DynamicType.forVoid(),
          ]),
          isFuture: true,
          annotations: const [DeleteMapping('/books/{isbn}')],
          call: (target, arguments) =>
              (target as FormClient).delete(arguments[0]! as String),
        ),
        ProxyMethod(
          'raw',
          returnType: const ClassType<HttpResponse>(),
          isFuture: true,
          annotations: const [GetMapping('/raw')],
          call: (target, arguments) => (target as FormClient).raw(),
        ),
      ],
    );
    return FormClientImpl(InterfaceProxies.handlerFor(r, metadata), metadata);
  }

  final InvocationHandler _handler;
  final InterfaceMetadata<FormClient> _metadata;

  @override
  Future<String> login(Map<String, Object?> form) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[0], [form]));

  @override
  Future<String> book(Book book) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[1], [book]));

  @override
  Future<String> header(Map<String, Object?> form) =>
      retypeFuture<String>(_handler.invoke(_metadata.methods[2], [form]));

  @override
  Future<ResponseEntity<void>> delete(String isbn) =>
      retypeFuture<ResponseEntity<void>>(
        _handler.invoke(_metadata.methods[3], [isbn]),
      );

  @override
  Future<HttpResponse> raw() => retypeFuture<HttpResponse>(
    _handler.invoke(_metadata.methods[4], const []),
  );
}

/// The module with [FormClient] (and the introspection of [Book]).
final bodiesModule = BeanModule(
  'bodies',
  [
    BeanDefinition<FormClient>(
      name: 'formClient',
      primary: true,
      create: FormClientImpl.$create,
    ),
  ],
  introspections: [bookIntrospection],
);
