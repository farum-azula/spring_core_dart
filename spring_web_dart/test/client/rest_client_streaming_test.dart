// RestClient with a streamed body: body(stream), body(StreamingBody), a
// MultipartBody with a streamed part through the converters; read whole
// for interceptors that get bytes (as Spring's), passed through those that
// stream; a body read once sent once under RetryTemplate and @Retryable.
// The hand-written proxy uses `this.` like generated code does.
// ignore_for_file: unnecessary_this
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

void main() {
  late MockHttpTransport server;
  // What reached the transport: the kind of body and its bytes.
  late List<String> sent;

  setUp(() {
    server = MockHttpTransport();
    sent = [];
    server.when(HttpMethod.post, '/upload').respondWith((request) async {
      final streaming = request.streamingBody;
      final bytes = streaming == null
          ? request.body ?? const <int>[]
          : await streaming.toBytes();
      sent.add(
        '${streaming == null ? 'bytes' : 'stream'} ${bytes.length} '
        '${streaming?.length ?? '-'} ${request.headers.contentType}',
      );
      return HttpResponse(200, body: utf8.encode('${bytes.length}'));
    });
  });

  RestClientBuilder builder() =>
      RestClient.builder().baseUrl('https://api.neon.books').transport(server);

  Stream<List<int>> chunks(int count, {int size = 1000}) async* {
    for (var i = 0; i < count; i++) {
      yield List.filled(size, i);
    }
  }

  group('through the converters', () {
    test('body(stream): sent as a stream, octet-stream by default', () async {
      final rest = builder().build();
      final answer = await rest
          .post()
          .uri('/upload')
          .body(chunks(3))
          .retrieve()
          .body<String>();
      expect(answer, '3000');
      expect(sent, ['stream 3000 - application/octet-stream']);
    });

    test('body(StreamingBody): its length and the declared type', () async {
      final rest = builder().build();
      await rest
          .post()
          .uri('/upload')
          .contentType('text/csv')
          .body(StreamingBody(chunks(2), length: 2000))
          .retrieve()
          .toBodilessEntity();
      expect(sent, ['stream 2000 2000 text/csv']);
    });

    test('a MultipartBody with a streamed part: a stream of the exact '
        'length', () async {
      final rest = builder().build();
      final body = MultipartBody([
        MultipartBodyPart.field('title', 'Dune'),
        MultipartBodyPart.stream('scan', chunks(5), length: 5000),
      ], boundary: 'b1');
      await rest.post().uri('/upload').body(body).retrieve().toBodilessEntity();
      final length = body.contentLength;
      expect(sent, ['stream $length $length multipart/form-data; boundary=b1']);
    });

    test('one with its parts in memory: bytes, as before', () async {
      final rest = builder().build();
      final body = MultipartBody([
        MultipartBodyPart.field('title', 'Dune'),
      ], boundary: 'b2');
      await rest.post().uri('/upload').body(body).retrieve().toBodilessEntity();
      expect(sent, [
        'bytes ${body.encode().length} - multipart/form-data; boundary=b2',
      ]);
    });

    test('an uploaded MultipartFile passed on without its bytes', () async {
      final rest = builder().build();
      final file = InMemoryMultipartFile(
        'cover',
        Uint8List(4096),
        originalFilename: 'dune.png',
      );
      await rest
          .post()
          .uri('/upload')
          .body(
            MultipartBody([
              MultipartBodyPart.multipartFile('cover', file),
            ], boundary: 'b3'),
          )
          .retrieve()
          .toBodilessEntity();
      expect(sent.single, startsWith('stream '));
    });
  });

  group('interceptors', () {
    test('one that gets bytes: the stream is read whole first, as in '
        'Spring', () async {
      final seen = <String>[];
      final rest = builder()
          .requestInterceptor(
            ClientHttpRequestInterceptor.of((request, body, execution) {
              seen.add('${body?.length} ${request.streamingBody}');
              return execution.execute(request, body);
            }),
          )
          .build();
      await rest
          .post()
          .uri('/upload')
          .body(chunks(3))
          .retrieve()
          .toBodilessEntity();
      expect(seen, ['3000 null']);
      expect(sent, ['bytes 3000 - application/octet-stream']);
    });

    test('only streaming ones: the stream passes them unread', () async {
      final seen = <String>[];
      final rest = builder()
          .requestInterceptor(
            StreamingClientHttpRequestInterceptor.of((
              request,
              body,
              execution,
            ) {
              request.headers.set('X-Trace', '1');
              seen.add('${body?.length} ${request.streamingBody?.isConsumed}');
              return execution.execute(request, body);
            }),
          )
          .requestInterceptor(
            StreamingClientHttpRequestInterceptor.of(
              (request, body, execution) => execution.execute(request, body),
            ),
          )
          .build();
      await rest
          .post()
          .uri('/upload')
          .body(chunks(3))
          .retrieve()
          .toBodilessEntity();
      expect(seen, ['null false']);
      expect(sent, ['stream 3000 - application/octet-stream']);
      expect(server.lastRequest.headers['X-Trace'], '1');
    });

    test('a streaming one with one that is not: read whole', () async {
      final rest = builder()
          .requestInterceptor(
            StreamingClientHttpRequestInterceptor.of(
              (request, body, execution) => execution.execute(request, body),
            ),
          )
          .requestInterceptor(
            ClientHttpRequestInterceptor.of(
              (request, body, execution) => execution.execute(request, body),
            ),
          )
          .build();
      await rest
          .post()
          .uri('/upload')
          .body(chunks(2))
          .retrieve()
          .toBodilessEntity();
      expect(sent, ['bytes 2000 - application/octet-stream']);
    });

    test('a streaming one that sends again: a stream read once fails, a '
        'repeatable one is opened again', () async {
      final twice = builder()
          .requestInterceptor(
            StreamingClientHttpRequestInterceptor.of((
              request,
              body,
              execution,
            ) async {
              await execution.execute(request, body);
              return await execution.execute(request, body);
            }),
          )
          .build();
      await expectLater(
        twice
            .post()
            .uri('/upload')
            .body(chunks(2))
            .retrieve()
            .toBodilessEntity(),
        throwsA(isA<NonRepeatableBodyException>()),
      );
      expect(sent, hasLength(1));
      await twice
          .post()
          .uri('/upload')
          .body(StreamingBody.repeatable(() => chunks(2), length: 2000))
          .retrieve()
          .toBodilessEntity();
      expect(sent, hasLength(3));
    });
  });

  group('retries', () {
    final template = RetryTemplate(
      retryPolicy: RetryPolicy.builder()
          .maxRetries(3)
          .delay(Duration.zero)
          .include<ResourceAccessException>()
          .build(),
    );

    // A client whose first call fails without an answer, the next ones
    // answer with the size of the body they read.
    (MockHttpTransport, RestClient) flaky() {
      final server = MockHttpTransport()
        ..when(HttpMethod.post, '/flaky').fail(HttpTransportException('down'))
        ..when(HttpMethod.post, '/flaky').respondWith((request) async {
          final bytes = await request.streamingBody!.toBytes();
          return HttpResponse(200, body: utf8.encode('${bytes.length}'));
        });
      return (server, RestClient.builder().transport(server).build());
    }

    Future<String> upload(RestClient rest, Object body) =>
        rest.post().uri('/flaky').body(body).retrieve().body<String>();

    test('the same stream again: NonRepeatableBodyException, not '
        'retried', () async {
      final (server, rest) = flaky();
      final stream = chunks(3);
      Object? failure;
      try {
        await template.invoke(() => upload(rest, stream));
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isA<NonRepeatableBodyException>());
      expect(server.requests, hasLength(2));
    });

    test('a MultipartBody whose streamed part was sent: fails before '
        'anything goes out', () async {
      final (server, rest) = flaky();
      final body = MultipartBody([
        MultipartBodyPart.stream('scan', chunks(3), length: 3000),
      ]);
      await expectLater(
        template.execute(() => upload(rest, body)),
        throwsA(
          isA<RetryException>().having(
            (e) => e.cause,
            'cause',
            isA<NonRepeatableBodyException>(),
          ),
        ),
      );
      // The second attempt never reached the transport.
      expect(server.requests, hasLength(1));
    });

    test('a repeatable body: the second attempt sends it whole', () async {
      final (server, rest) = flaky();
      final answer = await template.invoke(
        () => upload(
          rest,
          StreamingBody.repeatable(() => chunks(3), length: 3000),
        ),
      );
      expect(answer, '3000');
      expect(server.requests, hasLength(2));
    });

    test('@Retryable: the same stream fails clearly', () async {
      final (server, rest) = flaky();
      final uploads = _proxied(_Uploads(rest));
      await expectLater(
        uploads.send(chunks(3)),
        throwsA(isA<NonRepeatableBodyException>()),
      );
      expect(server.requests, hasLength(2));
    });

    test('@Retryable: a source opened again is sent whole', () async {
      final (server, rest) = flaky();
      final uploads = _proxied(_Uploads(rest));
      expect(await uploads.sendRepeatable(() => chunks(3)), '3000');
      expect(server.requests, hasLength(2));
    });
  });
}

