import 'dart:convert';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

MediaType _t(String value) => MediaType.parse(value);

void main() {
  group('MediaType', () {
    test('parse: type, subtype, parameters, charset, quality', () {
      final type = _t('Text/Plain; charset="ISO-8859-1"; q=0.5');
      expect(type.type, 'text');
      expect(type.subtype, 'plain');
      expect(type.getParameter('CHARSET'), 'ISO-8859-1');
      expect(type.charset, latin1);
      expect(type.qualityValue, 0.5);
      expect(type.isConcrete, isTrue);
      expect('$type', 'text/plain;charset="ISO-8859-1";q=0.5');
      expect(_t('*'), _t(MediaType.all));
      expect(_t('application/problem+json').subtypeSuffix, 'json');
    });

    test('parse rejects invalid media types', () {
      expect(() => _t(''), throwsA(isA<InvalidMediaTypeException>()));
      expect(() => _t('json'), throwsA(isA<InvalidMediaTypeException>()));
      expect(() => _t('text/'), throwsA(isA<InvalidMediaTypeException>()));
      expect(() => _t('*/json'), throwsA(isA<InvalidMediaTypeException>()));
      expect(() => _t('a/b/c'), throwsA(isA<InvalidMediaTypeException>()));
      expect(() => _t('text/plain;q=2'), throwsArgumentError);
      expect(() => _t('te xt/plain'), throwsArgumentError);
    });

    test('parseMediaTypes splits an Accept header', () {
      expect(MediaType.parseMediaTypes('text/html, application/json;q=0.9'), [
        _t('text/html'),
        _t('application/json;q=0.9'),
      ]);
      expect(MediaType.parseMediaTypes(null), isEmpty);
      expect(MediaType.parseMediaTypes(' '), isEmpty);
    });

    test('includes, like Spring (not symmetric)', () {
      expect(_t('*/*').includes(_t('text/plain')), isTrue);
      expect(_t('text/*').includes(_t('text/plain')), isTrue);
      expect(_t('text/plain').includes(_t('text/*')), isFalse);
      expect(_t('text/plain').includes(_t('text/plain;charset=UTF-8')), isTrue);
      expect(_t('text/*').includes(_t('application/json')), isFalse);
      expect(
        _t('application/*+json').includes(_t(MediaType.applicationProblemJson)),
        isTrue,
      );
      expect(
        _t('application/*+json').includes(_t(MediaType.applicationJson)),
        isFalse,
      );
      expect(
        _t('application/*+xml').includes(_t(MediaType.applicationProblemJson)),
        isFalse,
      );
    });

    test('isCompatibleWith, like Spring (symmetric)', () {
      expect(_t('text/plain').isCompatibleWith(_t('text/*')), isTrue);
      expect(_t('text/*').isCompatibleWith(_t('text/plain')), isTrue);
      expect(_t('text/plain').isCompatibleWith(_t('*/*')), isTrue);
      expect(_t('text/plain').isCompatibleWith(_t('text/html')), isFalse);
      expect(
        _t('application/*+json').isCompatibleWith(_t('application/json')),
        isTrue,
      );
      expect(
        _t('application/json').isCompatibleWith(_t('application/*+json')),
        isTrue,
      );
      expect(
        _t('application/problem+json')
            .isCompatibleWith(_t('application/*+json')),
        isTrue,
      );
      expect(
        _t('application/xml').isCompatibleWith(_t('application/*+json')),
        isFalse,
      );
    });

    test('equality ignores the case of names and of charset', () {
      expect(_t('text/plain;Charset=utf-8'), _t('TEXT/PLAIN;charset=UTF-8'));
      expect(_t('text/plain;a=1') == _t('text/plain;a=2'), isFalse);
      expect(
        _t('text/plain;charset=utf-8').equalsTypeAndSubtype(_t('text/plain')),
        isTrue,
      );
    });

    test('common constants', () {
      expect(MediaType.applicationXml, 'application/xml');
      expect(MediaType.applicationProblemJson, 'application/problem+json');
      expect(MediaType.applicationProblemXml, 'application/problem+xml');
      expect(MediaType.applicationNdjson, 'application/x-ndjson');
      expect(MediaType.applicationPdf, 'application/pdf');
      expect(MediaType.textXml, 'text/xml');
      expect(MediaType.imagePng, 'image/png');
    });
  });

  group('HttpHeaders accessors', () {
    test('accept', () {
      final headers = HttpHeaders()
        ..add('Accept', 'text/html, application/json;q=0.9')
        ..add('Accept', '*/*;q=0.1');
      expect(headers.accept, [
        _t('text/html'),
        _t('application/json;q=0.9'),
        _t('*/*;q=0.1'),
      ]);
      headers.accept = [_t(MediaType.applicationJson), _t(MediaType.textPlain)];
      expect(headers['accept'], 'application/json, text/plain');
      headers.accept = [];
      expect(headers.contains('Accept'), isFalse);
    });

    test('eTag is quoted unless it is already, ifNoneMatch lists tags', () {
      final headers = HttpHeaders()..eTag = 'v1';
      expect(headers.eTag, '"v1"');
      headers.eTag = 'W/"v2"';
      expect(headers.eTag, 'W/"v2"');
      headers.ifNoneMatch = ['a', '"b"', 'W/"c"'];
      expect(headers['If-None-Match'], '"a", "b", W/"c"');
      expect(headers.ifNoneMatch, ['"a"', '"b"', 'W/"c"']);
      headers.set('If-None-Match', '*');
      expect(headers.ifNoneMatch, ['*']);
      headers.eTag = null;
      expect(headers.eTag, isNull);
    });

    test('lastModified and date as HTTP dates', () {
      final headers = HttpHeaders()
        ..lastModified = DateTime.utc(2026, 10, 24, 8, 5, 9, 123);
      expect(headers['Last-Modified'], 'Sat, 24 Oct 2026 08:05:09 GMT');
      expect(headers.lastModified, DateTime.utc(2026, 10, 24, 8, 5, 9));
      headers.set('Date', 'Sunday, 06-Nov-94 08:49:37 GMT');
      expect(headers.date, DateTime.utc(1994, 11, 6, 8, 49, 37));
      headers.set('Date', 'Sun Nov  6 08:49:37 1994');
      expect(headers.date, DateTime.utc(1994, 11, 6, 8, 49, 37));
      headers.set('Date', 'yesterday');
      expect(() => headers.date, throwsArgumentError);
      expect(HttpHeaders().lastModified, isNull);
    });

    test('contentDisposition', () {
      final headers = HttpHeaders()
        ..contentDisposition = const ContentDisposition.attachment(
          filename: 'report "q3".pdf',
        );
      expect(
        headers['Content-Disposition'],
        r'attachment; filename="report \"q3\".pdf"',
      );
      expect(headers.contentDisposition!.filename, 'report "q3".pdf');
      expect(headers.contentDisposition!.isAttachment, isTrue);

      headers.setContentDispositionFormData('file', 'résumé.txt');
      expect(
        headers['Content-Disposition'],
        "form-data; name=\"file\"; filename*=UTF-8''r%C3%A9sum%C3%A9.txt",
      );
      expect(
        headers.contentDisposition,
        const ContentDisposition.formData(name: 'file', filename: 'résumé.txt'),
      );
      expect(
        ContentDisposition.parse('INLINE; filename=a.txt; size=3').isInline,
        isTrue,
      );
      expect(HttpHeaders().contentDisposition, isNull);
    });
  });

  group('ResponseEntity builders', () {
    test('status, created, noContent, notFound, badRequest, hasBody', () {
      final created = ResponseEntity.created(Uri.parse('/books/1'))
          .header('X-Id', ['1'])
          .body('book');
      expect(created.statusCode, HttpStatus.created);
      expect(created.headers.location, Uri.parse('/books/1'));
      expect(created.headers['x-id'], '1');
      expect(created.body, 'book');
      expect(created.hasBody, isTrue);

      final noContent = ResponseEntity.noContent().build<void>();
      expect(noContent.statusCode, 204);
      expect(noContent.hasBody, isFalse);

      expect(ResponseEntity.notFound().build<String>().statusCode, 404);
      final bad = ResponseEntity.badRequest()
          .contentType(MediaType.applicationProblemJson)
          .body({'title': 'Bad'});
      expect(bad.statusCode, 400);
      expect(bad.headers.contentType, 'application/problem+json');
      final status = ResponseEntity.status(HttpStatus.accepted)
          .eTag('v1')
          .build<int>();
      expect(status.statusCode, 202);
      expect(status.headers.eTag, '"v1"');
      expect(ResponseEntity.ok(1).hasBody, isTrue);
    });
  });
}
