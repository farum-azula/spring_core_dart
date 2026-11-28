// The HTTP service interfaces of test/http_services/app/, end to end: the
// generated classes are beans on their groups' RestClients, and each
// parameter role, return type and annotation shows in the request the mock
// transport gets; a @Retryable call is retried through the bean's proxy.
// What the build refuses is in the generator's tests
// (test/restclient/http_service_generation_test.dart).
import 'dart:convert';

import 'package:spring_boot_starter_restclient/spring_auto_configuration.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'http_services/app/http_services_app.dart';
import 'spring_gen/http_services/app/http_services_app.spring.dart';

const _catalog = 'https://catalog.neon.books';
const _payments = 'https://pay.neon.books';
const _reports = 'https://reports.neon.books';

const _dune = {'isbn': '978-0', 'title': 'Dune'};

ApplicationContextRunner _runner(MockHttpTransport server) =>
    const ApplicationContextRunner()
        .withUserConfiguration($application)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootResilienceAutoConfiguration)
        .withAutoConfiguration(springBootStarterRestclientAutoConfiguration)
        .withPropertyValues([
          'spring.http.serviceclient.catalog.base-url=$_catalog',
          'spring.http.serviceclient.payments.base-url=$_payments',
          'app.source=tests',
        ])
        .withBean<HttpTransport>(() => server);

// Runs [body] with the application's BookService on [server].
Future<void> _withBooks(
  MockHttpTransport server,
  Future<void> Function(BookService books) body,
) => _runner(server).runAsync((context) async {
  expect(context.startupFailure, isNull);
  await body(context.getBean<BookService>());
});

String _text(HttpRequest request) => utf8.decode(request.body ?? const []);