/// A bean whose uploads are retried with `@Retryable`.
class _Uploads {
  _Uploads(this.rest);

  final RestClient rest;

  @Retryable(includes: [ResourceAccessException], delay: Duration.zero)
  Future<String> send(Stream<List<int>> data) =>
      rest.post().uri('/flaky').body(data).retrieve().body<String>();

  @Retryable(includes: [ResourceAccessException], delay: Duration.zero)
  Future<String> sendRepeatable(Stream<List<int>> Function() open) => rest
      .post()
      .uri('/flaky')
      .body(StreamingBody.repeatable(open))
      .retrieve()
      .body<String>();
}

const _target = AopTarget('_Uploads', types: ['_Uploads']);

const _retried = Retryable(
  includes: [ResourceAccessException],
  delay: Duration.zero,
);

const _signatures = [
  MethodSignature.of(
    'send',
    _target,
    returnType: 'Future',
    parameterTypes: ['Stream'],
    parameterNames: ['data'],
    annotations: [_retried],
    annotationTypes: ['Retryable'],
  ),
  MethodSignature.of(
    'sendRepeatable',
    _target,
    returnType: 'Future',
    parameterTypes: ['Function'],
    parameterNames: ['open'],
    annotations: [_retried],
    annotationTypes: ['Retryable'],
  ),
];

