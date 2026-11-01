// The startup checks of @Transactional, the pointcut and the interceptor
// with hand-written signatures (no generated proxy needed).
import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support/recording_transaction_manager.dart';

class Orders {}

class _Boom implements Exception {}

class _SubBoom extends _Boom {}

MethodSignature _sig(
  String name,
  List<Object> annotations, {
  String returnType = 'Future',
  List<Object> classAnnotations = const [],
  MemberKind kind = MemberKind.method,
  bool isProtected = false,
}) => MethodSignature(
  name: name,
  declaringType: 'Orders',
  targetType: 'Orders',
  returnType: returnType,
  kind: kind,
  annotations: annotations,
  targetAnnotations: classAnnotations,
  isProtected: isProtected,
);

BeanModule _orders(List<MethodSignature> signatures) => BeanModule('app', [
  BeanDefinition<Orders>(
    name: 'orders',
    create: (_) => Orders(),
    aopProxy: AopProxyFactory(
      signatures: signatures,
      // Never reached by the failing cases: the validator stops first.
      create: (target, invoker) => target,
    ),
  ),
]);

BeanDefinition<Object> _manager(
  String name, {
  bool primary = false,
  Set<String> qualifiers = const {},
}) => BeanDefinition<RecordingTransactionManager>(
  name: name,
  types: const [RecordingTransactionManager, PlatformTransactionManager],
  create: (_) => RecordingTransactionManager(),
  primary: primary,
  qualifiers: qualifiers,
);

final class _Call implements MethodInvocation {
  _Call(this.signature, this.onProceed);

  @override
  final MethodSignature signature;
  final Object? Function() onProceed;

  @override
  List<Object?> get args => const [];

  @override
  Object get target => this;

  @override
  Object get proxy => this;

  @override
  Object? proceed([List<Object?>? arguments]) => onProceed();

  @override
  String toShortString() => 'execution(Orders.${signature.name}(..))';
}

