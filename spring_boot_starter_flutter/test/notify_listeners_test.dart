import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

class Basket extends ChangeNotifier {
  int count = 0;
}

class Plain {}

/// A call of [name] on [target] that runs [body].
class _Call implements MethodInvocation {
  _Call(this.target, this.body, {String name = 'add', Object? proxy})
    : proxy = proxy ?? target,
      signature = MethodSignature(
        name: name,
        declaringType: 'Basket',
        targetType: 'Basket',
      );

  @override
  final Object target;

  @override
  final Object proxy;

  final Object? Function() body;

  @override
  final MethodSignature signature;

  @override
  Object? proceed([List<Object?>? args]) => body();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MethodSignature signature(
  String name, {
  MemberKind kind = MemberKind.method,
  List<Object> annotations = const [],
  List<Object> classAnnotations = const [],
}) => MethodSignature(
  name: name,
  declaringType: 'Basket',
  targetType: 'Basket',
  kind: kind,
  annotations: annotations,
  targetAnnotations: classAnnotations,
);

void main() {
  group('NotifyListenersPointcut', () {
    const pointcut = NotifyListenersPointcut();
    const notify = NotifyListeners();

    test('a method or setter carrying it', () {
      expect(
        pointcut.matches(signature('add', annotations: [notify]), 'basket'),
        isTrue,
      );
      expect(
        pointcut.matches(
          signature('count', kind: MemberKind.setter, annotations: [notify]),
          'basket',
        ),
        isTrue,
      );
      expect(pointcut.matches(signature('add'), 'basket'), isFalse);
    });

    test('on the class: methods and setters, not getters or the '
        "notifier's own members", () {
      bool matches(String name, [MemberKind kind = MemberKind.method]) =>
          pointcut.matches(
            signature(name, kind: kind, classAnnotations: [notify]),
            'basket',
          );
      expect(matches('add'), isTrue);
      expect(matches('count', MemberKind.setter), isTrue);
      expect(matches('count', MemberKind.getter), isFalse);
      for (final own in [
        'addListener',
        'removeListener',
        'dispose',
        'notifyListeners',
        'toString',
      ]) {
        expect(matches(own), isFalse, reason: own);
      }
      expect(matches('hasListeners', MemberKind.getter), isFalse);
    });
  });

  test('class level: excluded names and @ChangeNotifierComponent', () {
    const pointcut = NotifyListenersPointcut();
    bool matches(Object annotation, String name) => pointcut.matches(
      signature(name, classAnnotations: [annotation]),
      'basket',
    );
    expect(matches(const NotifyListeners(exclude: ['peek']), 'add'), isTrue);
    expect(matches(const NotifyListeners(exclude: ['peek']), 'peek'), isFalse);
    expect(matches(const ChangeNotifierComponent(), 'add'), isTrue);
    expect(
      matches(const ChangeNotifierComponent(exclude: ['reset']), 'reset'),
      isFalse,
    );
    expect(matches(const ChangeNotifierComponent(), 'dispose'), isFalse);
    expect(matches(const Component(), 'add'), isFalse);
  });

  group('NotifyListenersInterceptor', () {
    const interceptor = NotifyListenersInterceptor();

    test('notifies after the method', () {
      final basket = Basket();
      final seen = <int>[];
      basket.addListener(() => seen.add(basket.count));
      final result = interceptor.invoke(_Call(basket, () => ++basket.count));
      expect(result, 1);
      expect(seen, [1]);
    });

    test('a Future: once it completes, with its value', () async {
      final basket = Basket();
      final seen = <int>[];
      basket.addListener(() => seen.add(basket.count));
      final done = Completer<int>();
      final result = interceptor.invoke(_Call(basket, () => done.future));
      expect(result, isA<Future<int>>());
      expect(seen, isEmpty);
      basket.count = 5;
      done.complete(5);
      expect(await (result! as Future<int>), 5);
      expect(seen, [5]);
    });

    test('also when the method throws', () {
      final basket = Basket();
      var notified = 0;
      basket.addListener(() => notified++);
      expect(
        () => interceptor.invoke(_Call(basket, () => throw StateError('x'))),
        throwsStateError,
      );
      expect(notified, 1);
    });

    test('a proxy that is the ChangeNotifier (a @ChangeNotifierComponent) '
        'is notified, not its target', () {
      final proxy = Basket();
      var notified = 0;
      proxy.addListener(() => notified++);
      const NotifyListenersInterceptor().invoke(
        _Call(Plain(), () => null, proxy: proxy),
      );
      expect(notified, 1);
    });

    test('a bean that is no ChangeNotifier is an error', () {
      expect(
        () => interceptor.invoke(_Call(Plain(), () => null)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no ChangeNotifier'),
          ),
        ),
      );
    });
  });

  test('listenableOf', () {
    final basket = Basket();
    expect(listenableOf(basket), same(basket));
    expect(() => listenableOf(Plain()), throwsArgumentError);
  });
}
