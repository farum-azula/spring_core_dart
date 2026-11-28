// A @Retryable method returning an EventStream: retried into the stream
// the caller listens to, which stays an EventStream with whole events.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

class Feed {
  int calls = 0;

  @Retryable(maxRetries: 2, delay: Duration(milliseconds: 1))
  EventStream<String> orders() {
    final attempt = ++calls;
    return EventStream<String>(() async* {
      yield ServerSentEvent('order $attempt', id: '$attempt');
      if (attempt < 3) {
        throw StateErrorLike('lost $attempt');
      }
    });
  }
}

final class StateErrorLike implements Exception {
  StateErrorLike(this.message);

  final String message;
}

const _target = AopTarget('Feed', types: ['Feed']);

const _signatures = [
  MethodSignature.of(
    'orders',
    _target,
    returnType: 'EventStream',
    annotations: [
      Retryable(maxRetries: 2, delay: Duration(milliseconds: 1)),
    ],
    annotationTypes: ['Retryable'],
    returnTypeArguments: [TypeCapture<String>()],
  ),
];

class _$FeedProxy implements Feed {
  _$FeedProxy(this._target, this._invoker);

  final Feed _target;
  final ProxyInvoker _invoker;

  @override
  int get calls => _target.calls;

  @override
  set calls(int value) => _target.calls = value;

  @override
  EventStream<String> orders() =>
      this._invoker.invoke(
            proxy: this,
            target: this._target,
            methodIndex: 0,
            arguments: const [],
            original: (args) => this._target.orders(),
          )!
          as EventStream<String>;
}

Feed _proxied(Feed feed) {
  final factory =
      ProxyFactory(
        feed,
        AopProxyFactory(
          signatures: _signatures,
          create: (target, invoker) => _$FeedProxy(target as Feed, invoker),
        ),
      )..addAdvisor(
        DefaultPointcutAdvisor(
          const RetryablePointcut(),
          RetryInterceptor(streamAdapters: const [EventStreamRetryAdapter()]),
          order: AdvisorOrder.retry,
        ),
      );
  return factory.getProxy() as Feed;
}

void main() {
  test('the retried stream is an EventStream of every call', () async {
    final feed = Feed();
    final orders = _proxied(feed).orders();
    expect(orders, isA<EventStream<String>>());
    expect(await orders.toList(), ['order 1', 'order 2', 'order 3']);
    expect(feed.calls, 3);
  });

  test('the whole events come through, with their ids', () async {
    final feed = Feed();
    final events = await _proxied(feed).orders().events.toList();
    expect([for (final e in events) e.id], ['1', '2', '3']);
  });

  test('without the adapter the type would be lost', () {
    expect(
      const EventStreamRetryAdapter().supports(const Stream<int>.empty()),
      isFalse,
    );
    expect(
      const EventStreamRetryAdapter().supports(EventStream<int>.empty()),
      isTrue,
    );
  });
}
