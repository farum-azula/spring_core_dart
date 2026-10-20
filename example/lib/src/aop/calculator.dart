import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks methods for the timing aspect.
class Timed {
  const Timed();
}

abstract interface class Calculator {
  int add(int a, int b);

  @Timed()
  int multiply(int a, int b);

  Future<int> slowAdd(int a, int b);

  int divide(int a, int b);
}

@Service()
class SimpleCalculator implements Calculator {
  @override
  int add(int a, int b) => a + b;

  @override
  int multiply(int a, int b) => a * b;

  @override
  Future<int> slowAdd(int a, int b) async => a + b;

  @override
  int divide(int a, int b) => a ~/ b;
}

abstract interface class Shouter {
  String shout(String text);
}

@Service()
class EchoShouter implements Shouter {
  @override
  String shout(String text) => text;
}

/// Upper-cases results: an advisor registered as a bean.
class UpperCaseInterceptor implements MethodInterceptor {
  @override
  Object? invoke(MethodInvocation invocation) =>
      (invocation.proceed()! as String).toUpperCase();
}
