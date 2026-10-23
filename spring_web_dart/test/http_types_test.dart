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
      headers.forEach((name, values) => seen.add('$name=$values'));
      expect(seen, [
        'Accept=[application/json]',
        'x-tag=[c]',
        'Content-Type=[text/plain]',
      ]);
      expect(HttpHeaders().isEmpty, isTrue);
      expect(
        HttpHeaders.fromEntries(const [MapEntry('A', '1'), MapEntry('a', '2')])
            .getAll('a'),
        ['1', '2'],
      );
      expect(headers['missing'], isNull);
    });

    test('forEach passes every name once with all its values, like '
        'Spring 7', () {
      final headers = HttpHeaders()
        ..add('Accept', 'text/plain')
        ..add('X-Tag', 'a')
        ..add('accept', 'application/json');
      final seen = <String, List<String>>{};
      headers.forEach((name, values) => seen[name] = values);
      expect(seen, {
        'Accept': ['text/plain', 'application/json'],
        'X-Tag': ['a'],
      });
    });

    test('toSingleValueMap keeps the first value of each name', () {
      final headers = HttpHeaders()
        ..add('Accept', 'text/plain')
        ..add('accept', 'application/json')
        ..add('X-Tag', 'a');
      expect(headers.toSingleValueMap(), {
        'Accept': 'text/plain',
        'X-Tag': 'a',
      });
    });

    test('typed accessors: contentType, location, contentLength', () {
      final headers = HttpHeaders();
      expect(headers.contentType, isNull);
      expect(headers.location, isNull);
      expect(headers.contentLength, -1);
      headers
        ..contentType = MediaType.applicationJson
        ..location = Uri.parse('https://api.neon.test/books/1')
        ..contentLength = 42;
      expect(headers[HttpHeaders.contentTypeHeader], 'application/json');
      expect(headers['location'], 'https://api.neon.test/books/1');
      expect(headers.location, Uri.parse('https://api.neon.test/books/1'));
      expect(headers['Content-Length'], '42');
      expect(headers.contentLength, 42);
      headers
        ..contentType = null
        ..location = null
        ..contentLength = -1;
      expect(headers.isEmpty, isTrue);
    });

    test('setBearerAuth and setBasicAuth', () {
      final headers = HttpHeaders()..setBearerAuth('t0k3n');
      expect(headers[HttpHeaders.authorizationHeader], 'Bearer t0k3n');
      headers.setBasicAuth('Aladdin', 'open sesame');
      expect(headers.getAll('Authorization'), [
        'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==',
      ]);
      // ISO-8859-1 by default, like Spring.
      headers.setBasicAuth('zoë', 'pw');
      expect(headers['Authorization'], 'Basic em/rOnB3');
      expect(
        HttpHeaders.encodeBasicAuth('zoë', 'pw', encoding: utf8),
        'em/Dqzpwdw==',
      );
      expect(() => headers.setBasicAuth('a:b', 'pw'), throwsArgumentError);
      expect(() => headers.setBasicAuth('名前', 'pw'), throwsArgumentError);
    });

    test('name constants', () {
      expect(HttpHeaders.acceptHeader, 'Accept');
      expect(HttpHeaders.contentTypeHeader, 'Content-Type');
      expect(HttpHeaders.ifNoneMatchHeader, 'If-None-Match');
      expect(HttpHeaders.retryAfterHeader, 'Retry-After');
      expect(HttpHeaders.wwwAuthenticateHeader, 'WWW-Authenticate');
    });
  });

  test('HttpMethod', () {
    expect(HttpMethod.post.value, 'POST');
    expect(HttpMethod.parse('delete'), HttpMethod.delete);
    expect(HttpMethod.parse(' PATCH '), HttpMethod.patch);
    expect(() => HttpMethod.parse('FETCH'), throwsArgumentError);
    expect('${HttpMethod.get}', 'GET');
  });

  group('HttpStatus', () {
    test('constants are ints with reason phrases', () {
      expect(HttpStatus.notFound, 404);
      expect(HttpStatus.notFound.value, 404);
      expect(HttpStatus.serviceUnavailable.reasonPhrase, 'Service Unavailable');
      expect(HttpResponse(404).statusCode == HttpStatus.notFound, isTrue);
    });

    test('Spring 7 names: unprocessableContent, contentTooLarge', () {
      expect(HttpStatus.unprocessableContent, 422);
      expect(
        HttpStatus.unprocessableContent.reasonPhrase,
        'Unprocessable Content',
      );
      expect(HttpStatus.contentTooLarge, 413);
      expect(HttpStatus.contentTooLarge.reasonPhrase, 'Content Too Large');
    });

    test('every constant once, by code', () {
      final codes = [for (final status in HttpStatus.values) status.value];
      expect(codes, hasLength(62));
      expect(codes.toSet(), hasLength(codes.length));
      expect(codes, orderedEquals([...codes]..sort()));
      expect(codes, containsAll([100, 103, 226, 308, 418, 421, 451, 511]));
      for (final status in HttpStatus.values) {
        expect(status.reasonPhrase, isNotEmpty);
      }
    });

    test('valueOf, resolve', () {
      expect(HttpStatus.valueOf(503), HttpStatus.serviceUnavailable);
      expect(HttpStatus.resolve(201), HttpStatus.created);
      expect(HttpStatus.resolve(599), isNull);
      expect(() => HttpStatus.valueOf(599), throwsArgumentError);
    });

    test('is2xxSuccessful-style checks and series', () {
      expect(HttpStatus.noContent.is2xxSuccessful, isTrue);
      expect(HttpStatus.continue_.is1xxInformational, isTrue);
      expect(HttpStatus.found.is3xxRedirection, isTrue);
      expect(HttpStatus.notFound.is4xxClientError, isTrue);
      expect(HttpStatus.badGateway.is5xxServerError, isTrue);
      expect(HttpStatus.notFound.isError, isTrue);
      expect(HttpStatus.found.isError, isFalse);
      expect(HttpStatus.ok.series, HttpStatusSeries.successful);
      expect(HttpStatus.notFound.series, HttpStatusSeries.clientError);
      expect(HttpStatusSeries.valueOf(503), HttpStatusSeries.serverError);
      expect(HttpStatusSeries.resolve(99), isNull);
      expect(() => HttpStatusSeries.valueOf(600), throwsArgumentError);
    });

    test('HttpStatusCode for any code, on responses', () {
      final status = HttpStatusCode.valueOf(599);
      expect(status.is5xxServerError, isTrue);
      expect(status.isError, isTrue);
      expect(status.isSameCodeAs(HttpStatusCode(599)), isTrue);
      expect(() => HttpStatusCode.valueOf(42), throwsArgumentError);
      expect(HttpResponse(429).statusCode.is4xxClientError, isTrue);
      expect(ResponseEntity<void>(204).statusCode.is2xxSuccessful, isTrue);
      expect('${HttpResponse(599)}', 'HttpResponse(599)');
    });
  });

  test('ResponseEntity', () {
    final created = ResponseEntity<String>(
      HttpStatus.created,
      body: 'x',
      headers: HttpHeaders({'Location': '/books/1'}),
    );
    expect(created.isSuccess, isTrue);
    expect(created.headers['location'], '/books/1');
    expect(created.headers.location, Uri.parse('/books/1'));
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
      PostMapping.of(path: '/b', consumes: MediaType.applicationJson),
      PutMapping('/c'),
      PatchMapping('/d'),
      DeleteMapping.of(path: '/e', headers: ['X-A=1']),
      RequestMapping.of(path: '/f', method: HttpMethod.head),
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
    expect(mappings[4].headers, ['X-A=1']);
    expect(const PathVariable().name, isNull);
    expect(const RequestParam('q').name, 'q');
    expect(const CookieValue('SESSION').name, 'SESSION');
    expect(const RequestBody().required, isTrue);
    expect(const RequestBody(required: false).required, isFalse);
  });

  test('the path of a mapping is optional', () {
    const List<Mapping> mappings = [
      GetMapping(),
      PostMapping(),
      PutMapping(),
      PatchMapping(),
      DeleteMapping(),
      RequestMapping(),
      GetMapping.of(produces: MediaType.textEventStream),
      RequestMapping.of(method: HttpMethod.head),
    ];
    for (final mapping in mappings) {
      expect(mapping.path, '', reason: '$mapping');
    }
    expect(mappings[0].method, HttpMethod.get);
    expect(mappings[1].method, HttpMethod.post);
    expect(mappings[5].method, HttpMethod.get);
    expect(mappings[6].produces, 'text/event-stream');
    expect(mappings[7].method, HttpMethod.head);
    // The shorthand and the attribute form agree.
    expect(const GetMapping('/a').path, const GetMapping.of(path: '/a').path);
    expect(const GetMapping('/a').headers, isEmpty);
    expect(const GetMapping('/a').produces, isNull);
  });

  test('required and defaultValue of parameter annotations', () {
    // Spring: required unless said otherwise, no default value.
    expect(const PathVariable().required, isTrue);
    expect(const PathVariable('id').required, isTrue);
    expect(const RequestParam('q').required, isTrue);
    expect(const RequestParam('q').defaultValue, isNull);
    expect(const RequestHeader().required, isTrue);
    expect(const RequestHeader('X-Id').defaultValue, isNull);

    const optional = PathVariable.of(name: 'id', required: false);
    expect(optional.name, 'id');
    expect(optional.required, isFalse);
    expect(const PathVariable.of().required, isTrue);

    const param = RequestParam.of(name: 'page', defaultValue: '0');
    expect(param.name, 'page');
    expect(param.defaultValue, '0');
    expect(param.required, isTrue, reason: 'the annotation keeps what was set');
    expect(const RequestParam.of(required: false).name, isNull);
    expect(const RequestParam.of(required: false).required, isFalse);

    const header = RequestHeader.of(name: 'X-Tenant', defaultValue: 'public');
    expect(header.name, 'X-Tenant');
    expect(header.defaultValue, 'public');
    expect(const RequestHeader.of(required: false).required, isFalse);
  });
}
