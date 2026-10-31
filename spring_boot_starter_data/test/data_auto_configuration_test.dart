import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/app.dart';

final class _Auditor implements AuditorAware<String> {
  _Auditor(this.name);

  final String name;

  @override
  String? getCurrentAuditor() => name;
}

final class _PrefixedNaming extends NamingStrategy {
  const _PrefixedNaming();

  @override
  String tableName(String className, Table? table) =>
      'app_${super.tableName(className, table)}';
}

// A configuration bean carrying @EnableDataAuditing with [settings].
BeanModule _auditing(
  EnableDataAuditing settings, [
  List<BeanDefinition<Object>> beans = const [],
]) => BeanModule('auditing', [
  BeanDefinition<Object>(
    name: 'auditingSetup',
    create: (_) => Object(),
    annotations: [settings],
  ),
  ...beans,
]);

BeanDefinition<Object> _auditor(String name, {String? bean}) =>
    BeanDefinition<_Auditor>(
      name: bean ?? name,
      types: const [_Auditor, AuditorAware<String>],
      create: (_) => _Auditor(name),
    );

void main() {
  const runner = ApplicationContextRunner();

  test('the starter adds its beans', () {
    exampleRunner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<RelationalMappingContext>());
      expect(context, hasSingleBean<EntityConverter>());
      expect(context, hasSingleBean<InMemoryDataStore>());
      expect(context, hasSingleBean<RepositoryFactory>());
      expect(context, hasSingleBean<AuditingHandler>());
      expect(context, hasBean<DataStore>());
      expect(context, hasBean<InvocationHandlerFactory>());
      expect(context, hasBeanNamed('bookRepository'));
    });
  });

  test("the mapping context uses the context's introspector", () {
    exampleRunner.run((context) {
      final mapping = context.getBean<RelationalMappingContext>();
      expect(mapping.introspector, same(context.getBean<BeanIntrospector>()));
      // Described by the generated module, found through it.
      expect(mapping.getRequiredPersistentEntity<Book>().tableName, 'books');
    });
  });

  test('without @EnableDataAuditing there is no auditing', () {
    runner.withAutoConfiguration(springBootStarterDataAutoConfiguration).run((
      context,
    ) {
      expect(context.startupFailure, isNull);
      expect(context, doesNotHaveBean<AuditingHandler>());
      expect(context, hasSingleBean<RepositoryFactory>());
    });
  });

  test("beans of the application replace the starter's", () {
    final converter = EntityConverter();
    final store = InMemoryDataStore(converter: converter, name: 'mine');
    exampleRunner
        .withBean<EntityConverter>(() => converter)
        .withBean<InMemoryDataStore>(() => store)
        .run((context) {
          expect(context.startupFailure, isNull);
          expect(context.getBean<EntityConverter>(), same(converter));
          expect(context.getBean<InMemoryDataStore>(), same(store));
          expect(context, hasSingleBean<EntityConverter>());
          expect(context, hasSingleBean<InMemoryDataStore>());
        });
  });

  test('a NamingStrategy bean names the tables', () {
    exampleRunner.withBean<NamingStrategy>(_PrefixedNaming.new).run((context) {
      final mapping = context.getBean<RelationalMappingContext>();
      expect(mapping.namingStrategy, isA<_PrefixedNaming>());
      expect(
        mapping.getRequiredPersistentEntity<Book>().tableName,
        'app_books',
      );
    });
  });

  test(
    "an application's DataStore is a store repositories can name",
    () async {
      final custom = InMemoryDataStore(
        converter: EntityConverter(),
        name: 'archive',
      );
      final annotated = BeanModule('archived', [
        BeanDefinition<InMemoryDataStore>(
          name: 'archive',
          types: const [InMemoryDataStore, DataStore],
          create: (_) => custom,
        ),
      ]);
      await exampleRunner.withUserConfiguration(annotated).runAsync((context) {
        final factory = context.getBean<RepositoryFactory>();
        expect(factory.stores.keys, containsAll(['memory', 'archive']));
      });
    },
  );

  group('@EnableDataAuditing', () {
    test('the only AuditorAware and DateTimeProvider beans are used', () {
      final clock = DateTimeProvider(() => DateTime.utc(2000));
      runner
          .withUserConfiguration(
            _auditing(const EnableDataAuditing(), [_auditor('ada')]),
          )
          .withBean<DateTimeProvider>(() => clock)
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            expect(context.startupFailure, isNull);
            final handler = context.getBean<AuditingHandler>();
            expect(handler.auditorAware, isA<_Auditor>());
            expect(handler.dateTimeProvider, same(clock));
            expect(handler.setDates, isTrue);
            expect(handler.modifyOnCreate, isTrue);
          });
    });

    test('references pick a bean among several', () {
      runner
          .withUserConfiguration(
            _auditing(const EnableDataAuditing(auditorAwareRef: 'grace'), [
              _auditor('ada'),
              _auditor('grace'),
            ]),
          )
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            final handler = context.getBean<AuditingHandler>();
            expect((handler.auditorAware! as _Auditor).name, 'grace');
          });
    });

    test('the flags are passed on', () {
      runner
          .withUserConfiguration(
            _auditing(
              const EnableDataAuditing(setDates: false, modifyOnCreate: false),
            ),
          )
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            final handler = context.getBean<AuditingHandler>();
            expect(handler.setDates, isFalse);
            expect(handler.modifyOnCreate, isFalse);
            expect(handler.auditorAware, isNull);
          });
    });

    test('several auditors without a reference fail the start', () {
      runner
          .withUserConfiguration(
            _auditing(const EnableDataAuditing(), [
              _auditor('ada'),
              _auditor('grace'),
            ]),
          )
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            expect(
              context,
              hasFailed(
                isA<BeanCreationException>().having(
                  (e) => '$e',
                  'message',
                  contains('Several AuditorAware beans'),
                ),
              ),
            );
          });
    });

    test('a reference to nothing, or to a bean of another type, fails', () {
      runner
          .withUserConfiguration(
            _auditing(const EnableDataAuditing(auditorAwareRef: 'nobody')),
          )
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            expect(
              context,
              hasFailed(
                isA<BeanCreationException>().having(
                  (e) => '$e',
                  'message',
                  contains('auditorAwareRef: "nobody"'),
                ),
              ),
            );
          });
      runner
          .withUserConfiguration(
            _auditing(
              const EnableDataAuditing(dateTimeProviderRef: 'auditingSetup'),
            ),
          )
          .withAutoConfiguration(springBootStarterDataAutoConfiguration)
          .run((context) {
            expect(
              context,
              hasFailed(
                isA<BeanCreationException>().having(
                  (e) => '$e',
                  'message',
                  contains('not a DateTimeProvider'),
                ),
              ),
            );
          });
    });

    test("an AuditingHandler of the application replaces the starter's", () {
      final own = AuditingHandler(converter: EntityConverter());
      exampleRunner.withBean<AuditingHandler>(() => own).run((context) {
        expect(context.getBean<AuditingHandler>(), same(own));
      });
    });
  });
}
