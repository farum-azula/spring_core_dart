// A generated subclass proxy is the bean itself: calls the bean makes on
// itself skip the advice, as `this.` calls on Spring's target do.
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Nested {
  String outer() => 'outer(${inner()})';

  String inner() => 'inner';

  String viaProxy() => 'via(${(AopContext.currentProxy() as Nested).inner()})';

  Future<String> outerLater() async {
    await Future<void>.delayed(Duration.zero);
    return 'later(${inner()}, ${await innerLater()})';
  }

  Future<String> innerLater() async => 'innerLater';
}

const _signatures = [
  MethodSignature(name: 'outer', declaringType: 'Nested', targetType: 'N'),
  MethodSignature(name: 'inner', declaringType: 'Nested', targetType: 'N'),
  MethodSignature(name: 'viaProxy', declaringType: 'Nested', targetType: 'N'),
  MethodSignature(name: 'outerLater', declaringType: 'Nested', targetType: 'N'),
  MethodSignature(name: 'innerLater', declaringType: 'Nested', targetType: 'N'),
];

// What the generator writes for a subclass proxy (trimmed).
class _$NestedProxy extends Nested {
  ProxyInvoker? _$invoker;

  @override
  String outer() {
    final i = _$invoker;
    return i == null
        ? super.outer()
        : i.invoke(this, this, 0, const [], (args) => super.outer())! as String;
  }

  @override
  String inner() {
    final i = _$invoker;
    return i == null
        ? super.inner()
        : i.invoke(this, this, 1, const [], (args) => super.inner())! as String;
  }

  @override
  String viaProxy() {
    final i = _$invoker;
    return i == null
        ? super.viaProxy()
        : i.invoke(this, this, 2, const [], (args) => super.viaProxy())!
              as String;
  }

  @override
  Future<String> outerLater() {
    final i = _$invoker;
    return i == null
        ? super.outerLater()
        : i.invokeAsync<String>(
            this,
            this,
            3,
            const [],
            (args) => super.outerLater(),
          );
  }

  @override
  Future<String> innerLater() {
    final i = _$invoker;
    return i == null
        ? super.innerLater()
        : i.invokeAsync<String>(
            this,
            this,
            4,
            const [],
            (args) => super.innerLater(),
          );
  }
}

class _Record implements MethodInterceptor {
  final calls = <String>[];

  @override
  Object? invoke(MethodInvocation invocation) {
    calls.add(invocation.signature.name);
    return invocation.proceed();
  }
}

class _CallInner implements MethodInterceptor {
  _CallInner(this.bean, this.calls);

  final Nested bean;
  final List<String> calls;

  @override
  Object? invoke(MethodInvocation invocation) {
    calls.add(bean.inner());
    return invocation.proceed();
  }
}

void main() {
  late _$NestedProxy bean;
  late _Record record;

  setUp(() {
    record = _Record();
    bean = _$NestedProxy()
      .._$invoker = ProxyInvoker(_signatures, [
        DefaultPointcutAdvisor(const TruePointcut(), record),
      ], 'nested');
  });

  test('a self-call skips the advice (Spring: [outer])', () {
    expect(bean.outer(), 'outer(inner)');
    expect(record.calls, ['outer']);
    expect(bean.inner(), 'inner');
    expect(record.calls, ['outer', 'inner']);
  });

  test('a self-call through AopContext.currentProxy() is advised', () {
    expect(bean.viaProxy(), 'via(inner)');
    expect(record.calls, ['viaProxy', 'inner']);
    // The pass is used up: a later self-call is not advised.
    expect(bean.outer(), 'outer(inner)');
    expect(record.calls, ['viaProxy', 'inner', 'outer']);
  });

  test('self-calls after an await skip the advice too', () async {
    expect(await bean.outerLater(), 'later(inner, innerLater)');
    expect(record.calls, ['outerLater']);
  });

  test('calls from outside while a Future member waits are advised', () async {
    final pending = bean.outerLater();
    expect(bean.inner(), 'inner');
    await pending;
    expect(record.calls, ['outerLater', 'inner']);
  });

  test('advice code calling the bean is advised', () {
    final calls = <String>[];
    bean._$invoker!.addAdvisor(
      DefaultPointcutAdvisor(
        const NameMatchMethodPointcut(['outer']),
        _CallInner(bean, calls),
      ),
    );
    bean.outer();
    expect(record.calls, ['outer', 'inner']);
    expect(calls, ['inner']);
  });
}