void main() {
  group('the beans', () {
    test('one per interface, on the RestClient of its group', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.post, '$_payments/payments/p-1').respond(204);
      await _runner(server).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context, hasSingleBean<BookService>());
        expect(context, hasSingleBean<PaymentService>());
        await context.getBean<PaymentService>().pay('p-1', 1250);
        expect(
          '${server.lastRequest.url}',
          '$_payments/payments/p-1?cents=1250',
        );
      });
    });

    test('the groups the application declares, with their interfaces', () {
      _runner(MockHttpTransport()).run((context) {
        final groups = context.getBean<HttpServiceGroups>();
        expect(groups.groupNames, containsAll(['catalog', 'payments']));
        expect(groups.group('catalog').types, [BookService]);
        expect(groups.group('payments').types, [PaymentService]);
      });
    });
  });

  group('a configuration with a @Profile', () {
    test('without the profile: neither its services nor its group', () async {
      await _runner(MockHttpTransport()).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(context, doesNotHaveBean<ReportService>());
        expect(context, doesNotHaveBean<ReportClients>());
        expect(
          context.getBean<HttpServiceGroups>().groupNames,
          isNot(contains('reports')),
        );
      });
    });

    test('with the profile: its services on their group', () async {
      final server = MockHttpTransport()
        ..when(
          HttpMethod.get,
          '$_reports/reports/r-1',
        ).respond(200, body: 'ok');
      await _runner(server)
          .withPropertyValues([
            'spring.profiles.active=reports',
            'spring.http.serviceclient.reports.base-url=$_reports',
          ])
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            expect(await context.getBean<ReportService>().find('r-1'), 'ok');
            expect('${server.lastRequest.url}', '$_reports/reports/r-1');
          });
    });
  });

  group('the parameters', () {
    test('a path variable, and the attribute of the interface', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/978-0').respond(200, json: _dune);
      await _withBooks(server, (books) async {
        final book = await books.find('978-0');
        expect((book.isbn, book.title), ('978-0', 'Dune'));
        final request = server.lastRequest;
        expect('${request.url}', '$_catalog/books/978-0');
        expect(request.attributes['tenant'], 'neon');
      });
    });

    test('query parameters, a null one left out; headers; a cookie', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books').respond(200, json: [_dune]);
      await _withBooks(server, (books) async {
        final found = await books.search(
          'du ne',
          shelves: [Shelf.fiction, Shelf.science],
          tags: ['new', 'sale'],
          session: 's-1',
        );
        expect([for (final book in found) book.isbn], ['978-0']);
        final request = server.lastRequest;
        expect(request.url.queryParametersAll, {
          'q': ['du ne'],
          'shelves': ['fiction', 'science'],
        });
        expect(request.headers.getAll('X-Tag'), ['new', 'sale']);
        expect(request.headers['Cookie'], 'session=s-1');
        await books.search('dune', year: 1965);
        expect(server.lastRequest.url.queryParameters, {
          'q': 'dune',
          'year': '1965',
        });
        expect(server.lastRequest.headers['Cookie'], isNull);
      });
    });

    test('a JSON body, a header from a property, Accept, a number header '
        'and the entity of the answer', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.post, '/books').respond(
          201,
          json: _dune,
          headers: {'Location': '/books/978-0'},
        );
      await _withBooks(server, (books) async {
        final created = await books.create(
          const Book(isbn: '978-0', title: 'Dune'),
          7,
        );
        expect(created.statusCode.value, 201);
        expect(created.body?.title, 'Dune');
        expect(created.headers.location, Uri.parse('/books/978-0'));
        final request = server.lastRequest;
        expect(jsonDecode(_text(request)), _dune);
        expect(request.headers['X-Source'], 'tests');
        expect(request.headers['Accept'], 'application/json');
        expect(request.headers['X-Request-Id'], '7');
      });
    });

    test('multipart parts: a file, a JSON part, an optional field', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.post, '/books/978-0/cover').respond(204);
      await _withBooks(server, (books) async {
        await books.upload(
          '978-0',
          InMemoryMultipartFile(
            'cover',
            [1, 2, 3],
            originalFilename: 'dune.png',
            contentType: 'image/png',
          ),
          const Book(isbn: '978-0', title: 'Dune'),
          null,
        );
        final request = server.lastRequest;
        expect(
          request.headers['Content-Type'],
          startsWith('multipart/form-data'),
        );
        final body = latin1.decode(request.body!);
        expect(body, contains('name="cover"; filename="dune.png"'));
        expect(body, contains('Content-Type: image/png'));
        expect(body, contains('name="meta"'));
        expect(body, contains('{"isbn":"978-0","title":"Dune"}'));
        expect(body, isNot(contains('name="note"')));
      });
    });

    test(
      "a form of the request parameters, and the method's attribute",
      () async {
        final server = MockHttpTransport()
          ..when(HttpMethod.post, '/books/login').respond(200, body: 'token');
        await _withBooks(server, (books) async {
          expect(await books.login('ada', Shelf.science), 'token');
          final request = server.lastRequest;
          expect(
            request.headers['Content-Type'],
            startsWith('application/x-www-form-urlencoded'),
          );
          expect(_text(request), 'user=ada&shelf=science');
          expect(request.attributes['tenant'], 'login');
        });
      },
    );

    test('the method and the URL as parameters', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.options, '$_catalog/elsewhere').respond(
          200,
          body: 'GET, HEAD',
        );
      await _withBooks(server, (books) async {
        expect(
          await books.exchange(HttpMethod.options, Uri.parse('/elsewhere')),
          'GET, HEAD',
        );
      });
    });
  });

  group('the answers', () {
    test('no body: the status only, the entity, the headers', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.put, '/books/978-0').respond(204)
        ..when(HttpMethod.delete, '/books/978-0').respond(204)
        ..when(HttpMethod.head, '/books/978-0').respond(
          200,
          headers: {'X-Copies': '3'},
        );
      await _withBooks(server, (books) async {
        await books.replace('978-0', const Book(isbn: '978-0', title: 'Dune'));
        expect(jsonDecode(_text(server.lastRequest)), _dune);
        final removed = await books.remove('978-0');
        expect(removed.statusCode.value, 204);
        final headers = await books.head('978-0');
        expect(headers['X-Copies'], '3');
      });
    });

    test('server-sent events and the bytes of a body', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/events').respondEvents([
          const ServerSentEvent(_dune, id: '1'),
        ])
        ..when(HttpMethod.get, '/books/978-0/pdf').respond(
          200,
          bytes: [37, 80, 68, 70],
        );
      await _withBooks(server, (books) async {
        final events = await books.events().take(1).toList();
        expect(events.single.title, 'Dune');
        final bytes = await books
            .pdf('978-0')
            .expand((chunk) => chunk)
            .toList();
        expect(bytes, [37, 80, 68, 70]);
      });
    });

    test("an error status throws the client's exception", () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/000').respond(404);
      await _withBooks(server, (books) async {
        await expectLater(
          books.find('000'),
          throwsA(
            isA<HttpClientErrorException>().having(
              (error) => error.statusCode,
              'statusCode',
              HttpStatus.notFound,
            ),
          ),
        );
      });
    });
  });

  test('@Retryable on a method of the interface: a lost connection is '
      'retried through the proxy', () async {
    final server = MockHttpTransport()
      ..when(
        HttpMethod.get,
        '/books/978-0',
      ).fail(HttpTransportException('connection reset'))
      ..when(HttpMethod.get, '/books/978-0').respond(200, json: _dune);
    await _withBooks(server, (books) async {
      final book = await books.findPatiently('978-0');
      expect(book.title, 'Dune');
      expect(server.requests, hasLength(2));
    });
  });
}
