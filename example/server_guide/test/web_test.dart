// Chapter 3, the web: controllers through MockMvc (the real dispatcher,
// filters and error handling, no socket), JSON, problems, files, events,
// filters, interceptors, CORS and the session.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/book_controller.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:spring_boot_starter_security/testing.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

import 'support/app.dart';

const dune = '9780441013593';

/// A request made by an admin, with a valid CSRF token.
MockRequestBuilder asAdmin(HttpMethod method, String path) =>
    MockRequestBuilder(method, path)
      ..with_(user('root').roles(['USER', 'ADMIN']))
      ..with_(csrf());

void main() {
  final app = neonBooks();

  group('the catalog', () {
    test('a page of books: JSON from the ObjectMapper', () async {
      await app.mockMvc
          .get('/api/books', params: {'q': 'dune'})
          .andExpect(
            status: 200,
            contentType: MediaType.applicationJson,
            json: {
              'items': [
                {
                  'isbn': dune,
                  'title': 'Dune',
                  'author': 'Frank Herbert',
                  'price': 9.99,
                  'year': 1965,
                  'tags': ['fiction', 'science-fiction'],
                  'format': 'PAPERBACK', // @JsonValue
                  'available': 5,
                },
              ],
              'page': 0,
              'size': 10,
              'total': 1,
            },
          );
      final all = jsonOf(await app.mockMvc.get('/api/books').andReturn());
      expect(all, containsPair('total', 8));
    });

    test('request parameters are converted; a bad one is a 400', () async {
      await app.mockMvc
          .get('/api/books', params: {'page': '1'})
          .andExpect(status: 200, json: containsPair('page', 1));
      await app.mockMvc
          .get('/api/books', params: {'page': 'two'})
          .andExpect(
            status: 400,
            contentType: MediaType.applicationProblemJson,
          );
      await app.mockMvc
          .get('/api/books', params: {'page': '-1'})
          .andExpect(
            status: 400,
            json: containsPair('detail', 'page must be >= 0'),
          );
    });

    test('an unknown book is a 404 ProblemDetail', () async {
      await app.mockMvc
          .get('/api/books/9780000000000')
          .andExpect(
            status: 404,
            contentType: MediaType.applicationProblemJson,
            json: {
              'type': 'about:blank',
              'title': 'Book not found',
              'status': 404,
              'detail': 'No book 9780000000000',
              'instance': '/api/books/9780000000000',
              'isbn': '9780000000000',
            },
          );
    });

    test('a cookie remembers the books seen last', () async {
      final seen = await app.mockMvc.get('/api/books/$dune').andReturn();
      final cookie = seen.response.cookies.singleWhere(
        (c) => c.name == 'neon-recent',
      );
      expect(cookie.value, dune);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, 'Lax');
      final recent = await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.get, '/api/books/recent')
              ..cookies['neon-recent'] = cookie.value,
          )
          .andReturn();
      expect(jsonOf(recent), [containsPair('title', 'Dune')]);
    });
  });

  group('adding books', () {
    test('@Valid: field errors in the language asked for', () async {
      final result = await app.mockMvc
          .perform(
            asAdmin(HttpMethod.post, '/api/books')
              ..headers['Accept-Language'] = 'ja'
              ..json({'isbn': '12', 'title': ' ', 'author': 'X', 'price': 1}),
          )
          .andExpect(status: 400, contentType: MediaType.applicationProblemJson)
          .andReturn();
      final errors = (jsonOf(result)! as Map)['errors'] as List;
      expect(errors, [
        {
          'field': 'isbn',
          'message': 'ISBNは978または979で始まる13桁です',
          'rejectedValue': '12',
        },
        {'field': 'title', 'message': 'タイトルを入力してください', 'rejectedValue': ' '},
      ]);
    });

    test(
      'unreadable JSON: the log names the place, the client gets 400',
      () async {
        await app.mockMvc
            .perform(
              asAdmin(HttpMethod.post, '/api/books')
                ..json({'isbn': '9780261102385', 'price': 'cheap'}),
            )
            .andExpect(
              status: 400,
              json: containsPair('detail', 'Failed to read request'),
            );
        // What the ObjectMapper says (Jackson's JsonMappingException).
        expect(
          () => app.getBean<ObjectMapper>().readValue<NewBook>(
            '{"isbn": "9780261102385", "price": "cheap"}',
          ),
          throwsA(
            isA<JsonMappingException>().having(
              (e) => '$e',
              'message',
              contains('price'),
            ),
          ),
        );
      },
    );

    test('201 Created with Location', () async {
      await app.mockMvc
          .perform(
            asAdmin(HttpMethod.post, '/api/books')..json({
              'isbn': '9780261102385',
              'title': 'The Lord of the Rings',
              'author': 'J. R. R. Tolkien',
              'price': 25,
              'format': 'HARDCOVER',
            }),
          )
          .andExpect(
            status: 201,
            headers: {'Location': '/api/books/9780261102385'},
            json: containsPair('format', 'HARDCOVER'),
          );
      // The same again: StateError → 409 by the advice.
      await app.mockMvc
          .perform(
            asAdmin(HttpMethod.post, '/api/books')..json({
              'isbn': '9780261102385',
              'title': 'Again',
              'author': 'X',
              'price': 1,
            }),
          )
          .andExpect(status: 409);
    });
  });

  group('covers', () {
    test('a Resource with Range and Cache-Control', () async {
      final whole = await app.mockMvc
          .get('/api/books/$dune/cover')
          .andExpect(
            status: 200,
            contentType: 'image/png',
            headers: {
              'Cache-Control': 'public, max-age=86400',
              'Accept-Ranges': 'bytes',
            },
          )
          .andReturn();
      final length = whole.response.bodyBytes.length;
      final part = await app.mockMvc
          .get(
            '/api/books/$dune/cover',
            // What the app's Feign client sends (produces: 'image/*').
            headers: {'Range': 'bytes=0-7', 'Accept': 'image/*'},
          )
          .andExpect(
            status: 206,
            headers: {'Content-Range': 'bytes 0-7/$length'},
          )
          .andReturn();
      expect(part.response.bodyBytes, whole.response.bodyBytes.sublist(0, 8));
    });

    test('uploads: multipart, checked type, then served', () async {
      final png =
          (await app.mockMvc.get('/api/books/9780345539434/cover').andReturn())
              .response
              .bodyBytes;
      await app.mockMvc
          .multipart(
            '/api/books/9780451524935/cover',
            method: HttpMethod.put,
            files: [MockMultipartFile('file', '1984.png', 'image/png', png)],
            headers: {'X-XSRF-TOKEN': 'none'},
          )
          .andExpect(status: 403); // no admin, no CSRF token
      Future<MvcResult> upload(String type) => app.mockMvc
          .perform(
            asAdmin(HttpMethod.put, '/api/books/9780451524935/cover')
              ..headers[HttpHeaders.contentTypeHeader] =
                  'multipart/form-data; boundary=neon'
              ..content(
                utf8.encode(
                      '--neon\r\n'
                      'Content-Disposition: form-data; name="file"; '
                      'filename="1984"\r\n'
                      'Content-Type: $type\r\n\r\n',
                    ) +
                    png +
                    utf8.encode('\r\n--neon--\r\n'),
              ),
          )
          .andReturn();
      expect((await upload('text/plain')).response.statusCode, 415);
      expect((await upload('image/png')).response.statusCode, 204);
      final served = await app.mockMvc
          .get('/api/books/9780451524935/cover')
          .andReturn();
      expect(served.response.bodyBytes, png);
      expect(served.response.headers['Last-Modified'], isNotNull); // a file
    });

    // The file of a cover is `<directory>/<isbn>.<png|jpg>`: the ISBN of a
    // book in the catalog (13 digits), the extension from the content
    // type; the client's file name is never part of a path.
    test('no way out of the covers directory', () async {
      final directory = io.Directory(
        app.getBean<BookController>().covers.getObject().directory,
      ).absolute;
      // A real book, a file name that climbs: stored under the ISBN (and
      // removed after, so the packaged cover is served again).
      final stored = io.File('${directory.path}/9780345539434.png');
      if (stored.existsSync()) {
        stored.deleteSync(); // left by an interrupted run
      }
      addTearDown(() {
        if (stored.existsSync()) {
          stored.deleteSync();
        }
      });
      // Where `../`, `../../` and `../../../escape.png` would land, and
      // the directory itself: only the cover's own file may appear.
      final before = directory.listSync().map((e) => e.path).toSet();
      final escapes = [
        for (var up = directory, i = 0; i < 4; up = up.parent, i++)
          io.File('${up.path}/escape.png'),
      ];

      for (final isbn in [
        '..%2F..%2Fpubspec.yaml',
        '..%252F..%252Fpubspec.yaml',
        '%2e%2e%2f%2e%2e%2fpubspec.yaml',
        '....%2F%2F....%2F%2Fpubspec.yaml',
        '..%5C..%5Cpubspec.yaml',
        '%2e%2e',
        '..',
      ]) {
        final read = await app.mockMvc
            .get('/api/books/$isbn/cover')
            .andReturn();
        expect(read.response.statusCode, isNot(200), reason: isbn);
        expect(
          utf8.decode(read.response.bodyBytes, allowMalformed: true),
          isNot(contains('neon_books_server')),
          reason: isbn,
        );
        final written = await app.mockMvc
            .perform(
              asAdmin(HttpMethod.put, '/api/books/$isbn/cover')
                ..headers[HttpHeaders.contentTypeHeader] =
                    'multipart/form-data; boundary=neon'
                ..content(
                  utf8.encode(
                    '--neon\r\n'
                    'Content-Disposition: form-data; name="file"; '
                    'filename="escape.png"\r\n'
                    'Content-Type: image/png\r\n\r\n'
                    'escape\r\n--neon--\r\n',
                  ),
                ),
            )
            .andReturn();
        expect(written.response.statusCode, isNot(204), reason: isbn);
      }

      final upload = await app.mockMvc
          .perform(
            asAdmin(HttpMethod.put, '/api/books/9780345539434/cover')
              ..headers[HttpHeaders.contentTypeHeader] =
                  'multipart/form-data; boundary=neon'
              ..content(
                utf8.encode(
                  '--neon\r\n'
                  'Content-Disposition: form-data; name="file"; '
                  'filename="../../../escape.png"\r\n'
                  'Content-Type: image/png\r\n\r\n'
                  'escape\r\n--neon--\r\n',
                ),
              ),
          )
          .andReturn();
      expect(upload.response.statusCode, 204);
      expect(stored.readAsStringSync(), 'escape');
      expect(escapes.where((f) => f.existsSync()), isEmpty);
      expect(
        directory.listSync().map((e) => e.path).toSet().difference(before),
        {stored.path},
      );
    });
  });

  group('server-sent events', () {
    test('stock changes as they happen, resumed with Last-Event-ID', () async {
      final result = await app.mockMvc.get('/api/stock/events').andReturn();
      expect(
        result.response.headers.contentType,
        startsWith('text/event-stream'),
      );
      final next = result.response.eventStream.firstWhere(
        (e) => e.data != null,
      );
      app.getBean<Catalog>().changeStock(dune, 1);
      final event = await next.timeout(const Duration(seconds: 5));
      expect(event.event, 'stock');
      expect(jsonDecode(event.data!), {'isbn': dune, 'available': 6});
      await result.cancel();

      // A client that saw the event before reconnects and gets the next
      // one, which happened while it was away.
      app.getBean<Catalog>().changeStock(dune, -1);
      final resumed = await app.mockMvc
          .get('/api/stock/events', headers: {'Last-Event-ID': event.id!})
          .andReturn();
      final missed = await resumed.response.eventStream
          .firstWhere((e) => e.data != null)
          .timeout(const Duration(seconds: 5));
      expect(jsonDecode(missed.data!), {'isbn': dune, 'available': 5});
      await resumed.cancel();
    });

    test('an SseEmitter pushes orders to admins', () async {
      final live = await app.mockMvc
          .perform(asAdmin(HttpMethod.get, '/api/admin/orders/live'))
          .andReturn();
      final placed = live.response.eventStream.firstWhere(
        (e) => e.event == 'placed',
      );
      final ada = ApiClient(app.mockMvc);
      await ada.login('ada', 'ada-secret');
      await ada.send(
        HttpMethod.put,
        '/api/basket/items/$dune',
        json: {'quantity': 1},
      );
      await ada.send(HttpMethod.post, '/api/orders');
      final event = await placed.timeout(const Duration(seconds: 5));
      expect(jsonDecode(event.data!), containsPair('user', 'ada'));
      await live.cancel();
    });
  });

  group('the session keeps the basket', () {
    test('PUT then GET with the session cookie', () async {
      final ada = ApiClient(app.mockMvc);
      expect(await ada.login('ada', 'ada-secret'), 204);
      final put = await ada.send(
        HttpMethod.put,
        '/api/basket/items/9780140421996',
        json: {'quantity': 1},
      );
      expect(jsonOf(put), {
        'items': [
          {
            'isbn': '9780140421996',
            'title': 'Leaves of Grass',
            'price': 8.0,
            'quantity': 1,
            'discount': 20, // poetry
            'total': 6.4,
          },
        ],
        'count': 1,
        'total': 6.4,
      });
      expect(jsonOf(await ada.get('/api/basket')), containsPair('count', 1));
      // Another session (another client) has its own basket.
      final other = ApiClient(app.mockMvc);
      await other.login('ada', 'ada-secret');
      expect(jsonOf(await other.get('/api/basket')), containsPair('count', 0));
      // More than the stock: 409.
      final tooMany = await ada.send(
        HttpMethod.put,
        '/api/basket/items/9780140421996',
        json: {'quantity': 9},
      );
      expect(tooMany.response.statusCode, 409);
    });
  });

  group('filters, interceptors, CORS', () {
    final logs = captureLogs(level: SpringLogLevel.debug);

    test('a request id, back in the response and in the log', () async {
      await app.mockMvc
          .get('/api/books', headers: {'X-Request-Id': 'abc123'})
          .andExpect(status: 200, headers: {'X-Request-Id': 'abc123'});
      final access = logs.ofLogger('neon.access').single;
      expect(access.message, startsWith('GET /api/books 200'));
      expect(access.fields, containsPair('request', 'abc123'));
    });

    test('the interceptor times the handler (Server-Timing)', () async {
      final result = await app.mockMvc.get('/api/books').andReturn();
      expect(
        result.response.headers['Server-Timing'],
        matches(r'^app;dur=[\d.]+$'),
      );
    });

    test(
      'CORS: the Flutter web build (localhost) may, others may not',
      () async {
        await app.mockMvc
            .perform(
              MockRequestBuilder(HttpMethod.options, '/api/orders')
                ..headers.addAll({
                  'Origin': 'http://localhost:5000',
                  'Access-Control-Request-Method': 'POST',
                  'Access-Control-Request-Headers': 'x-xsrf-token',
                }),
            )
            .andExpect(
              status: 200,
              headers: {
                'Access-Control-Allow-Origin': 'http://localhost:5000',
                'Access-Control-Allow-Credentials': 'true',
              },
            );
        await app.mockMvc
            .get('/api/books', headers: {'Origin': 'https://evil.example'})
            .andExpect(status: 403);
      },
    );
  });
}
