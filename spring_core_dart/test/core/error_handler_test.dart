// The handler of a component's errors, and the one for a single type:
// neither can be taken for the other.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

final class PaymentFailure implements Exception {}

final class ShippingFailure implements Exception {}

final class AnyErrors implements ErrorHandler {
  final seen = <Object>[];

  @override
  void handleError(Object error, StackTrace stackTrace) => seen.add(error);
}

final class PaymentErrors implements TypedErrorHandler<PaymentFailure> {
  final seen = <PaymentFailure>[];

  @override
  void handleError(PaymentFailure error, StackTrace stackTrace) =>
      seen.add(error);
}

final class ShippingErrors implements TypedErrorHandler<ShippingFailure> {
  @override
  void handleError(ShippingFailure error, StackTrace stackTrace) {}
}

DefaultListableBeanFactory _factory() => DefaultListableBeanFactory()
  ..registerBeanDefinition(
    BeanDefinition<PaymentErrors>(
      name: 'paymentErrors',
      types: const [PaymentErrors, TypedErrorHandler<PaymentFailure>],
      create: (_) => PaymentErrors(),
    ),
  )
  ..registerBeanDefinition(
    BeanDefinition<ShippingErrors>(
      name: 'shippingErrors',
      types: const [ShippingErrors, TypedErrorHandler<ShippingFailure>],
      create: (_) => ShippingErrors(),
    ),
  );

void main() {
  test('a typed handler is no handler of any error', () {
    expect(PaymentErrors(), isNot(isA<ErrorHandler>()));
    expect(AnyErrors(), isNot(isA<TypedErrorHandler<Object>>()));
  });

  test('a typed handler is not one of another type', () {
    expect(PaymentErrors(), isA<TypedErrorHandler<PaymentFailure>>());
    expect(PaymentErrors(), isNot(isA<TypedErrorHandler<ShippingFailure>>()));
  });

  test('the container finds each typed handler by its type', () {
    final factory = _factory();
    expect(
      factory.getBean<TypedErrorHandler<PaymentFailure>>(),
      isA<PaymentErrors>(),
    );
    expect(
      factory.getBean<TypedErrorHandler<ShippingFailure>>(),
      isA<ShippingErrors>(),
    );
  });

  test('asking for any handler finds no typed one', () {
    expect(_factory().provider<ErrorHandler>().getIfUnique(), isNull);
  });

  test('it receives its error', () {
    final handler = PaymentErrors();
    final failure = PaymentFailure();
    handler.handleError(failure, StackTrace.current);
    expect(handler.seen, [failure]);
  });
}
