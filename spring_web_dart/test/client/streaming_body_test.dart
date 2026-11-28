// StreamingBody on its own: a stream is sent once (also when wrapped
// again), a repeatable source opens again, its length is checked, and an
// observed body counts what goes out without changing what it can do.
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  Stream<List<int>> chunks() => Stream.fromIterable([
    [1, 2],
    [3],
  ]);

  test('a stream: listened once, then NonRepeatableBodyException', () async {
    final body = StreamingBody(chunks(), length: 3);
    expect(body.isRepeatable, isFalse);
    expect(body.isConsumed, isFalse);
    // Opening is not reading.
    body.open();
    expect(body.isConsumed, isFalse);
    expect(await body.toBytes(), [1, 2, 3]);
    expect(body.isConsumed, isTrue);
    expect(body.open, throwsA(isA<NonRepeatableBodyException>()));
    expect(
      NonRetryableException.isNonRetryable(NonRepeatableBodyException('x')),
      isTrue,
    );
  });

  test('the same stream in a new body is known as sent', () async {
    final stream = chunks();
    await StreamingBody(stream).toBytes();
    final again = StreamingBody(stream);
    expect(again.isConsumed, isTrue);
    expect(again.open, throwsA(isA<NonRepeatableBodyException>()));
  });

  test('two opens before a listen: the second listen errors', () async {
    final body = StreamingBody(chunks());
    final first = body.open();
    final second = body.open();
    expect(await first.expand((c) => c).toList(), [1, 2, 3]);
    await expectLater(
      second.toList(),
      throwsA(isA<NonRepeatableBodyException>()),
    );
  });

  test('a repeatable body opens its source each time', () async {
    var opened = 0;
    final body = StreamingBody.repeatable(() {
      opened++;
      return chunks();
    }, length: 3);
    expect(body.isRepeatable, isTrue);
    expect(await body.toBytes(), [1, 2, 3]);
    expect(await body.toBytes(), [1, 2, 3]);
    expect(opened, 2);
    expect(body.isConsumed, isFalse);
  });

  test('a length that is wrong or negative', () async {
    await expectLater(
      StreamingBody(chunks(), length: 4).toBytes(),
      throwsStateError,
    );
    expect(() => StreamingBody(chunks(), length: -1), throwsArgumentError);
    expect(
      () => StreamingBody.repeatable(chunks, length: -1),
      throwsArgumentError,
    );
    expect(
      () => StreamingBody(StreamController<List<int>>.broadcast().stream),
      throwsArgumentError,
    );
  });

  test('observed: counts what goes out, keeps the length and what it can '
      'do', () async {
    final seen = <int>[];
    final once = StreamingBody(chunks(), length: 3);
    final watched = once.observed((chunk) => seen.add(chunk.length));
    expect(watched.length, 3);
    expect(watched.isRepeatable, isFalse);
    // The source is opened only when the observed body is read.
    expect(once.isConsumed, isFalse);
    expect(await watched.toBytes(), [1, 2, 3]);
    expect(seen, [2, 1]);
    expect(once.isConsumed, isTrue);
    expect(watched.isConsumed, isTrue);
    // A body observed after it was sent knows it before connecting.
    expect(
      once.observed((_) {}).open,
      throwsA(isA<NonRepeatableBodyException>()),
    );

    final repeatable = StreamingBody.repeatable(chunks).observed(
      (chunk) => seen.add(chunk.length),
    );
    expect(repeatable.isRepeatable, isTrue);
    await repeatable.toBytes();
    await repeatable.toBytes();
    expect(seen, [2, 1, 2, 1, 2, 1]);
  });

  test('an HttpRequest has one kind of body', () {
    final url = Uri.parse('http://h/');
    expect(
      () => HttpRequest(
        method: HttpMethod.post,
        url: url,
        body: const [1],
        streamingBody: StreamingBody(chunks()),
      ),
      throwsArgumentError,
    );
    final streamed = HttpRequest(
      method: HttpMethod.post,
      url: url,
      streamingBody: StreamingBody(chunks()),
      timeout: const Duration(seconds: 1),
    );
    expect(streamed.hasBody, isTrue);
    final copy = streamed.withHeaders(HttpHeaders({'X': '1'}));
    expect(copy.streamingBody, same(streamed.streamingBody));
    final bytes = streamed.withBody(body: const [1]);
    expect(bytes.streamingBody, isNull);
    expect(bytes.body, [1]);
    expect(bytes.timeout, const Duration(seconds: 1));
    expect(streamed.withBody().hasBody, isFalse);
  });
}
