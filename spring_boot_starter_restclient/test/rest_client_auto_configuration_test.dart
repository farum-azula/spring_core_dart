import 'package:spring_boot_starter_restclient/spring_auto_configuration.dart';
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_web_dart/io.dart';
import 'package:test/test.dart';

const _json = MapType<String, Object?>(ClassType<String>(), DynamicType());

final ApplicationContextRunner _runner = const ApplicationContextRunner()
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterRestclientAutoConfiguration);

BeanDefinition<T> _bean<T extends Object>(
  String name,
  T Function() create, {
  int? order,
}) => BeanDefinition<T>(
  name: name,
  types: [T],
  order: order,
  create: (_) => create(),
  source: 'test#$name',
);

void main() {
  group('the default beans', () {
    test('the transport, its allowed addresses, a builder per injection', () {
      _runner.run((context) {
        expect(context.startupFailure, isNull);
        expect(context, hasSingleBean<HttpTransport>());
        expect(context, hasSingleBean<RestClientBuilderConfigurer>());
        expect(context, hasSingleBean<HttpServiceGroups>());
        final transport = context.getBean<HttpTransport>();
        expect(transport, isA<IoHttpTransport>());
        expect(
          (transport as IoHttpTransport).allowedAddresses,
          same(context.getBean<AllowedAddresses>()),
        );
        expect(
          context.getBean<RestClientBuilder>(),
          isNot(same(context.getBean<RestClientBuilder>())),
        );
      });
    });

    test('every address is denied until allowed by hand', () async {
      await _runner.runAsync((context) async {
        final rest = context.getBean<RestClientBuilder>().build();
        await expectLater(
          rest.get().uri('http://127.0.0.1:9/').retrieve().body<String>(),
          throwsA(
            isA<ResourceAccessException>().having(
              (e) => e.cause,
              'cause',
              isA<FilteredHostException>().having(
                (e) => e.message,
                'message',
                contains('spring.http.clients.allowed-addresses'),
              ),
            ),
          ),
        );
      });
    });

    test('the allow list: the property, the base URLs, the filter bean', () {
      _runner
          .withPropertyValues([
            'spring.http.clients.allowed-addresses=api.neon.books,10.0.0.0/8',
            'spring.http.serviceclient.catalog.base-url=https://catalog.neon.books/v1',
            'spring.http.serviceclient.local.base-url=http://127.0.0.1:8080',
          ])
          .withBean<InetAddressFilter>(
            () => InetAddressFilter.of(['10.1.0.0/16', '127.0.0.1']).or(
              InetAddressFilter.externalAddresses,
            ),
          )
          .run((context) {
            final allowed = context.getBean<AllowedAddresses>()
              ..checkUrl(Uri.parse('https://api.neon.books/x'))
              ..checkUrl(Uri.parse('https://catalog.neon.books/x'))
              ..checkUrl(Uri.parse('http://127.0.0.1:8080/x'))
              ..checkUrl(Uri.parse('http://10.1.2.3/'));
            expect(
              () => allowed.checkUrl(Uri.parse('http://10.2.0.1/')),
              throwsA(isA<FilteredHostException>()),
            );
            expect(
              () => allowed.checkUrl(Uri.parse('https://evil.example/')),
              throwsA(isA<FilteredHostException>()),
            );
          });
    });

    test('an application transport makes the starter back off', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, 'http://books.test/b/1').respond(
          200,
          json: {'isbn': '1'},
        );
      await _runner.withBean<HttpTransport>(() => server).runAsync((
        context,
      ) async {
        expect(context.getBeanNamesForType<HttpTransport>(), [
          'httpTransport',
        ]);
        final rest = context
            .getBean<RestClientBuilder>()
            .baseUrl('http://books.test')
            .build();
        expect(
          await rest.get().uri('/b/{id}', ['1']).retrieve().body(_json),
          {'isbn': '1'},
        );
      });
    });
  });

  group('spring.http.clients.*', () {
    test('timeouts and redirects reach every request', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, 'http://a.test/x').respond(204);
      await _runner
          .withBeanOverride<HttpTransport>(server)
          .withPropertyValues([
            'spring.http.clients.connect-timeout=2s',
            'spring.http.clients.read-timeout=5s',
            'spring.http.clients.redirects=dont-follow',
          ])
          .runAsync((context) async {
            await context
                .getBean<RestClientBuilder>()
                .build()
                .get()
                .uri('http://a.test/x')
                .retrieve()
                .toBodilessEntity();
            final request = server.lastRequest;
            expect(request.connectTimeout, const Duration(seconds: 2));
            expect(request.readTimeout, const Duration(seconds: 5));
            expect(request.followRedirects, isFalse);
          });
    });

    test('the defaults: 10 s to connect, 60 s to read, redirects followed', () {
      _runner.run((context) {
        final properties = context.getBean<HttpClientsProperties>();
        expect(properties.connectTimeout, const Duration(seconds: 10));
        expect(properties.readTimeout, const Duration(seconds: 60));
        expect(properties.redirects, HttpRedirects.followWhenPossible);
        expect(properties.allowedAddresses, isEmpty);
      });
    });

    test('the transport waits as long as the longest connect timeout', () {
      final clients = HttpClientsProperties();
      final groups = HttpServiceClientProperties()
        ..serviceclient = {
          'slow': HttpServiceClientGroupProperties()
            ..connectTimeout = const Duration(seconds: 30),
          'fast': HttpServiceClientGroupProperties()
            ..connectTimeout = const Duration(seconds: 1),
        };
      expect(
        transportConnectTimeout(clients, groups),
        const Duration(seconds: 30),
      );
      clients.connectTimeout = Duration.zero;
      expect(
        transportConnectTimeout(clients, HttpServiceClientProperties()),
        isNull,
      );
    });
  });

  group('customizers', () {
    test('run on every builder, in order', () async {
      final server = MockHttpTransport()
        ..when(HttpMethod.get, 'http://a.test/x').respond(204);
      await _runner
          .withBeanOverride<HttpTransport>(server)
          .withUserConfiguration(
            BeanModule('customizers', [
              _bean<RestClientCustomizer>(
                'second',
                () => RestClientCustomizer.of(
                  (builder) => builder.defaultHeaders(
                    (headers) => headers.add('X-Order', 'second'),
                  ),
                ),
                order: 2,
              ),
              _bean<RestClientCustomizer>(
                'first',
                () => RestClientCustomizer.of(
                  (builder) => builder.defaultHeaders(
                    (headers) => headers.add('X-Order', 'first'),
                  ),
                ),
                order: 1,
              ),
            ]),
          )
          .runAsync((context) async {
            await context
                .getBean<RestClientBuilder>()
                .build()
                .get()
                .uri('http://a.test/x')
                .retrieve()
                .toBodilessEntity();
            expect(server.lastRequest.headers.getAll('X-Order'), [
              'first',
              'second',
            ]);
          });
    });
  });

  group('HTTP service groups', () {
    test('the base URL, default headers and timeouts of a group', () async {
      final server = MockHttpTransport()
        ..when(
          HttpMethod.get,
          'https://catalog.neon.books/v1/books/1',
        ).respond(200, json: {'isbn': '1'});
      await _runner
          .withBeanOverride<HttpTransport>(server)
          .withPropertyValues([
            'spring.http.serviceclient.catalog.base-url=https://catalog.neon.books/v1',
            'spring.http.serviceclient.catalog.default-header.X-Api-Version=2',
            'spring.http.serviceclient.catalog.default-header.X-Tags=a,b',
            'spring.http.serviceclient.catalog.read-timeout=3s',
            'spring.http.serviceclient.catalog.connect-timeout=1s',
            'spring.http.serviceclient.catalog.redirects=dont-follow',
          ])
          .runAsync((context) async {
            final groups = context.getBean<HttpServiceGroups>();
            expect(groups.groupNames, ['catalog']);
            final book = await groups
                .restClient('catalog')
                .get()
                .uri('/books/{isbn}', '1')
                .retrieve()
                .body(_json);
            expect(book, {'isbn': '1'});
            final request = server.lastRequest;
            expect(request.headers['X-Api-Version'], '2');
            expect(request.headers.getAll('X-Tags'), ['a', 'b']);
            expect(request.readTimeout, const Duration(seconds: 3));
            expect(request.connectTimeout, const Duration(seconds: 1));
            expect(request.followRedirects, isFalse);
          });
    });

    test(
      'configurers run after the properties, on the groups they pick',
      () async {
        final server = MockHttpTransport()
          ..when(HttpMethod.get, 'https://a.test/x').respond(204)
          ..when(HttpMethod.get, 'https://b.test/x').respond(204);
        await _runner
            .withBeanOverride<HttpTransport>(server)
            .withPropertyValues([
              'spring.http.serviceclient.a.base-url=https://a.test',
              'spring.http.serviceclient.a.default-header.X-Group=property',
              'spring.http.serviceclient.b.base-url=https://b.test',
            ])
            .withBean<RestClientHttpServiceGroupConfigurer>(
              () => RestClientHttpServiceGroupConfigurer.of(
                (groups) => groups
                    .filterByName(['a'])
                    .forEachClient(
                      (group, builder) => builder.defaultHeader(
                        'X-Group',
                        'configurer ${group.name}',
                      ),
                    ),
              ),
            )
            .runAsync((context) async {
              final groups = context.getBean<HttpServiceGroups>();
              await groups
                  .restClient('a')
                  .get()
                  .uri('/x')
                  .retrieve()
                  .toBodilessEntity();
              expect(server.lastRequest.headers['X-Group'], 'configurer a');
              await groups
                  .restClient('b')
                  .get()
                  .uri('/x')
                  .retrieve()
                  .toBodilessEntity();
              expect(server.lastRequest.headers.contains('X-Group'), isFalse);
            });
      },
    );

    test('a declared group without properties; an unknown group', () {
      _runner
          .withBean<HttpServiceGroup>(
            () => const HttpServiceGroup('payments', types: [String]),
          )
          .run((context) {
            final groups = context.getBean<HttpServiceGroups>();
            expect(groups.group('payments').types, [String]);
            expect(groups.restClient('payments'), isA<RestClient>());
            expect(
              () => groups.restClient('shipping'),
              throwsA(
                isA<ArgumentError>().having(
                  (e) => e.message,
                  'message',
                  contains('spring.http.serviceclient.shipping.base-url'),
                ),
              ),
            );
          });
    });
  });
}
