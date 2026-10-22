import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  group('HttpHeaders', () {
    test('case-insensitive, multi-valued, ordered, original casing', () {
      final headers = HttpHeaders({'Accept': 'application/json'})
        ..add('X-Tag', 'a')
        ..add('x-tag', 'b')
        ..add('Content-Type', 'text/plain');
      expect(headers['accept'], 'application/json');
      expect(headers.getAll('X-TAG'), ['a', 'b']);
      expect(headers.names, ['Accept', 'X-Tag', 'Content-Type']);
      expect(headers.toMap(), {
        'Accept': 'application/json',
        'X-Tag': 'a, b',
        'Content-Type': 'text/plain',
      });
      headers.set('x-tag', 'c');
      expect(headers.getAll('X-Tag'), ['c']);
      expect(headers.names, ['Accept', 'x-tag', 'Content-Type']);
      final copy = headers.copy()..remove('ACCEPT');
      expect(copy.contains('Accept'), isFalse);
      expect(headers.contains('Accept'), isTrue);
      final seen = <String>[];
      headers.forEach((name, value) => seen.add('$name=$value'));
      expect(seen, [
        'Accept=application/json',
        'x-tag=c',
        'Content-Type=text/plain',
      ]);
      expect(HttpHeaders().isEmpty, isTrue);
      expect(
        HttpHeaders.fromEntries(const [MapEntry('A', '1'), MapEntry('a', '2')])
            .getAll('a'),
        ['1', '2'],
      );
      expect(headers['missing'], isNull);
    });
  });

  test('HttpMethod', () {
    expect(HttpMethod.post.value, 'POST');
    expect(HttpMethod.parse('delete'), HttpMethod.delete);
    expect(HttpMethod.parse(' PATCH '), HttpMethod.patch);
    expect(() => HttpMethod.parse('FETCH'), throwsArgumentError);
    expect('${HttpMethod.get}', 'GET');
  });

  test('HttpStatus', () {
    expect(HttpStatus.notFound, 404);
    expect(HttpStatus.reasonPhrase(503), 'Service Unavailable');
    expect(HttpStatus.reasonPhrase(499), 'Client Error');
    expect(HttpStatus.isSuccess(204), isTrue);
    expect(HttpStatus.isClientError(404), isTrue);
    expect(HttpStatus.isServerError(502), isTrue);
    expect(HttpStatus.isError(302), isFalse);
  });

  test('ResponseEntity', () {
    final created = ResponseEntity<String>(
      HttpStatus.created,
      body: 'x',
      headers: HttpHeaders({'Location': '/books/1'}),
    );
    expect(created.isSuccess, isTrue);
    expect(created.headers['location'], '/books/1');
    expect('$created', 'ResponseEntity(201 Created, x)');
    final ok = ResponseEntity.ok(42);
    expect(ok.statusCode, 200);
    expect(ok.body, 42);
    expect(ResponseEntity<void>(404).isSuccess, isFalse);
  });

  test('HttpRequest and HttpResponse', () {
    final request = HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('https://a.b/c?d=1'),
    );
    expect('$request', 'GET https://a.b/c?d=1');
    expect(request.headers.isEmpty, isTrue);
    final response = HttpResponse(
      200,
      body: utf8.encode('héllo'),
      request: request,
    );
    expect(response.bodyText, 'héllo');
    expect(response.isSuccess, isTrue);
    expect(
      HttpResponse(
        200,
        body: latin1.encode('é'),
        headers: HttpHeaders({
          'Content-Type': 'text/plain; charset=ISO-8859-1',
        }),
      ).bodyText,
      'é',
    );
    expect(HttpResponse(200, body: const [0xff]).bodyText, '�');
  });

  test('mapping annotations', () {
    const List<Mapping> mappings = [
      GetMapping('/a'),
      PostMapping('/b', consumes: MediaType.applicationJson),
      PutMapping('/c'),
      PatchMapping('/d'),
      DeleteMapping('/e', headers: ['X-A: 1']),
      RequestMapping('/f', method: HttpMethod.head),
    ];
    expect(
      [for (final m in mappings) m.method],
      [
        HttpMethod.get,
        HttpMethod.post,
        HttpMethod.put,
        HttpMethod.patch,
        HttpMethod.delete,
        HttpMethod.head,
      ],
    );
    expect(mappings[1].consumes, 'application/json');
    expect(mappings[4].headers, ['X-A: 1']);
    expect(const PathVariable().name, isNull);
    expect(const RequestParam('q').name, 'q');
  });
}