// The proxy as the generator writes it.
class _$UploadsProxy implements _Uploads {
  _$UploadsProxy(this._target, this._invoker);

  final _Uploads _target;
  final ProxyInvoker _invoker;

  @override
  RestClient get rest => _target.rest;

  @override
  Future<String> send(Stream<List<int>> data) =>
      this._invoker.invokeAsync<String>(
        proxy: this,
        target: this._target,
        methodIndex: 0,
        arguments: [data],
        original: (args) => this._target.send(args[0]! as Stream<List<int>>),
      );

  @override
  Future<String> sendRepeatable(Stream<List<int>> Function() open) =>
      this._invoker.invokeAsync<String>(
        proxy: this,
        target: this._target,
        methodIndex: 1,
        arguments: [open],
        original: (args) => this._target.sendRepeatable(
          args[0]! as Stream<List<int>> Function(),
        ),
      );
}

_Uploads _proxied(_Uploads uploads) {
  final factory =
      ProxyFactory(
        uploads,
        AopProxyFactory(
          signatures: _signatures,
          create: (target, invoker) =>
              _$UploadsProxy(target as _Uploads, invoker),
        ),
        beanName: 'uploads',
      )..addAdvisor(
        DefaultPointcutAdvisor(
          const RetryablePointcut(),
          RetryInterceptor(
            introspector: Introspector()
              ..registerTypeTests({
                ResourceAccessException: (value) =>
                    value is ResourceAccessException,
              }),
          ),
          order: AdvisorOrder.retry,
        ),
      );
  return factory.getProxy() as _Uploads;
}
