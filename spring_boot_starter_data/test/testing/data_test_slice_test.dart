// Which beans of an application a @DataTest keeps: the data ones, the ones it
// is told to include, and what they need to be made.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_data/testing.dart';
import 'package:test/test.dart';

abstract interface class Book {}

abstract interface class BookRepository
    implements ListCrudRepository<Book, int> {}

class Orders {}

class Mailer {}

class Config {
  Config();
}

class Reporter implements CommandLineRunner {
  @override
  Future<void> run(List<String> args) async {}
}

class Auditor implements AuditorAware<String> {
  @override
  String? getCurrentAuditor() => 'me';
}

class Prefixes extends NamingStrategy {
  const Prefixes();
}

class Clock extends DateTimeProvider {
  const Clock();
}

class FakeStore implements DataStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeManager implements PlatformTransactionManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BeanDefinition<Object> _bean(
  String name,
  List<Type> types, {
  String? factory,
  List<Object> annotations = const [],
  String? source,
}) => BeanDefinition<Object>(
  name: name,
  types: types,
  source: source ?? 'test#$name',
  factoryBeanName: factory,
  annotations: annotations,
  create: (_) => Object(),
);

// The beans of an application module, as the generator describes them.
final _application = BeanModule('application', [
  _bean('bookRepository', const [
    BookRepository,
    ListCrudRepository<Book, int>,
    CrudRepository<Book, int>,
    DataRepository<Book, int>,
    ListCrudRepository<dynamic, dynamic>,
    CrudRepository<dynamic, dynamic>,
    DataRepository<dynamic, dynamic>,
  ]),
  _bean('entityIntrospections#application', const [EntityIntrospections]),
  _bean('auditor', const [
    Auditor,
    AuditorAware<String>,
    AuditorAware<dynamic>,
  ]),
  _bean('prefixes', const [Prefixes, NamingStrategy]),
  _bean('clock', const [Clock, DateTimeProvider]),
  _bean('store', const [FakeStore, DataStore]),
  _bean('manager', const [FakeManager, PlatformTransactionManager]),
  _bean('sqlite3JdbcDriver', const [JdbcDriver]),
  _bean('orders', const [Orders]),
  _bean('mailer', const [Mailer]),
  _bean('reporter', const [Reporter, CommandLineRunner]),
  _bean('config', const [Config]),
]);

DefaultListableBeanFactory _registryOf(
  BeanModule module, {
  List<BeanDefinition<Object>> others = const [],
}) {
  final factory = DefaultListableBeanFactory();
  [...module.definitions, ...others].forEach(factory.registerBeanDefinition);
  return factory;
}

Set<String> _slice(
  BeanModule module, {
  List<Type> include = const [],
  List<BeanDefinition<Object>> others = const [],
}) {
  final registry = _registryOf(module, others: others);
  DataTestSlice([
    module,
  ], include: include).postProcessBeanDefinitionRegistry(registry);
  return registry.beanDefinitionNames.toSet();
}

void main() {
  test('the data beans stay, the other components go', () {
    expect(_slice(_application), {
      'bookRepository',
      'entityIntrospections#application',
      'auditor',
      'prefixes',
      'clock',
      'store',
      'manager',
      'sqlite3JdbcDriver',
    });
  });

  test('every type of the starter that an application replaces is a data '
      'type', () {
    expect(
      DataTestSlice.dataTypes,
      containsAll([
        DataRepository<dynamic, dynamic>,
        EntityIntrospections,
        JdbcDriver,
        DataSource,
        DataStore,
        PlatformTransactionManager,
        TransactionTemplate,
        JdbcTemplate,
        NamedParameterJdbcTemplate,
        JdbcClient,
        NamingStrategy,
        AuditorAware<dynamic>,
        DateTimeProvider,
        RelationalMappingContext,
        EntityConverter,
        RepositoryFactory,
      ]),
    );
  });

  test('a class with @EnableDataAuditing stays, though it is a plain '
      'configuration', () {
    final module = BeanModule('application', [
      _bean(
        'auditing',
        const [Config],
        annotations: const [EnableDataAuditing()],
      ),
      _bean('orders', const [Orders]),
    ]);
    expect(_slice(module), {'auditing'});
  });

  group('@Bean methods', () {
    final module = BeanModule('application', [
      _bean('settings', const [Config]),
      _bean('auditor', const [
        Auditor,
        AuditorAware<dynamic>,
      ], factory: 'settings'),
      _bean('mailer', const [Mailer], factory: 'settings'),
      _bean('orders', const [Orders]),
    ]);

    test('a data bean brings the configuration object that makes it, not '
        'its other beans', () {
      expect(_slice(module), {'settings', 'auditor'});
    });

    test('an included configuration brings all its beans', () {
      expect(_slice(module, include: [Config]), {
        'settings',
        'auditor',
        'mailer',
      });
    });
  });

  group('include', () {
    test('adds the beans of the types it names', () {
      expect(
        _slice(_application, include: [Orders]),
        containsAll(['orders', 'bookRepository']),
      );
      expect(
        _slice(_application, include: [Orders]),
        isNot(contains('mailer')),
      );
    });

    test('names a bean by any of its types', () {
      expect(
        _slice(_application, include: [CommandLineRunner]),
        contains('reporter'),
      );
    });

    test('a type no bean has fails, naming it', () {
      expect(
        () => _slice(_application, include: [String]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('@DataTest(include: [String])'),
              contains('no bean'),
            ),
          ),
        ),
      );
    });
  });

  group("what is not the application's", () {
    test('beans of other modules and added by a test are left alone', () {
      final names = _slice(
        _application,
        others: [
          // The auto-configuration of a starter, a @TestBean.
          _bean('cacheManager', const [Mailer], source: 'starter#cache'),
          _bean('orders#fake', const [Orders]),
        ],
      );
      expect(names, containsAll(['cacheManager', 'orders#fake']));
      expect(names, isNot(contains('orders')));
    });

    test('a definition of the same name from another source is not the '
        "application's", () {
      final registry = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          _bean('orders', const [Orders], source: 'starter#orders'),
        );
      DataTestSlice([_application]).postProcessBeanDefinitionRegistry(registry);
      expect(registry.containsBeanDefinition('orders'), isTrue);
    });

    test(
      "the modules an application module imports are the application's",
      () {
        final imported = BeanModule('imported', [
          _bean('billing', const [Orders]),
          _bean('billingRepository', const [DataRepository<dynamic, dynamic>]),
        ]);
        final module = BeanModule(
          'application',
          [
            _bean('mailer', const [Mailer]),
          ],
          imports: [imported],
        );
        final registry = _registryOf(imported)
          ..registerBeanDefinition(module.definitions.single);
        DataTestSlice([module]).postProcessBeanDefinitionRegistry(registry);
        expect(registry.beanDefinitionNames, ['billingRepository']);
      },
    );

    test('a slice made from the same definitions twice is the same', () {
      expect(_slice(_application), _slice(_application));
    });
  });
}
