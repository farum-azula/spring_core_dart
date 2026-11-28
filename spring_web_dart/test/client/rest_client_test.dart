import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

const _json = MapType<String, Object?>(ClassType<String>(), DynamicType());

void main() {
  late MockHttpTransport server;
  late RestClient rest;

  setUp(() {
    server = MockHttpTransport();
    rest = RestClient.builder()
        .baseUrl('https://api.neon.books/v1')
        .transport(server)
        .build();
  });

  group('URIs', () {
    test(
      'a template relative to the base URL, values by list or map',
      () async {
        server.when(HttpMethod.get, '/v1/books/1').respond(200, json: {'a': 1});
        server.when(HttpMethod.get, '/v1/books/2').respond(200, json: {'a': 2});
        expect(
          await rest.get().uri('/books/{isbn}', ['1']).retrieve().body(_json),
          {'a': 1},
        );
        expect(
          await rest
              .get()
              .uri('books/{isbn}', {'isbn': 2})
              .retrieve()
              .body(_json),
          {'a': 2},
        );
        expect(server.requests.map((r) => '${r.url}'), [
          'https://api.neon.books/v1/books/1',
          'https://api.neon.books/v1/books/2',
        ]);
      },
    );

    test('a whole URL ignores the base; a Uri; a UriBuilder', () async {
      server
        ..when(HttpMethod.get, 'https://other.test/x').respond(204)
        ..when(HttpMethod.get, '/v1/search').respond(204);
      await rest
          .get()
          .uri('https://other.test/x')
          .retrieve()
          .toBodilessEntity();
      await rest
          .get()
          .uri(Uri.parse('/search?q=a%20b'))
          .retrieve()
          .toBodilessEntity();
      await rest
          .get()
          .uri(
            (UriBuilder b) =>
                b.path('/search').queryParam('q', 'Le Guin').build(),
          )
          .retrieve()
          .toBodilessEntity();
      expect(server.requests.map((r) => '${r.url}'), [
        'https://other.test/x',
        'https://api.neon.books/v1/search?q=a%20b',
        'https://api.neon.books/v1/search?q=Le%20Guin',
      ]);
    });

    test('default URI variables, a templated base URL', () async {
      final tenant = RestClient.builder()
          .baseUrl('https://{tenant}.neon.books')
          .defaultUriVariables({'tenant': 'eu'})
          .transport(server)
          .build();
      server.when(HttpMethod.get, 'https://eu.neon.books/b/1').respond(204);
      await tenant
          .get()
          .uri('/b/{id}', {'id': 1})
          .retrieve()
          .toBodilessEntity();
      expect('${server.lastRequest.url}', 'https://eu.neon.books/b/1');
    });

    test('misuse: a variable count that does not match, a dot segment', () {
      expect(() => rest.get().uri('/b/{a}/{b}', ['x']), throwsArgumentError);
      expect(() => rest.get().uri('/b/{a}', ['x', 'y']), throwsArgumentError);
      expect(() => rest.get().uri('/b/{a}', {'b': 1}), throwsArgumentError);
      expect(() => rest.get().uri('/b/{a}', '..'), throwsArgumentError);
      expect(() => rest.get().uri(42), throwsArgumentError);
    });
  });

  group('bodies', () {
    test('JSON through the ObjectMapper, Content-Type set', () async {
      server
          .when(HttpMethod.post, '/v1/books')
          .respondWith(
            (request) => HttpResponse(
              201,
              headers: HttpHeaders({'Content-Type': 'application/json'}),
              body: request.body!,
            ),
          );
      final echoed = await rest
          .post()
          .uri('/books')
          .body({
            'isbn': '1',
            'tags': ['sf'],
          })
          .retrieve()
          .body(_json);
      expect(echoed, {
        'isbn': '1',
        'tags': ['sf'],
      });
      expect(server.lastRequest.headers.contentType, MediaType.applicationJson);
    });

    test('bytes and text as they are, a declared type kept', () async {
      server.when(HttpMethod.put, '/v1/raw').respond(204);
      await rest
          .put()
          .uri('/raw')
          .body(Uint8List.fromList([1, 2]))
          .retrieve()
          .toBodilessEntity();
      expect(server.lastRequest.body, [1, 2]);
      expect(
        server.lastRequest.headers.contentType,
        MediaType.applicationOctetStream,
      );
      await rest
          .put()
          .uri('/raw')
          .contentType(MediaType.applicationJson)
          .body('{"a":1}')
          .retrieve()
          .toBodilessEntity();
      expect(utf8.decode(server.lastRequest.body!), '{"a":1}');
      expect(server.lastRequest.headers.contentType, MediaType.applicationJson);
      await rest.put().uri('/raw').body('plain').retrieve().toBodilessEntity();
      expect(
        server.lastRequest.headers.contentType,
        'text/plain; charset=utf-8',
      );
    });

    test('a form, a multipart body', () async {
      server.when(HttpMethod.post, '/v1/form').respond(204);
      await rest
          .post()
          .uri('/form')
          .contentType(MediaType.applicationFormUrlencoded)
          .body({
            'q': 'a b&c',
            'tag': ['x', 'y'],
            'none': null,
          })
          .retrieve()
          .toBodilessEntity();
      expect(utf8.decode(server.lastRequest.body!), 'q=a+b%26c&tag=x&tag=y');
      final multipart = MultipartBody([
        MultipartBodyPart.field('title', 'Dune'),
      ], boundary: 'b0');
      await rest
          .post()
          .uri('/form')
          .body(multipart)
          .retrieve()
          .toBodilessEntity();
      expect(
        server.lastRequest.headers.contentType,
        'multipart/form-data; boundary=b0',
      );
      expect(utf8.decode(server.lastRequest.body!), contains('name="title"'));
    });

    test('reading: String, bytes, a list, an empty body', () async {
      server
        ..when(HttpMethod.get, '/v1/text').respond(200, body: 'hello')
        ..when(HttpMethod.get, '/v1/list').respond(200, json: [1, 2])
        ..when(HttpMethod.get, '/v1/empty').respond(204);
      expect(await rest.get().uri('/text').retrieve().body<String>(), 'hello');
      expect(
        await rest.get().uri('/text').retrieve().body<Uint8List>(),
        utf8.encode('hello'),
      );
      expect(
        await rest
            .get()
            .uri('/list')
            .retrieve()
            .body(const ListType<int>(ClassType<int>())),
        [1, 2],
      );
      expect(await rest.get().uri('/empty').retrieve().body<String?>(), isNull);
      await expectLater(
        rest.get().uri('/empty').retrieve().body<String>(),
        throwsA(isA<RestClientException>()),
      );
    });

    test('a body no converter reads fails clearly', () async {
      server
          .when(HttpMethod.get, '/v1/page')
          .respond(
            200,
            body: '<html></html>',
            headers: {'Content-Type': 'text/html'},
          );
      await expectLater(
        rest.get().uri('/page').retrieve().body(_json),
        throwsA(
          isA<RestClientException>().having(
            (e) => e.message,
            'message',
            contains('No HttpMessageConverter'),
          ),
        ),
      );
    });

    test('misuse: no body on GET or HEAD', () {
      expect(rest.get(), isNot(isA<RequestBodySpec>()));
      expect(rest.delete(), isNot(isA<RequestBodySpec>()));
      expect(
        () => rest.method(HttpMethod.get).uri('/x').body('x'),
        throwsArgumentError,
      );
      expect(
        () => rest.method(HttpMethod.head).uri('/x').body({'a': 1}),
        throwsArgumentError,
      );
    });

    test('toEntity and toBodilessEntity', () async {
      server
          .when(HttpMethod.post, '/v1/books')
          .respond(
            201,
            json: {'isbn': '1'},
            headers: {'Location': '/v1/books/1'},
          );
      final entity = await rest
          .post()
          .uri('/books')
          .body({'isbn': '1'})
          .retrieve()
          .toEntity(_json);
      expect(entity.statusCode, 201);
      expect(entity.body, {'isbn': '1'});
      expect(entity.headers.location, Uri.parse('/v1/books/1'));
      final bodiless = await rest
          .post()
          .uri('/books')
          .retrieve()
          .toBodilessEntity();
      expect(bodiless.statusCode, HttpStatus.created);
      expect(bodiless.hasBody, isFalse);
    });
  });

  group('errors', () {
    test('4xx, 5xx and their bodies', () async {
      server
        ..when(HttpMethod.get, '/v1/missing').respond(
          404,
          json: {'detail': 'no such book'},
        )
        ..when(HttpMethod.get, '/v1/broken').respond(503, body: 'later');
      final client = await rest
          .get()
          .uri('/missing')
          .retrieve()
          .body<String>()
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(client, isA<HttpClientErrorException>());
      final error = client! as HttpClientErrorException;
      expect(error.statusCode, HttpStatus.notFound);
      expect(error.statusText, 'Not Found');
      expect(error.message, '404 Not Found: {"detail":"no such book"}');
      expect(error.bodyAs(_json), {'detail': 'no such book'});
      expect(error.bodyText, '{"detail":"no such book"}');
      expect(error, isA<HttpStatusCodeException>());
      expect(error, isA<RestClientResponseException>());
      await expectLater(
        rest.get().uri('/broken').retrieve().toBodilessEntity(),
        throwsA(
          isA<HttpServerErrorException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.bodyText, 'body', 'later'),
        ),
      );
    });

    test('no response is a ResourceAccessException', () async {
      server
          .when(HttpMethod.get, '/v1/down')
          .fail(
            HttpTransportException('connection refused'),
          );
      await expectLater(
        rest.get().uri('/down?token=s3cret').retrieve().body<String>(),
        throwsA(
          isA<ResourceAccessException>()
              .having((e) => e.isRetryable, 'retryable', isTrue)
              .having(
                (e) => e.message,
                'message',
                'I/O error on GET request for '
                    '"https://api.neon.books/v1/down": connection refused',
              ),
        ),
      );
    });

    test(
      'onStatus first, then defaultStatusHandler, then the default',
      () async {
        final seen = <String>[];
        final client = rest
            .mutate()
            .defaultStatusHandler((s) => s == 404, (_, _) {
              seen.add('default 404');
              throw StateError('default');
            })
            .defaultStatusHandler((s) => s.isError, (_, _) {
              seen.add('default error');
            })
            .build();
        server
          ..when(HttpMethod.get, '/v1/a').respond(404, body: 'x')
          ..when(HttpMethod.get, '/v1/b').respond(500, body: 'y')
          ..when(HttpMethod.get, '/v1/c').respond(302);
        await expectLater(
          client
              .get()
              .uri('/a')
              .retrieve()
              .onStatus((s) => s == 404, (_, _) {
                seen.add('own 404');
                throw ArgumentError('own');
              })
              .onStatus((s) => s == 404, (_, _) => seen.add('second 404'))
              .body<String>(),
          throwsArgumentError,
        );
        await expectLater(
          client.get().uri('/a').retrieve().body<String>(),
          throwsStateError,
        );
        // A handler that returns: the body is read as for a success.
        expect(await client.get().uri('/b').retrieve().body<String>(), 'y');
        // A 3xx is no error unless a handler says so.
        expect(
          (await client.get().uri('/c').retrieve().toBodilessEntity())
              .statusCode,
          302,
        );
        await expectLater(
          client
              .get()
              .uri('/c')
              .retrieve()
              .onStatus(
                (s) => s.is3xxRedirection,
                (_, response) => throw RestClientResponseException.of(response),
              )
              .toBodilessEntity(),
          throwsA(isA<UnknownHttpStatusCodeException>()),
        );
        expect(seen, ['own 404', 'default 404', 'default error']);
      },
    );
  });

  group('interceptors', () {
    test(
      'run in order, the first outermost, and may change the request',
      () async {
        final order = <String>[];
        ClientHttpRequestInterceptor named(String name) =>
            ClientHttpRequestInterceptor.of((request, body, execution) async {
              order.add('> $name');
              request.headers.add('X-Seen', name);
              final response = await execution.execute(request, body);
              order.add('< $name');
              return response;
            });
        final client = rest
            .mutate()
            .requestInterceptor(named('a'))
            .requestInterceptors((list) => list.add(named('b')))
            .build();
        server.when(HttpMethod.post, '/v1/x').respond(204);
        await client.post().uri('/x').body('one').retrieve().toBodilessEntity();
        expect(order, ['> a', '> b', '< b', '< a']);
        expect(server.lastRequest.headers.getAll('X-Seen'), ['a', 'b']);
      },
    );

    test('may replace the body or answer by itself', () async {
      final client = rest
          .mutate()
          .requestInterceptor(
            ClientHttpRequestInterceptor.of(
              (request, body, execution) =>
                  execution.execute(request, utf8.encode('replaced')),
            ),
          )
          .build();
      server.when(HttpMethod.post, '/v1/x').respond(204);
      await client.post().uri('/x').body('one').retrieve().toBodilessEntity();
      expect(utf8.decode(server.lastRequest.body!), 'replaced');
      final cached = rest
          .mutate()
          .requestInterceptor(
            ClientHttpRequestInterceptor.of(
              (request, body, execution) async =>
                  HttpResponse(200, body: utf8.encode('cached')),
            ),
          )
          .build();
      expect(await cached.get().uri('/y').retrieve().body<String>(), 'cached');
    });
  });

  test('exchange gets every status, without status handling', () async {
    server.when(HttpMethod.get, '/v1/missing').respond(404, json: {'a': 1});
    final result = await rest
        .get()
        .uri('/missing')
        .exchange(
          (request, response) => (
            response.statusCode,
            response.bodyTo(_json),
            response.createException(),
            request.url.path,
          ),
        );
    expect(result.$1, 404);
    expect(result.$2, {'a': 1});
    expect(result.$3, isA<HttpClientErrorException>());
    expect(result.$4, '/v1/missing');
  });

  group('the builder', () {
    test(
      'default headers and cookies; a request header replaces one',
      () async {
        final client = rest
            .mutate()
            .defaultHeader('X-Api-Version', '2')
            .defaultHeaders((h) => h.add('X-Trace', 't'))
            .defaultCookie('region', 'eu')
            .defaultRequest((spec) => spec.header('X-Default-Request', 'yes'))
            .build();
        server.when(HttpMethod.get, '/v1/x').respond(204);
        await client
            .get()
            .uri('/x')
            .header('X-Api-Version', '3')
            .cookie('session', 'abc')
            .accept(MediaType.applicationJson)
            .retrieve()
            .toBodilessEntity();
        final headers = server.lastRequest.headers;
        expect(headers.getAll('X-Api-Version'), ['3']);
        expect(headers['X-Trace'], 't');
        expect(headers['X-Default-Request'], 'yes');
        expect(headers['Cookie'], 'region=eu; session=abc');
        expect(headers['Accept'], MediaType.applicationJson);
      },
    );

    test('clone and mutate are independent copies', () async {
      final builder = RestClient.builder()
          .transport(server)
          .baseUrl('https://a.test');
      final copy = builder.clone().baseUrl('https://b.test');
      final a = builder.build();
      builder.baseUrl('https://c.test');
      final b = copy.build();
      final c = a.mutate().defaultHeader('X', '1').build();
      server
        ..when(HttpMethod.get, 'https://a.test/x').respond(204)
        ..when(HttpMethod.get, 'https://b.test/x').respond(204);
      await a.get().uri('/x').retrieve().toBodilessEntity();
      await b.get().uri('/x').retrieve().toBodilessEntity();
      await c.get().uri('/x').retrieve().toBodilessEntity();
      expect(server.requests.map((r) => r.url.host), [
        'a.test',
        'b.test',
        'a.test',
      ]);
      expect(server.requests.first.headers.contains('X'), isFalse);
      expect(server.requests.last.headers['X'], '1');
    });

    test('timeouts and redirects reach the request', () async {
      final client = rest
          .mutate()
          .readTimeout(const Duration(seconds: 7))
          .connectTimeout(const Duration(seconds: 2))
          .followRedirects(false)
          .sensitiveHeaders(['X-Grant'])
          .build();
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await client.get().uri('/x').retrieve().toBodilessEntity();
      final request = server.lastRequest;
      expect(request.readTimeout, const Duration(seconds: 7));
      expect(request.connectTimeout, const Duration(seconds: 2));
      expect(request.followRedirects, isFalse);
      expect(request.sensitiveHeaders, {'x-grant'});
      expect(request.timeout, isNull);
    });

    test('a custom converter in front', () async {
      final client = rest
          .mutate()
          .messageConverters((list) => list.insert(0, _Csv()))
          .build();
      server
          .when(HttpMethod.get, '/v1/x')
          .respond(
            200,
            body: 'a,b',
            headers: {'Content-Type': 'text/csv'},
          );
      expect(
        await client
            .get()
            .uri('/x')
            .retrieve()
            .body(const ListType<String>(ClassType<String>())),
        ['a', 'b'],
      );
    });
  });

  group('the request deadline', () {
    test('the time left becomes the timeout of the call', () async {
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await RequestDeadline.run(const Duration(seconds: 2), () async {
        await rest
            .mutate()
            .readTimeout(const Duration(minutes: 1))
            .build()
            .get()
            .uri('/x')
            .retrieve()
            .toBodilessEntity();
      });
      final request = server.lastRequest;
      expect(request.timeout, lessThanOrEqualTo(const Duration(seconds: 2)));
      expect(
        request.readTimeout,
        lessThanOrEqualTo(const Duration(seconds: 2)),
      );
    });

    RestClient withTimeout(Duration timeout) => rest
        .mutate()
        .requestInterceptor(
          ClientHttpRequestInterceptor.of(
            (request, body, execution) => execution.execute(
              HttpRequest(
                method: request.method,
                url: request.url,
                headers: request.headers,
                body: body,
                timeout: timeout,
                attributes: request.attributes,
              ),
              body,
            ),
          ),
        )
        .build();

    test('a request timeout shorter than the time left is kept', () async {
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await RequestDeadline.run(const Duration(minutes: 1), () async {
        await withTimeout(
          const Duration(seconds: 3),
        ).get().uri('/x').retrieve().toBodilessEntity();
      });
      expect(server.lastRequest.timeout, const Duration(seconds: 3));
    });

    test('a request timeout longer than the time left is cut', () async {
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await RequestDeadline.run(const Duration(seconds: 2), () async {
        await withTimeout(
          const Duration(minutes: 1),
        ).get().uri('/x').retrieve().toBodilessEntity();
      });
      expect(
        server.lastRequest.timeout,
        lessThanOrEqualTo(const Duration(seconds: 2)),
      );
    });

    test('a request timeout without a deadline is kept', () async {
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await withTimeout(
        const Duration(seconds: 3),
      ).get().uri('/x').retrieve().toBodilessEntity();
      expect(server.lastRequest.timeout, const Duration(seconds: 3));
    });

    test('a passed deadline sends nothing', () async {
      server.when(HttpMethod.get, '/v1/x').respond(204);
      await expectLater(
        RequestDeadline.run(
          Duration.zero,
          () => rest.get().uri('/x').retrieve().toBodilessEntity(),
        ),
        throwsA(
          isA<ResourceAccessException>()
              .having((e) => e.isTimeout, 'timeout', isTrue)
              .having(
                (e) => e.cause,
                'cause',
                isA<RequestDeadlineExceededException>(),
              ),
        ),
      );
      expect(server.requests, isEmpty);
    });
  });

  test('sensitive headers and parameters are never logged', () async {
    final lines = <String>[];
    final stop = SpringLog.listen((record) => lines.add(record.message));
    SpringLog.setLevel('web.client.RestClient', SpringLogLevel.trace);
    addTearDown(() {
      stop();
      SpringLog.setLevel('web.client.RestClient', null);
    });
    server.when(HttpMethod.get, '/v1/x').respond(204);
    await rest
        .mutate()
        .sensitiveHeaders(['X-Grant'])
        .build()
        .get()
        .uri('/x?code=c0de&page=2')
        .header('Authorization', 'Bearer t0ken')
        .header('X-Api-Key', 'k3y')
        .header('X-Grant', 'gr4nt')
        .header('X-Plain', 'visible')
        .retrieve()
        .toBodilessEntity();
    final log = lines.join('\n');
    expect(
      log,
      contains('---> GET https://api.neon.books/v1/x?code=***&page=2'),
    );
    expect(log, contains('X-Plain: visible'));
    expect(log, contains('Authorization: ***'));
    for (final secret in ['t0ken', 'k3y', 'gr4nt', 'c0de']) {
      expect(log, isNot(contains(secret)));
    }
  });

  group('streams', () {
    test('server-sent events as objects, through the interceptors', () async {
      final seen = <String>[];
      final client = rest
          .mutate()
          .requestInterceptor(
            ClientHttpRequestInterceptor.of((request, body, execution) async {
              final response = await execution.execute(request, body);
              seen.add('${response.statusCode} ${request.headers['Accept']}');
              return response;
            }),
          )
          .build();
      server.when(HttpMethod.get, '/v1/events').respondEvents([
        const ServerSentEvent<Object?>({'n': 1}, id: '1'),
        const ServerSentEvent<Object?>({'n': 2}, id: '2'),
      ]);
      final events = client
          .get()
          .uri('/events')
          .retrieve()
          .eventStream(
            type: _json,
            reconnect: SseReconnect.never,
          );
      expect(await events.toList(), [
        {'n': 1},
        {'n': 2},
      ]);
      expect(events.lastEventId, '2');
      expect(seen, ['200 text/event-stream']);
      expect(server.lastRequest.headers['Cache-Control'], 'no-cache');
    });

    test(
      'an error status fails the stream with the handlers exception',
      () async {
        server.when(HttpMethod.get, '/v1/events').respond(403, body: 'no');
        await expectLater(
          rest
              .get()
              .uri('/events')
              .retrieve()
              .eventStream<String>(reconnect: SseReconnect.never)
              .toList(),
          throwsA(isA<HttpClientErrorException>()),
        );
      },
    );

    test('a lost connection is opened again with Last-Event-ID', () async {
      server.when(HttpMethod.get, '/v1/events').respondEvents([
        const ServerSentEvent<Object?>('a', id: '7'),
      ]);
      final events = rest
          .get()
          .uri('/events')
          .retrieve()
          .eventStream<String>(
            reconnect: const SseReconnect(
              delay: Duration(milliseconds: 1),
              maxAttempts: 3,
            ),
          );
      expect(await events.take(2).toList(), ['a', 'a']);
      expect(server.requests.last.headers['Last-Event-ID'], '7');
    });

    test('the bytes of the body as they arrive', () async {
      server
          .when(HttpMethod.get, '/v1/file')
          .respondStream(
            200,
            () => Stream.fromIterable([
              [1, 2],
              [3],
            ]),
          );
      expect(await rest.get().uri('/file').retrieve().bodyStream().toList(), [
        [1, 2],
        [3],
      ]);
      server.when(HttpMethod.get, '/v1/gone').respond(410);
      await expectLater(
        rest.get().uri('/gone').retrieve().bodyStream().toList(),
        throwsA(isA<HttpClientErrorException>()),
      );
    });
  });

  test('RestClient.create gives a client with the defaults', () {
    expect(RestClient.create('https://a.test'), isA<RestClient>());
    expect(RestClient.create(), isA<RestClient>());
  });
}

final class _Csv implements HttpMessageConverter {
  @override
  bool canRead(TypeInfo<Object?> type, String? contentType) =>
      contentType == 'text/csv';

  @override
  Object? read(TypeInfo<Object?> type, Uint8List body, String? contentType) =>
      utf8.decode(body).split(',');

  @override
  bool canWrite(Object value, String? contentType) => false;

  @override
  ({List<int> bytes, String contentType}) write(
    Object value,
    String? contentType,
    TypeInfo<Object?>? type,
  ) => throw UnsupportedError('read only');
}
