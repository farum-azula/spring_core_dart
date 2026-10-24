import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

void main() {
  group('MediaType.parse parameters, like Spring', () {
    test('a parameter without "=" is ignored', () {
      final type = MediaType.parse('text/plain; flowed; charset=UTF-8');
      expect(type.parameters, {'charset': 'UTF-8'});
    });

    test('names are tokens, values tokens or quoted strings', () {
      expect(
        () => MediaType.parse('text/plain; a b=c'),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(
        () => MediaType.parse('text/plain; a=b c'),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(
        () => MediaType.parse('text/plain; a='),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(
        () => MediaType.parse('text/plain; =b'),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(MediaType.parse('text/plain; a="b c"').getParameter('a'), 'b c');
      expect(MediaType.parse("text/plain; a='b c'").getParameter('a'), 'b c');
      expect(MediaType.parse('text/plain; a="b;c"; d=e').parameters, {
        'a': '"b;c"',
        'd': 'e',
      });
    });

    test('charset must be a legal name, quoted or not', () {
      expect(MediaType.parse('text/plain; charset="utf-8"').charset, utf8);
      expect(MediaType.parse("text/plain; charset='latin1'").charset, latin1);
      // Legal but unknown to Dart: accepted, no Encoding.
      expect(MediaType.parse('text/plain; charset=windows-1252').charset, null);
      expect(
        () => MediaType.parse('text/plain; charset=@@'),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(
        () => MediaType.parse('text/plain; charset=""'),
        throwsA(isA<InvalidMediaTypeException>()),
      );
    });

    test('a name given twice (any case) keeps the last value', () {
      final type = MediaType.parse('text/plain; Charset=latin1; charset=utf-8');
      expect(type.parameters, {'charset': 'utf-8'});
      expect(type.charset, utf8);
    });

    test('the constructor checks parameters too', () {
      expect(
        () => MediaType('text', 'plain', {'a b': 'c'}),
        throwsA(isA<InvalidMediaTypeException>()),
      );
      expect(
        () => MediaType('text', 'plain', {'q': '"2"'}),
        throwsA(isA<InvalidMediaTypeException>()),
      );
    });
  });

  group('HttpResponse.bodyText', () {
    List<int> latin(String text) => latin1.encode(text);

    test('decodes with the charset of the Content-Type', () {
      for (final contentType in [
        'text/plain; charset="ISO-8859-1"',
        "text/plain;charset='iso-8859-1'",
        'text/plain; CHARSET=Latin1',
        'text/plain; charset=l1',
      ]) {
        final response = HttpResponse(
          200,
          headers: HttpHeaders({'Content-Type': contentType}),
          body: latin('café'),
        );
        expect(response.bodyText, 'café', reason: contentType);
      }
    });

    test('UTF-8 by default, for unknown charsets and broken types', () {
      final bytes = utf8.encode('café');
      for (final contentType in [
        null,
        'text/plain',
        'text/plain; charset=windows-1252',
        'not a type',
      ]) {
        final response = HttpResponse(
          200,
          headers: HttpHeaders({'Content-Type': ?contentType}),
          body: bytes,
        );
        expect(response.bodyText, 'café', reason: contentType);
      }
    });

    test('US-ASCII replaces bytes above 127', () {
      final response = HttpResponse(
        200,
        headers: HttpHeaders({'Content-Type': 'text/plain; charset=us-ascii'}),
        body: [0x61, 0xe9],
      );
      expect(response.bodyText, 'a�');
    });
  });

  group('HttpHeaders', () {
    test('lastModified is lenient, date is strict', () {
      final headers = HttpHeaders({
        'Last-Modified': 'yesterday',
        'Date': 'yesterday',
      });
      expect(headers.lastModified, isNull);
      expect(() => headers.date, throwsArgumentError);
    });

    test('addAll, addHeaders, putAll, setAll, clear, size', () {
      final headers = HttpHeaders()
        ..addAll('X-Tag', ['a', 'b'])
        ..add('x-tag', 'c')
        ..set('Accept', 'text/plain');
      expect(headers.size, 2);
      expect(headers.getAll('X-TAG'), ['a', 'b', 'c']);

      headers.addHeaders(HttpHeaders({'Accept': 'application/json'}));
      expect(headers.getAll('accept'), ['text/plain', 'application/json']);

      headers.putAll(
        HttpHeaders.fromEntries([
          const MapEntry('x-tag', 'z'),
          const MapEntry('X-Tag', 'y'),
        ]),
      );
      expect(headers.getAll('X-Tag'), ['z', 'y']);
      expect(headers.getAll('Accept'), ['text/plain', 'application/json']);

      headers.setAll({'Accept': '*/*', 'X-New': '1'});
      expect(headers.getAll('Accept'), ['*/*']);
      expect(headers['x-new'], '1');
      expect(headers.size, 3);

      headers.clear();
      expect(headers.isEmpty, isTrue);
      expect(headers.size, 0);
    });

    test('containsHeaderValue', () {
      final headers = HttpHeaders()
        ..add('Vary', 'Accept')
        ..add('vary', 'Origin');
      expect(headers.containsHeaderValue('VARY', 'Origin'), isTrue);
      expect(headers.containsHeaderValue('Vary', 'origin'), isFalse);
      expect(headers.containsHeaderValue('Other', 'Origin'), isFalse);
    });

    test('== ignores name case and name order, not value order', () {
      final a = HttpHeaders()
        ..add('A', '1')
        ..add('B', '2')
        ..add('B', '3');
      final b = HttpHeaders()
        ..add('b', '2')
        ..add('a', '1')
        ..add('b', '3');
      final c = HttpHeaders()
        ..add('A', '1')
        ..add('B', '3')
        ..add('B', '2');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(HttpHeaders(), HttpHeaders());
    });

    test('readOnly is a view whose setters throw', () {
      final headers = HttpHeaders({'A': '1'});
      final view = HttpHeaders.readOnly(headers);
      expect(view.isReadOnly, isTrue);
      expect(() => view.set('A', '2'), throwsUnsupportedError);
      expect(() => view.add('B', '2'), throwsUnsupportedError);
      expect(() => view.remove('A'), throwsUnsupportedError);
      expect(() => view.clear(), throwsUnsupportedError);
      expect(() => view.contentType = 'text/plain', throwsUnsupportedError);
      headers.add('B', '2');
      expect(view['b'], '2');
      expect(view.copy().isReadOnly, isFalse);
    });
  });

  group('ResponseEntity', () {
    test('headers are read-only', () {
      final entity = ResponseEntity.ok('x');
      expect(() => entity.headers.set('A', '1'), throwsUnsupportedError);
      final built = ResponseEntity.status(201).header('A', ['1']).body('x');
      expect(() => built.headers.add('A', '2'), throwsUnsupportedError);
      expect(built.headers['a'], '1');
    });

    test('== compares status, headers and body', () {
      ResponseEntity<Object?> entity(int status, Object? body, [String? tag]) =>
          ResponseEntity(
            status,
            body: body,
            headers: HttpHeaders({'ETag': ?tag}),
          );
      expect(entity(200, 'a', 'v'), entity(200, 'a', 'v'));
      expect(entity(200, 'a').hashCode, entity(200, 'a').hashCode);
      expect(entity(200, 'a'), isNot(entity(201, 'a')));
      expect(entity(200, 'a'), isNot(entity(200, 'b')));
      expect(entity(200, 'a', 'v'), isNot(entity(200, 'a', 'w')));
      expect(
        entity(200, [
          {'a': 1},
        ]),
        entity(200, [
          {'a': 1},
        ]),
      );
      expect(entity(200, [1]).hashCode, entity(200, [1]).hashCode);
    });

    test('of and ofNullable: 200 with a body, 404 without', () {
      final found = ResponseEntity.of('book');
      expect(found.statusCode, HttpStatus.ok);
      expect(found.body, 'book');
      final missing = ResponseEntity.ofNullable<String>(null);
      expect(missing.statusCode, HttpStatus.notFound);
      expect(missing.hasBody, isFalse);
      expect(ResponseEntity.ofNullable(1).statusCode, 200);
    });
  });
}
