// IoHttpTransport sends a StreamingBody as it is read: Content-Length when
// its length is known, chunked otherwise, never gathered first; a body read
// once is sent once, on a redirect and on a retry.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  late io.HttpServer server;
  late Uri base;
  final transport = IoHttpTransport();
  // What the server got, per request: path, headers, body.
  final received =
      <
        ({String path, String method, io.HttpHeaders headers, List<int> body})
      >[];
  // Completed when the server has read the first chunk of /slow.
  var firstChunk = Completer<void>();
  var flaky = 0;

  setUpAll(() async {
    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((request) async {
      final response = request.response;
      final path = request.uri.path;
      if (path == '/parts') {
        final boundary = MultipartParser.boundaryOf(
          MediaType.parse(request.headers.value('content-type')!),
        )!;
        final parts = <Map<String, Object?>>[];
        var size = 0;
        final counted = request.map((chunk) {
          size += chunk.length;
          return chunk;
        });
        await for (final part in MultipartParser(boundary).bind(counted)) {
          final content = await part.content.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          parts.add({
            'name': part.name,
            'filename': part.filename,
            'type': part.headers.contentType,
            'size': content.length,
            'text': part.isFile
                ? null
                : utf8.decode(content, allowMalformed: true),
            'sum': content.fold<int>(0, (sum, byte) => (sum + byte) % 65521),
          });
        }
        response
          ..headers.set('X-Length', request.headers.contentLength)
          ..headers.set('X-Read', size)
          ..headers.set(
            'X-Chunked',
            request.headers.chunkedTransferEncoding.toString(),
          )
          ..write(jsonEncode(parts));
        await response.close();
        return;
      }
      final body = <int>[];
      try {
        await for (final chunk in request) {
          body.addAll(chunk);
          if (path == '/slow' && !firstChunk.isCompleted) {
            firstChunk.complete();
          }
        }
      } on io.HttpException {
        // A client that gave its request up (a body shorter than its
        // length): nothing to answer.
        return;
      }
      received.add((
        path: path,
        method: request.method,
        headers: request.headers,
        body: body,
      ));
      switch (path) {
        case '/temporary':
          response
            ..statusCode = 307
            ..headers.set('Location', '/echo');
        case '/found':
          response
            ..statusCode = 302
            ..headers.set('Location', '/echo');
        case '/other':
          response
            ..statusCode = 303
            ..headers.set('Location', '/echo');
        case '/flaky' when flaky++ == 0:
          // The body was read, the answer never comes.
          final socket = await response.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        default:
          response
            ..headers.set('X-Length', request.headers.contentLength)
            ..headers.set(
              'X-Chunked',
              request.headers.chunkedTransferEncoding.toString(),
            )
            ..write('${body.length}');
      }
      await response.close();
    });
  });

  tearDownAll(() async {
    transport.close();
    await server.close(force: true);
  });

  setUp(() {
    received.clear();
    firstChunk = Completer<void>();
    flaky = 0;
  });

  Uint8List bytes(int length) =>
      Uint8List.fromList(List.generate(length, (i) => i % 251));

  // [length] bytes in chunks of [chunk], as a file is read.
  Stream<List<int>> chunks(int length, {int chunk = 64 * 1024}) async* {
    for (var start = 0; start < length; start += chunk) {
      yield bytes(chunk)
          .sublist(0, start + chunk > length ? length - start : chunk);
    }
  }

  HttpRequest post(String path, StreamingBody body, {HttpMethod? method}) =>
      HttpRequest(
        method: method ?? HttpMethod.post,
        url: base.resolve(path),
        streamingBody: body,
      );

  group('the length', () {
    test('known: sent as Content-Length', () async {
      final response = await transport.send(
        post('/echo', StreamingBody(chunks(300000), length: 300000)),
      );
      expect(response.bodyText, '300000');
      expect(response.headers['X-Length'], '300000');
      expect(response.headers['X-Chunked'], 'false');
    });

    test('unknown: sent in chunks', () async {
      final response = await transport.send(
        post('/echo', StreamingBody(chunks(300000))),
      );
      expect(response.bodyText, '300000');
      expect(response.headers['X-Length'], '-1');
      expect(response.headers['X-Chunked'], 'true');
    });

    test('wrong: the request fails instead of sending another body', () {
      expect(
        transport.send(post('/echo', StreamingBody(chunks(10), length: 20))),
        throwsA(isA<HttpTransportException>()),
      );
    });

    test('through stream() as well', () async {
      final response = await transport.stream(
        post('/echo', StreamingBody(chunks(1000), length: 1000)),
      );
      expect(await utf8.decodeStream(response.body), '1000');
    });
  });

  test('the server reads the first chunk before the last is made', () async {
    final source = StreamController<List<int>>();
    final sent = transport.send(post('/slow', StreamingBody(source.stream)));
    source.add(bytes(1000));
    // A transport that gathered the body first would never send this one.
    await firstChunk.future.timeout(const Duration(seconds: 5));
    source.add(bytes(500));
    await source.close();
    expect((await sent).bodyText, '1500');
  });

  test('a stream is listened to only when it is written', () async {
    var listened = false;
    final body = StreamingBody(
      Stream.fromFuture(Future.value(<int>[1, 2, 3])).map((chunk) {
        listened = true;
        return chunk;
      }),
    );
    final denied = IoHttpTransport(
      allowedAddresses: AllowedAddresses(['api.neon.books']),
    );
    addTearDown(denied.close);
    await expectLater(
      denied.send(post('/echo', body)),
      throwsA(isA<FilteredHostException>()),
    );
    expect(listened, isFalse);
    expect(body.isConsumed, isFalse);
    // Not read, so it can still be sent.
    expect((await transport.send(post('/echo', body))).bodyText, '3');
    expect(body.isConsumed, isTrue);
  });

  group('sent once', () {
    test('a body read once is not sent again', () async {
      final body = StreamingBody(chunks(1000));
      expect((await transport.send(post('/echo', body))).bodyText, '1000');
      await expectLater(
        transport.send(post('/echo', body)),
        throwsA(isA<NonRepeatableBodyException>()),
      );
      expect(received, hasLength(1));
    });

    test('nor the same stream in a new body', () async {
      final stream = chunks(1000);
      await transport.send(post('/echo', StreamingBody(stream)));
      await expectLater(
        transport.send(post('/echo', StreamingBody(stream))),
        throwsA(isA<NonRepeatableBodyException>()),
      );
      expect(received, hasLength(1));
    });

    test('a repeatable body is opened again', () async {
      var opened = 0;
      final body = StreamingBody.repeatable(() {
        opened++;
        return chunks(1000);
      }, length: 1000);
      expect((await transport.send(post('/echo', body))).bodyText, '1000');
      expect((await transport.send(post('/echo', body))).bodyText, '1000');
      expect(opened, 2);
    });

    test('a broadcast stream is refused', () {
      expect(
        () => StreamingBody(StreamController<List<int>>.broadcast().stream),
        throwsArgumentError,
      );
    });
  });

  group('redirects', () {
    test('a 307 to a POST is the answer, the body sent once', () async {
      final response = await transport.send(
        post('/temporary', StreamingBody(chunks(1000))),
      );
      expect(response.statusCode, 307);
      expect([for (final r in received) r.path], ['/temporary']);
      expect(received.single.body, hasLength(1000));
    });

    test('a 303 is followed as a GET without the body', () async {
      final response = await transport.send(
        post('/other', StreamingBody(chunks(1000))),
      );
      expect(response.statusCode, 200);
      expect(
        [for (final r in received) '${r.method} ${r.path} ${r.body.length}'],
        ['POST /other 1000', 'GET /echo 0'],
      );
    });

    test('a hop that keeps the body: not followed with a stream read once '
        '(Apache HttpClient)', () async {
      final response = await transport.send(
        post('/found', StreamingBody(chunks(1000)), method: HttpMethod.get),
      );
      expect(response.statusCode, 302);
      expect(received, hasLength(1));
    });

    test('followed with a repeatable one, opened again', () async {
      final response = await transport.send(
        post(
          '/found',
          StreamingBody.repeatable(() => chunks(1000), length: 1000),
          method: HttpMethod.get,
        ),
      );
      expect(response.statusCode, 200);
      expect(
        [for (final r in received) '${r.method} ${r.path} ${r.body.length}'],
        ['GET /found 1000', 'GET /echo 1000'],
      );
    });
  });

  group('retries', () {
    final template = RetryTemplate(
      retryPolicy: RetryPolicy.builder()
          .maxRetries(3)
          .delay(Duration.zero)
          .build(),
    );

    test('of a body read once: the second attempt fails, nothing is sent '
        'again', () async {
      final body = StreamingBody(chunks(5000));
      Object? failure;
      try {
        await template.invoke(() => transport.send(post('/flaky', body)));
      } on Object catch (error) {
        failure = error;
      }
      expect(failure, isA<NonRepeatableBodyException>());
      expect(received, hasLength(1));
      expect(received.single.body, hasLength(5000));
    });

    test('RetryTemplate.execute names the cause', () async {
      final body = StreamingBody(chunks(5000));
      await expectLater(
        template.execute(() => transport.send(post('/flaky', body))),
        throwsA(
          isA<RetryException>().having(
            (e) => e.cause,
            'cause',
            isA<NonRepeatableBodyException>(),
          ),
        ),
      );
    });

    test('of a repeatable body: the second attempt sends it whole', () async {
      final body = StreamingBody.repeatable(() => chunks(5000), length: 5000);
      final response = await template.invoke(
        () => transport.send(post('/flaky', body)),
      );
      expect(response.bodyText, '5000');
      expect([for (final r in received) r.body.length], [5000, 5000]);
    });
  });

  group('multipart', () {
    Future<(HttpResponse, List<Object?>)> upload(MultipartBody body) async {
      final streaming = body.toStreamingBody();
      final response = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: base.resolve('/parts'),
          headers: HttpHeaders({
            HttpHeaders.contentTypeHeader: body.contentType,
          }),
          streamingBody: streaming,
        ),
      );
      return (response, jsonDecode(response.bodyText) as List<Object?>);
    }

    int sum(List<int> content) =>
        content.fold<int>(0, (sum, byte) => (sum + byte) % 65521);

    test('streamed parts with lengths: an exact Content-Length, parsed by '
        'the server', () async {
      final body = MultipartBody([
        MultipartBodyPart.field('title', 'Dune'),
        MultipartBodyPart.stream(
          'scan',
          chunks(200000),
          length: 200000,
          filename: 'scan.pdf',
        ),
        MultipartBodyPart.file('cover', bytes(3000), filename: 'dune.png'),
      ]);
      expect(body.isStreamed, isTrue);
      final (response, parts) = await upload(body);
      expect(response.headers['X-Length'], '${body.contentLength}');
      expect(response.headers['X-Read'], '${body.contentLength}');
      expect(response.headers['X-Chunked'], 'false');
      expect(parts, [
        {
          'name': 'title',
          'filename': null,
          'type': null,
          'size': 4,
          'text': 'Dune',
          'sum': sum(utf8.encode('Dune')),
        },
        {
          'name': 'scan',
          'filename': 'scan.pdf',
          'type': 'application/pdf',
          'size': 200000,
          'text': null,
          'sum': sum(await chunks(200000).expand((c) => c).toList()),
        },
        {
          'name': 'cover',
          'filename': 'dune.png',
          'type': 'image/png',
          'size': 3000,
          'text': null,
          'sum': sum(bytes(3000)),
        },
      ]);
    });

    test('a part of unknown length: in chunks', () async {
      final body = MultipartBody([
        MultipartBodyPart.stream('scan', chunks(100000), filename: 'a.bin'),
      ]);
      expect(body.contentLength, isNull);
      final (response, parts) = await upload(body);
      expect(response.headers['X-Chunked'], 'true');
      expect((parts.single! as Map<String, Object?>)['size'], 100000);
    });

    test('a file on disk, read while sent and opened again', () async {
      final directory = io.Directory.systemTemp.createTempSync('spring_part_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = io.File('${directory.path}/notes.txt')
        ..writeAsBytesSync(bytes(70000));
      final body = MultipartBody([
        MultipartBodyPart.fromPath('notes', file.path),
      ]);
      expect(body.contentLength, isNotNull);
      for (var attempt = 0; attempt < 2; attempt++) {
        final (response, parts) = await upload(body);
        expect(response.headers['X-Length'], '${body.contentLength}');
        expect(parts, [
          {
            'name': 'notes',
            'filename': 'notes.txt',
            'type': 'text/plain',
            'size': 70000,
            'text': null,
            'sum': sum(bytes(70000)),
          },
        ]);
      }
      expect(
        () => MultipartBodyPart.fromPath('x', '${directory.path}/missing'),
        throwsA(isA<io.FileSystemException>()),
      );
    });

    test('an uploaded MultipartFile passed on through openRead', () async {
      final file = InMemoryMultipartFile(
        'cover',
        bytes(4000),
        originalFilename: 'dune.png',
        contentType: 'image/png',
      );
      final body = MultipartBody([
        MultipartBodyPart.multipartFile('cover', file),
      ]);
      expect(body.toStreamingBody().isRepeatable, isTrue);
      final (_, parts) = await upload(body);
      expect(parts, [
        {
          'name': 'cover',
          'filename': 'dune.png',
          'type': 'image/png',
          'size': 4000,
          'text': null,
          'sum': sum(bytes(4000)),
        },
      ]);
    });

    test('a part read once: the body is sent once', () async {
      final body = MultipartBody([
        MultipartBodyPart.field('title', 'Dune'),
        MultipartBodyPart.stream('scan', chunks(1000), length: 1000),
      ]);
      await upload(body);
      expect(body.toStreamingBody, throwsA(isA<NonRepeatableBodyException>()));
    });

    test('the same bytes as encode() for parts in memory', () async {
      final parts = [
        MultipartBodyPart.field('title', 'Dune'),
        MultipartBodyPart.file('cover', bytes(3000), filename: 'dune.png'),
        MultipartBodyPart.json('meta', '{"pages":412}'),
      ];
      final body = MultipartBody(parts, boundary: 'fixed');
      final streamed = await body.toStreamingBody().toBytes();
      expect(streamed, body.encode());
      expect(body.contentLength, streamed.length);
      final withStream = MultipartBody([
        ...parts,
        MultipartBodyPart.stream('x', Stream.value([1])),
      ]);
      expect(withStream.encode, throwsStateError);
      expect(() => withStream.parts.last.body, throwsStateError);
    });
  });

  test('RestClient: body(stream) and a streamed MultipartBody, on to the '
      'server', () async {
    final rest = RestClient.builder()
        .baseUrl(base.toString())
        .transport(transport)
        .build();
    expect(
      await rest
          .post()
          .uri('/echo')
          .body(chunks(150000))
          .retrieve()
          .body<String>(),
      '150000',
    );
    final directory = io.Directory.systemTemp.createTempSync('spring_rest_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = io.File('${directory.path}/scan.pdf')
      ..writeAsBytesSync(bytes(90000));
    final body = MultipartBody([
      MultipartBodyPart.field('title', 'Dune'),
      MultipartBodyPart.fromPath('scan', file.path),
    ]);
    final response = await rest
        .post()
        .uri('/parts')
        .body(body)
        .retrieve()
        .toEntity<String>();
    expect(response.headers['X-Length'], '${body.contentLength}');
    final parts = jsonDecode(response.body!) as List<Object?>;
    expect(
      [for (final part in parts.cast<Map<String, Object?>>()) part['size']],
      [4, 90000],
    );
  });
}
