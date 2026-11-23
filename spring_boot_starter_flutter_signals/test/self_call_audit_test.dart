// Spring's rule for the advice of a bean with followed state: a call through
// the proxy is advised, one on this is not, per call. A @Computed first read
// by a self-call keeps no self-call's invocation (SIG-1); an @Effect re-run
// by an assignment the bean makes after an await is the framework's call,
// with all of its advice (SIG-2).
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

class Audited {
  const Audited();
}

final log = <String>[];

final class _Audit implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) {
    log.add(invocation.signature.name);
    return invocation.proceed();
  }
}

final class _AuditPointcut implements AnnotationPointcut {
  const _AuditPointcut();

  @override
  bool matches(MethodSignature signature, String beanName) =>
      signature.mergedAnnotations.any((a) => a is Audited);
}

class Shop {
  @Signal()
  int price = 1;

  @Audited()
  @Computed()
  int get taxed => price * 2;

  int readTaxed() => taxed;

  final noted = <int>[];

  @Audited()
  @Effect()
  void note() => noted.add(price);

  Future<void> raise() async {
    await Future<void>.delayed(Duration.zero);
    price++;
  }
}

const _t = AopTarget('Shop', types: ['Shop']);

const _signatures = [
  MethodSignature.of(
    'price',
    _t,
    kind: MemberKind.getter,
    returnType: 'int',
    annotations: [Signal()],
  ),
  MethodSignature.of(
    'taxed',
    _t,
    kind: MemberKind.getter,
    returnType: 'int',
    annotations: [Audited(), Computed()],
  ),
  MethodSignature.of('readTaxed', _t, returnType: 'int'),
  MethodSignature.of(
    'price',
    _t,
    kind: MemberKind.setter,
    returnType: 'int',
    annotations: [Signal()],
  ),
  MethodSignature.of(
    'note',
    _t,
    returnType: 'void',
    annotations: [Audited(), Effect()],
  ),
  MethodSignature.of('raise', _t, returnType: 'Future'),
];

class _ShopProxy extends Shop with AdvisedSubclass {
  @override
  int get price =>
      aopInvoker!.invoke(
            proxy: this,
            target: this,
            methodIndex: 0,
            arguments: const [],
            original: (_) => super.price,
          )!
          as int;

  @override
  int get taxed =>
      aopInvoker!.invoke(
            proxy: this,
            target: this,
            methodIndex: 1,
            arguments: const [],
            original: (_) => super.taxed,
          )!
          as int;

  @override
  int readTaxed() =>
      aopInvoker!.invoke(
            proxy: this,
            target: this,
            methodIndex: 2,
            arguments: const [],
            original: (_) => super.readTaxed(),
          )!
          as int;

  @override
  set price(int value) => aopInvoker!.invoke(
    proxy: this,
    target: this,
    methodIndex: 3,
    arguments: [value],
    original: (a) {
      super.price = a[0]! as int;
      return null;
    },
  );

  @override
  void note() => aopInvoker!.invoke(
    proxy: this,
    target: this,
    methodIndex: 4,
    arguments: const [],
    original: (_) {
      super.note();
      return null;
    },
  );

  @override
  Future<void> raise() => aopInvoker!.invokeAsync<void>(
    proxy: this,
    target: this,
    methodIndex: 5,
    arguments: const [],
    original: (_) => super.raise(),
  );
}

_ShopProxy _shop(SignalBeans beans) => _ShopProxy()
  ..aopInvoker = ProxyInvoker(
    _signatures,
    [
      DefaultPointcutAdvisor(
        SignalsPointcut(beans),
        SignalsInterceptor(beans),
        order: Ordered.lowestPrecedence - 1,
      ),
      DefaultPointcutAdvisor(const _AuditPointcut(), _Audit()),
    ],
    'shop',
    adviseSelfCalls: true,
  );

void main() {
  setUp(log.clear);

  test(
    'a computed value first read by a self-call keeps the advice of outside '
    'reads (SIG-1)',
    () {
      final shop = _shop(SignalBeans()..names.add('shop'));
      expect(shop.readTaxed(), 2);
      expect(log, isEmpty, reason: 'a self-call is not advised');
      shop.price = 5;
      expect(shop.taxed, 10);
      expect(log, ['taxed']);
      shop.price = 6;
      expect(shop.taxed, 12);
      expect(log, ['taxed', 'taxed']);
    },
  );

  test(
    'an effect re-run by an assignment in the bean’s async body is advised '
    '(SIG-2)',
    () async {
      final beans = SignalBeans()..names.add('shop');
      final shop = _shop(beans);
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<Shop>(
            name: 'shop',
            source: 'package:test#Shop',
            annotatedMethods: [
              IntrospectedMethod<Shop>(
                'note',
                invoke: (bean, _) => bean.note(),
                isVoid: true,
                annotations: const [Audited(), Effect()],
              ),
            ],
            create: (_) => shop,
          ),
        );
      final effects = SignalEffects(beans)..setBeanFactory(factory);
      effects.postProcessAfterInitialization(shop, 'shop');
      expect(shop.noted, [1]);
      expect(log, ['note']);
      shop.price = 2;
      expect(shop.noted, [1, 2]);
      expect(log, ['note', 'note']);
      await shop.raise();
      expect(shop.noted, [1, 2, 3]);
      expect(log, ['note', 'note', 'note']);
    },
  );

  test('a field or computed value whose name looks secret shows no value '
      '(S-04)', () {
    final token = ValueMember('Session.accessToken', 'eyJ.secret');
    expect(token.hidden, isTrue);
    expect(SignalsDebugSection.describe(token), isNot(contains('eyJ')));
    final plain = ValueMember('TokenStore.count', 3);
    expect(plain.hidden, isFalse);
    expect(SignalsDebugSection.describe(plain), contains('3'));
    final computed = ComputedMember('Session.bearer', () => 'eyJ.secret');
    addTearDown(computed.dispose);
    expect(SignalsDebugSection.describe(computed), isNot(contains('eyJ')));
  });
}