void main() {
  final runner = const ApplicationContextRunner().withAutoConfiguration(
    springBootStarterDataAutoConfiguration,
  );

  Matcher failsWith(Iterable<String> texts) =>
      isA<AssertableApplicationContext>()
          .having((c) => c.hasFailed, 'hasFailed', isTrue)
          .having(
            (c) => '${c.startupFailure}',
            'startupFailure',
            allOf([for (final text in texts) contains(text)]),
          );

  group('the startup validator', () {
    test('a synchronous method stops the start', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('sync', const [Transactional()], returnType: 'int'),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(
              context,
              failsWith([
                '@Transactional Orders.sync returns int, not a Future',
              ]),
            );
          });
    });

    test('a Stream method stops the start', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('watch', const [Transactional()], returnType: 'Stream'),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(
              context,
              failsWith(['Orders.watch returns Stream', 'a Stream']),
            );
          });
    });

    test('a void method stops the start', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('go', const [Transactional()], returnType: 'void'),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(context, failsWith(['Orders.go returns void']));
          });
    });

    test('an unknown transaction manager stops the start', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('place', const [Transactional(transactionManager: 'nope')]),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(
              context,
              failsWith([
                '@Transactional Orders.place',
                "no PlatformTransactionManager bean or qualifier named 'nope'",
              ]),
            );
          });
    });

    test('without a manager of the application the memory one serves', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('place', const [Transactional()]),
            ]),
          )
          .run((context) {
            expect(context.hasFailed, isFalse);
            expect(
              context.getBean<PlatformTransactionManager>(),
              isA<InMemoryTransactionManager>(),
            );
          });
    });

    test('several managers without a primary one stop the start', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('place', const [Transactional()]),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('first'), _manager('second')]),
          )
          .run((context) {
            expect(
              context,
              failsWith([
                'several PlatformTransactionManager beans (first, second)',
                'mark one @Primary',
              ]),
            );
          });
    });

    test('every problem is listed', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('a', const [Transactional()], returnType: 'String'),
              _sig('b', const [Transactional()], returnType: 'Stream'),
              _sig('c', const [Transactional(transactionManager: 'x')]),
              _sig('fine', const [Transactional()]),
              _sig('notTransactional', const [], returnType: 'int'),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(
              context,
              failsWith([
                'Orders.a returns String',
                'Orders.b returns Stream',
                'Orders.c: no PlatformTransactionManager bean or qualifier',
              ]),
            );
            expect('${context.startupFailure}', isNot(contains('fine')));
            expect(
              '${context.startupFailure}',
              isNot(contains('notTransactional')),
            );
          });
    });

    test('a correct application starts: primary, name, alias, qualifier', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig('primary', const [Transactional()]),
              _sig('named', const [
                Transactional(transactionManager: 'second'),
              ]),
              _sig('qualified', const [
                Transactional(transactionManager: 'audit'),
              ]),
              _sig(
                'onClass',
                const [],
                classAnnotations: const [Transactional()],
              ),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [
              _manager('first', primary: true),
              _manager('second'),
              _manager('third', qualifiers: {'audit'}),
            ]),
          )
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context, hasSingleBean<TransactionTemplate>());
          });
    });

    test('a class-level annotation on a sync method is checked too', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig(
                'count',
                const [],
                returnType: 'int',
                classAnnotations: [
                  const Transactional(),
                ],
              ),
            ]),
          )
          .withUserConfiguration(
            BeanModule('m', [_manager('transactionManager')]),
          )
          .run((context) {
            expect(context, failsWith(['Orders.count returns int']));
          });
    });

    test('getters, setters and protected members are not transactional', () {
      runner
          .withUserConfiguration(
            _orders([
              _sig(
                'total',
                const [Transactional()],
                returnType: 'int',
                kind: MemberKind.getter,
              ),
              _sig(
                'inner',
                const [Transactional()],
                returnType: 'int',
                isProtected: true,
              ),
              _sig('toString', const [Transactional()], returnType: 'String'),
            ]),
          )
          .run((context) {
            expect(context.startupFailure, isNull);
          });
    });
  });

  group('the TransactionTemplate bean', () {
    test('exists for exactly one manager', () {
      runner.withUserConfiguration(BeanModule('m', [_manager('only')])).run((
        context,
      ) {
        expect(context, hasSingleBean<TransactionTemplate>());
      });
    });

    test('is made of the memory manager, and absent with several', () {
      runner.run((context) {
        expect(context, hasBean<TransactionTemplate>());
        expect(
          context.getBean<TransactionTemplate>().manager,
          isA<InMemoryTransactionManager>(),
        );
      });
      runner
          .withUserConfiguration(
            BeanModule('m', [_manager('first'), _manager('second')]),
          )
          .run((context) {
            expect(context, doesNotHaveBean<TransactionTemplate>());
          });
    });

    test('the application can declare its own', () {
      final own = TransactionTemplate(RecordingTransactionManager());
      runner
          .withUserConfiguration(
            BeanModule('m', [
              _manager('only'),
              BeanDefinition<TransactionTemplate>(
                name: 'myTemplate',
                create: (_) => own,
              ),
            ]),
          )
          .run((context) {
            expect(context.getBean<TransactionTemplate>(), same(own));
          });
    });
  });

  group('the pointcut', () {
    const pointcut = TransactionAnnotationPointcut();

    test('matches the annotated method or class, not the rest', () {
      expect(pointcut.matches(_sig('a', const [Transactional()]), 'b'), isTrue);
      expect(
        pointcut.matches(
          _sig('a', const [], classAnnotations: [const Transactional()]),
          'b',
        ),
        isTrue,
      );
      expect(pointcut.matches(_sig('a', const []), 'b'), isFalse);
      expect(pointcut.matches(_sig('a', const [Object()]), 'b'), isFalse);
    });

    test('the method annotation wins over the class one', () {
      final signature = _sig(
        'a',
        const [Transactional(propagation: Propagation.never)],
        classAnnotations: [const Transactional(readOnly: true)],
      );
      final found = TransactionAnnotationPointcut.transactionalOf(signature)!;
      expect(found.propagation, Propagation.never);
      expect(found.readOnly, isFalse);
    });
  });

  group('the interceptor', () {
    late RecordingTransactionManager manager;
    late TransactionInterceptor interceptor;

    setUp(() {
      manager = RecordingTransactionManager();
      interceptor = TransactionInterceptor(transactionManager: manager);
    });

    Future<Object?> call(
      List<Object> annotations,
      Object? Function() body,
    ) =>
        interceptor.invoke(_Call(_sig('place', annotations), body))!
            as Future<Object?>;

    test('needs a bean factory or a manager', () {
      expect(TransactionInterceptor.new, throwsArgumentError);
    });

    test('runs the method in a transaction named Class.method', () async {
      await call(const [Transactional()], () async {
        expect(
          TransactionSynchronizationManager.currentTransactionName,
          'Orders.place',
        );
        return 1;
      });
      expect(manager.calls, ['begin 1', 'commit 1']);
    });

    test('a method that is not transactional is called as it is', () async {
      final result = interceptor.invoke(
        _Call(_sig('plain', const []), () => 'direct'),
      );
      expect(result, 'direct');
      expect(manager.calls, isEmpty);
    });

    test(
      'a synchronous error of the method is an error of the Future',
      () async {
        final result = call(const [Transactional()], () => throw _Boom());
        await expectLater(result, throwsA(isA<_Boom>()));
        expect(manager.calls, ['begin 1', 'rollback 1']);
      },
    );

    test('rules: noRollbackFor with subtypes, rollbackFor over it', () {
      const rules = Transactional(
        noRollbackFor: [_Boom],
        rollbackFor: [_SubBoom],
      );
      final plan = interceptor.planOf(_sig('place', const [rules]))!;
      // Without generated type tests the exact runtime type is compared:
      // a subtype needs a test, as the generator writes for annotations.
      expect(plan.rollsBackOn(StateError('x')), isTrue);
      expect(plan.rollsBackOn(_Boom()), isFalse);
      expect(plan.rollsBackOn(_SubBoom()), isTrue);
    });

    test("rules use the introspector's subtype tests", () {
      final introspector = BeanIntrospector()
        ..registerTypeTests({_Boom: (value) => value is _Boom});
      final custom = TransactionInterceptor(
        transactionManager: manager,
        introspector: introspector,
      );
      final plan = custom.planOf(
        _sig('place', const [
          Transactional(noRollbackFor: [_Boom]),
        ]),
      )!;
      expect(plan.rollsBackOn(_SubBoom()), isFalse);
      expect(plan.rollsBackOn(StateError('x')), isTrue);
    });

    test('the plan is computed once per member', () {
      final signature = _sig('place', const [Transactional()]);
      expect(
        interceptor.planOf(signature),
        same(interceptor.planOf(signature)),
      );
      expect(interceptor.planOf(_sig('x', const [])), isNull);
    });

    test("the definition has the annotation's settings", () {
      final plan = interceptor.planOf(
        _sig('place', const [
          Transactional(
            propagation: Propagation.requiresNew,
            isolation: Isolation.repeatableRead,
            timeout: Duration(seconds: 3),
            readOnly: true,
          ),
        ]),
      )!;
      expect(
        plan.definition.toString(),
        'PROPAGATION_requiresNew, ISOLATION_repeatableRead, timeout 3000 ms, '
        'readOnly',
      );
      expect(plan.definition.name, 'Orders.place');
    });
  });
}
