// The REST client against MockHttpTransport: requests, JSON, errors and
// retries, with the application's own configuration.
import 'dart:convert';

import 'package:spring_boot_feign_example/src/jsonplaceholder_client.dart';
import 'package:spring_boot_feign_example/src/models.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

import 'support/app.dart';
import 'support/fixtures.dart' as fixtures;

void main() {
  late MockHttpTransport server;

  setUp(() => server = MockHttpTransport());

  Future<void> withClient(
    Future<void> Function(JsonPlaceholderClient api) body,
  ) => appContext()
      .withBean<HttpTransport>(server)
      .runAsync((context) => body(context.getBean<JsonPlaceholderClient>()));

  test(
    'GET: the URL from application.properties, JSON into nested classes',
    () async {
      server.when(HttpMethod.get, '/users/1').respond(200, json: fixtures.user);
      await withClient((api) async {
        final user = await api.user(1);
        expect(user.name, 'Leanne Graham');
        expect(user.address.city, 'Gwenborough');
        expect(user.company.name, 'Romaguera-Crona');
        expect(user.website, 'hildegard.org');
      });
      final request = server.lastRequest;
      expect('${request.url}', 'https://jsonplaceholder.typicode.com/users/1');
      expect(request.headers[HttpHeaders.accept], MediaType.applicationJson);
      // The RequestInterceptor bean of FeignConfig.
      expect(request.headers['X-Client'], 'spring-boot-feign-example');
    },
  );

  test('a query parameter, a path variable and lists', () async {
    server
      ..when(
        HttpMethod.get,
        '/posts?userId=1',
      ).respond(200, json: fixtures.posts)
      ..when(
        HttpMethod.get,
        '/posts/1/comments',
      ).respond(200, json: fixtures.comments);
    await withClient((api) async {
      final posts = await api.postsOf(1);
      expect(posts, isA<List<Post>>());
      expect([for (final p in posts) p.title], ['first post', 'second post']);
      final comments = await api.comments(posts.first.id);
      expect(comments.map((c) => c.email), contains('ann@example.com'));
    });
  });

  test('POST: the body as JSON, the answer as a ResponseEntity', () async {
    server
        .when(HttpMethod.post, '/posts')
        .respondWith(
          (request) => HttpResponse(
            201,
            headers: HttpHeaders({
              HttpHeaders.contentType: MediaType.applicationJson,
            }),
            body: utf8.encode(
              jsonEncode(
                fixtures.created(
                  jsonDecode(utf8.decode(request.body!))
                      as Map<String, Object?>,
                ),
              ),
            ),
            request: request,
          ),
        );
    await withClient((api) async {
      final created = await api.create(
        const NewPost(userId: 1, title: 'Spring in Dart', body: 'It works.'),
      );
      expect(created.statusCode, 201);
      expect(created.body!.id, 101);
      expect(created.body!.title, 'Spring in Dart');
    });
    final request = server.lastRequest;
    expect(request.headers[HttpHeaders.contentType], MediaType.applicationJson);
    expect(jsonDecode(utf8.decode(request.body!)), {
      'userId': 1,
      'title': 'Spring in Dart',
      'body': 'It works.',
    });
  });

  test('404 → FeignNotFound', () async {
    server.when(HttpMethod.get, '/posts/9999').respond(404, json: {});
    await withClient(
      (api) => expectLater(
        api.post(9999),
        throwsA(isA<FeignNotFound>().having((e) => e.status, 'status', 404)),
      ),
    );
  });

  test(
    'connection failures: 3 attempts (the Retryer bean), then an error',
    () async {
      server
          .when(HttpMethod.get, '/users/1')
          .fail(HttpTransportException('down'));
      await withClient(
        (api) => expectLater(api.user(1), throwsA(isA<RetryableException>())),
      );
      expect(server.requests, hasLength(3));
    },
  );

  test('a failure followed by an answer is retried transparently', () async {
    server
      ..when(HttpMethod.get, '/users/1').fail(HttpTransportException('reset'))
      ..when(HttpMethod.get, '/users/1').respond(200, json: fixtures.user);
    await withClient((api) async => expect((await api.user(1)).id, 1));
    expect(server.requests, hasLength(2));
  });
}
