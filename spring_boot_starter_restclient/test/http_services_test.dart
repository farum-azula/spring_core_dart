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

import 'http_services/app/clients/stock_service.dart';
import 'http_services/app/http_services_app.dart';
import 'spring_gen/http_services/app/http_services_app.spring.dart';

const _catalog = 'https://catalog.neon.books';
const _payments = 'https://pay.neon.books';
const _reports = 'https://reports.neon.books';
const _stock = 'https://stock.neon.books';
const _insert = 'spring.http.serviceclient.stock.apiversion.insert';

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

    test(
      'multipart parts: a file streamed, a JSON part, an optional field',
      () async {
        var sent = <int>[];
        final server = MockHttpTransport()
          ..when(HttpMethod.post, '/books/978-0/cover').respondWith((
            request,
          ) async {
            // The file's part is streamed: the body is read as it is sent.
            sent = await request.streamingBody!.toBytes();
            return HttpResponse(204, request: request);
          });
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
          expect(request.body, isNull);
          final body = latin1.decode(sent);
          expect(body, contains('name="cover"; filename="dune.png"'));
          expect(body, contains('Content-Type: image/png'));
          expect(body, contains('name="meta"'));
          expect(body, contains('{"isbn":"978-0","title":"Dune"}'));
          expect(body, isNot(contains('name="note"')));
        });
      },
    );

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

  group('the parameters of several values', () {
    test('maps of query parameters, headers and cookies; HttpHeaders; '
        'request attributes', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/filter').respond(200, body: 'ok');
      await _withBooks(server, (books) async {
        await books.filter(
          {'author': 'Frank Herbert'},
          shelves: {
            'shelf': [Shelf.fiction, Shelf.science],
          },
          counts: {'X-Count': 2},
          more: HttpHeaders()..add('X-More', 'yes'),
          cookies: {
            'pref': ['dark', 'compact'],
          },
          tag: 'checkout',
          marks: {'mark': 1, 'none': null},
        );
        final request = server.lastRequest;
        expect(request.url.queryParametersAll, {
          'author': ['Frank Herbert'],
          'shelf': ['fiction', 'science'],
        });
        expect(request.headers['X-Count'], '2');
        expect(request.headers['X-More'], 'yes');
        expect(request.headers['Cookie'], 'pref=dark; pref=compact');
        expect(request.attributes['trace.tag'], 'checkout');
        expect(request.attributes['mark'], 1);
        expect(request.attributes.containsKey('none'), isFalse);
        expect(request.attributes['tenant'], 'neon');
        // A null map, a null HttpHeaders and a null attribute add nothing.
        await books.filter({});
        final bare = server.lastRequest;
        expect(bare.url.query, isEmpty);
        expect(bare.headers['Cookie'], isNull);
        expect(bare.attributes.containsKey('trace.tag'), isFalse);
      });
    });

    test('a header value with a line break never reaches the server', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/filter').respond(200, body: 'ok');
      await _withBooks(server, (books) async {
        expect(
          () => books.filter({}, more: HttpHeaders()..add('X-A', 'a\r\nX-B')),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => books.filter(
            {},
            cookies: {
              'session': ['a; admin=1'],
            },
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(server.requests, isEmpty);
      });
    });

    test('a map of path variables', () async {
      final server = MockHttpTransport()
        ..when(
          HttpMethod.get,
          '/books/fiction/978-0',
        ).respond(200, json: _dune);
      await _withBooks(server, (books) async {
        final book = await books.onShelf({'shelf': 'fiction', 'isbn': '978-0'});
        expect(book.title, 'Dune');
        expect(
          () => books.onShelf({'shelf': 'fiction'}),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    test("a UriBuilderFactory: its base URL, else the group's", () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/books/978-0').respond(200, json: _dune);
      await _withBooks(server, (books) async {
        await books.fromMirror(
          const UriBuilderFactory('https://mirror.neon.books'),
          '978-0',
        );
        expect(
          '${server.lastRequest.url}',
          'https://mirror.neon.books/books/978-0',
        );
        await books.fromMirror(null, '978-0');
        expect('${server.lastRequest.url}', '$_catalog/books/978-0');
      });
    });

    test('a map of form fields, an enum by its name', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.post, '/books/subscribe').respond(200, body: 'ok');
      await _withBooks(server, (books) async {
        await books.subscribe({'weekly': Shelf.fiction});
        expect(_text(server.lastRequest), 'weekly=fiction');
      });
    });
  });

  group('the stock group: basePackageClasses and API versions', () {
    ApplicationContextRunner stock(MockHttpTransport server) =>
        _runner(server).withPropertyValues([
          'spring.http.serviceclient.stock.base-url=$_stock',
        ]);

    MockHttpTransport stockServer() => MockHttpTransport()
      ..when(HttpMethod.get, '/stock/s-1').respond(200, body: '5')
      ..when(HttpMethod.get, '/stock/s-1/history').respond(200, body: '[]')
      ..when(HttpMethod.get, '/alerts').respond(200, body: 'none');

    test('the interfaces of the directory, found by the build', () {
      _runner(MockHttpTransport()).run((context) {
        expect(context, hasSingleBean<StockService>());
        expect(context, hasSingleBean<StockAlerts>());
        expect(
          context.getBean<HttpServiceGroups>().group('stock').types,
          [StockService, StockAlerts],
        );
      });
    });

    test(
      "the group's default version, the method's, the interface's",
      () async {
        final server = stockServer();
        await stock(server)
            .withPropertyValues([
              'spring.http.serviceclient.stock.apiversion.default=1.0',
              '$_insert.header=API-Version',
            ])
            .runAsync((context) async {
              expect(context.startupFailure, isNull);
              final service = context.getBean<StockService>();
              expect(await service.level('s-1'), '5');
              expect(server.lastRequest.headers['API-Version'], '1.0');
              await service.history('s-1');
              expect(server.lastRequest.headers['API-Version'], '2.0');
              await context.getBean<StockAlerts>().all();
              expect(server.lastRequest.headers['API-Version'], '3.1');
            });
      },
    );

    test('a query parameter, a path segment', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, '/stock/s-1').respond(200, body: '5')
        ..when(
          HttpMethod.get,
          '/2.0/stock/s-1/history',
        ).respond(200, body: 'h');
      await stock(server)
          .withPropertyValues([
            'spring.http.serviceclient.stock.apiversion.default=1.0',
            '$_insert.query-parameter=v',
          ])
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            await context.getBean<StockService>().level('s-1');
            expect('${server.lastRequest.url}', '$_stock/stock/s-1?v=1.0');
          });
      await stock(server)
          .withPropertyValues([
            '$_insert.path-segment=0',
          ])
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            await context.getBean<StockService>().history('s-1');
            expect(
              '${server.lastRequest.url}',
              '$_stock/2.0/stock/s-1/history',
            );
          });
    });

    test('a default version and no inserter fail the start', () async {
      await stock(MockHttpTransport())
          .withPropertyValues([
            'spring.http.serviceclient.stock.apiversion.default=1.0',
          ])
          .runAsync((context) async {
            expect(
              '${context.startupFailure}',
              allOf(
                contains(
                  'The HTTP service group "stock" asks for the API '
                  'version "1.0"',
                ),
                contains('spring.http.serviceclient.stock.apiversion.insert'),
              ),
            );
          });
    });

    test('a version of the annotation and no inserter fail the call, as in '
        'Spring', () async {
      final server = stockServer();
      await stock(server).runAsync((context) async {
        expect(context.startupFailure, isNull);
        expect(await context.getBean<StockService>().level('s-1'), '5');
        expect(server.lastRequest.headers['API-Version'], isNull);
        await expectLater(
          context.getBean<StockService>().history('s-1'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              startsWith('No ApiVersionInserter configured'),
            ),
          ),
        );
      });
    });

    test("a customizer's inserter serves the group's default", () async {
      final server = stockServer();
      await stock(server)
          .withPropertyValues([
            'spring.http.serviceclient.stock.apiversion.default=1.0',
          ])
          .withBean<RestClientCustomizer>(
            () => RestClientCustomizer.of(
              (builder) => builder.apiVersionInserter(
                ApiVersionInserter.useHeader('X-Version'),
              ),
            ),
          )
          .runAsync((context) async {
            expect(context.startupFailure, isNull);
            await context.getBean<StockService>().level('s-1');
            expect(server.lastRequest.headers['X-Version'], '1.0');
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

  test('@Retryable with a MultipartFile part: each attempt streams the file '
      'again', () async {
    final bodies = <String>[];
    final server = MockHttpTransport()
      ..when(
        HttpMethod.post,
        '/books/978-0/scan',
      ).fail(HttpTransportException('connection reset'))
      ..when(HttpMethod.post, '/books/978-0/scan').respondWith((request) async {
        bodies.add(latin1.decode(await request.streamingBody!.toBytes()));
        return HttpResponse(204, request: request);
      });
    await _withBooks(server, (books) async {
      await books.scanPatiently(
        '978-0',
        InMemoryMultipartFile('scan', utf8.encode('page one')),
      );
      expect(server.requests, hasLength(2));
      expect(bodies.single, contains('page one'));
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
