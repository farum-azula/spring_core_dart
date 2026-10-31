import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../support/app.dart';

// Repositories as the generator describes them, written by hand to make
// mistakes the generated code could not compile: the factory has to refuse
// them at startup, with every reason.
ProxyMethod method(
  String name, {
  List<BeanParameter> parameters = const [],
  TypeInfo<Object?> returnType = const DynamicType(),
  bool isFuture = true,
  bool isVoid = false,
  List<Object> annotations = const [],
}) => ProxyMethod(
  name,
  parameters: parameters,
  returnType: returnType,
  isFuture: isFuture,
  isVoid: isVoid,
  annotations: annotations,
  call: (target, arguments) => null,
);

BeanParameter parameter(String name, TypeInfo<Object?> type) =>
    BeanParameter(name, type: type, isRequired: true);

const book = ClassType<Book>();
const bookList = ListType<Book>(book);
const text = ClassType<String>();

InterfaceMetadata<Object> repository(
  List<ProxyMethod> methods, {
  List<Object> annotations = const [],
  String name = 'BrokenRepository',
  TypeInfo<Object?> entity = book,
}) => InterfaceMetadata<Object>(
  typeName: name,
  methods: methods,
  annotations: annotations,
  supertypeArguments: {
    'DataRepository': [entity, const ClassType<int>()],
  },
);

void main() {
  late Example app;
  late RepositoryFactory factory;

  Future<void> run(FutureOr<void> Function() body) =>
      withExample((example) async {
        app = example;
        factory = example.context.getBean<RepositoryFactory>();
        await body();
      });

  Matcher invalid(List<String> reasons) => throwsA(
    isA<StateError>().having(
      (e) => e.message,
      'message',
      allOf([
        startsWith('Invalid repository BrokenRepository:'),
        for (final reason in reasons) contains(reason),
      ]),
    ),
  );

  test(
    'the factory supports interfaces extending DataRepository',
    () => run(() async {
      expect(factory.supports(repository(const [])), isTrue);
      expect(
        factory.supports(
          InterfaceMetadata<Object>(typeName: 'Other', methods: const []),
        ),
        isFalse,
      );
      expect(app.context, hasBean<InvocationHandlerFactory>());
    }),
  );

  test(
    'a valid repository is created',
    () => run(() async {
      final handler = factory.create(
        repository([
          method(
            'findByTitle',
            parameters: [parameter('title', text)],
            returnType: bookList,
          ),
        ]),
      );
      expect(handler, isA<RepositoryInvocationHandler>());
    }),
  );

  test(
    'an unknown property names the properties there are',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method(
              'findByTitel',
              parameters: [parameter('title', text)],
              returnType: bookList,
            ),
          ]),
        ),
        invalid(['BrokenRepository.findByTitel', "did you mean 'title'"]),
      );
    }),
  );

  test(
    'a parameter that does not fit is refused',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method(
              'findByYear',
              parameters: [parameter('year', text)],
              returnType: bookList,
            ),
          ]),
        ),
        invalid(['findByYear', 'does not fit']),
      );
    }),
  );

  test(
    '@Query needs a SQL store',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method(
              'search',
              returnType: bookList,
              annotations: const [Query('select * from books')],
            ),
          ]),
        ),
        invalid(['BrokenRepository.search', '@Query', 'SQL store']),
      );
      // Also for a method whose name would be a derived query.
      expect(
        () => factory.create(
          repository([
            method(
              'findByTitle',
              parameters: [parameter('title', text)],
              returnType: bookList,
              annotations: const [Query('select 1')],
            ),
          ]),
        ),
        invalid(['@Query', 'spring.datasource.url']),
      );
    }),
  );

  test(
    '@Lock is refused: the memory store has no transactions',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method(
              'findByTitle',
              parameters: [parameter('title', text)],
              returnType: bookList,
              annotations: const [Lock(LockMode.pessimisticWrite)],
            ),
          ]),
        ),
        invalid(['BrokenRepository.findByTitle', '@Lock', 'transactions']),
      );
    }),
  );

  test(
    'a synchronous method is refused',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method(
              'findByTitle',
              parameters: [parameter('title', text)],
              returnType: bookList,
              isFuture: false,
            ),
          ]),
        ),
        invalid(['findByTitle', 'asynchronous']),
      );
    }),
  );

  test(
    'a method that is neither CRUD nor derived is refused',
    () => run(() async {
      expect(
        () => factory.create(
          repository([method('doSomething', returnType: bookList)]),
        ),
        invalid(['BrokenRepository.doSomething', 'derived query']),
      );
      // A CRUD name with another arity is not CRUD.
      expect(
        () => factory.create(
          repository([
            method(
              'findAll',
              parameters: [parameter('x', text)],
              returnType: bookList,
            ),
          ]),
        ),
        invalid(['findAll']),
      );
    }),
  );

  test(
    'every problem is reported, not only the first',
    () => run(() async {
      expect(
        () => factory.create(
          repository([
            method('findByNope', returnType: bookList),
            method(
              'search',
              returnType: bookList,
              annotations: const [Query('x')],
            ),
            method('whatever', returnType: bookList),
          ]),
        ),
        invalid(['findByNope', 'BrokenRepository.search', 'whatever']),
      );
    }),
  );

  test(
    'an unknown store names the known ones',
    () => run(() async {
      expect(
        () => factory.create(
          repository(const [], annotations: const [UseStore('cassandra')]),
        ),
        invalid(["@UseStore('cassandra')", 'memory']),
      );
      expect(
        () => factory.create(
          repository(const [], annotations: const [UseStore('jdbc')]),
        ),
        invalid(["@UseStore('jdbc')", 'not available']),
      );
    }),
  );

  test(
    '@UseDataSource needs a SQL store unless the store is memory',
    () => run(() async {
      expect(
        () => factory.create(
          repository(const [], annotations: const [UseDataSource('reports')]),
        ),
        invalid(["@UseDataSource('reports')", 'SQL']),
      );
      expect(
        factory.create(
          repository(
            const [],
            annotations: const [UseStore('memory'), UseDataSource('reports')],
          ),
        ),
        isA<RepositoryInvocationHandler>(),
      );
    }),
  );

  test(
    'store problems come with the method problems',
    () => run(() async {
      expect(
        () => factory.create(
          repository(
            [
              method('findByNope', returnType: bookList),
            ],
            annotations: const [UseStore('cassandra')],
          ),
        ),
        invalid(['cassandra', 'findByNope']),
      );
    }),
  );

  test(
    'an entity that is not described is refused',
    () => run(() async {
      expect(
        () => factory.create(
          repository(const [], entity: const ClassType<Uri>()),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Uri'),
          ),
        ),
      );
    }),
  );

  test('the application fails to start with a broken repository', () async {
    final broken = BeanModule('broken', [
      BeanDefinition<Object>(
        name: 'brokenRepository',
        create: (r) => InterfaceProxies.handlerFor(
          r,
          repository([method('findByNope', returnType: bookList)]),
        ),
      ),
    ]);
    await exampleRunner.withUserConfiguration(broken).runAsync((context) {
      expect(
        context.startupFailure,
        isA<BeanCreationException>().having(
          (e) => '$e',
          'message',
          contains('findByNope'),
        ),
      );
    });
  });
}
