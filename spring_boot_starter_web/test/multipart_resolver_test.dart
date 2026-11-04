import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_web/src/config/web_properties.dart';
import 'package:spring_boot_starter_web/src/multipart_resolver.dart';
import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

// The multipart resolver on request bodies written out by hand: what it
// accepts, the limits it keeps and the errors it answers with.

const _boundary = 'XX';

String _part(String headers, String content) =>
    '--$_boundary\r\n$headers\r\n\r\n$content\r\n';

MockServerHttpRequest _request(
  String body, {
  HttpMethod method = HttpMethod.post,
  String contentType = 'multipart/form-data; boundary=$_boundary',
}) {
  final request = MockServerHttpRequest(method, '/upload');
  request.headers.set('content-type', contentType);
  request.setBody(body);
  return request;
}

String _form(List<String> parts) => '${parts.join()}--$_boundary--\r\n';

Matcher _problem(int status, String detail) => isA<ErrorResponseException>()
    .having((e) => e.statusCode, 'status', status)
    .having((e) => e.body.detail, 'detail', contains(detail));

void main() {
  group('isMultipart', () {
    final resolver = MultipartResolver();

    test('is true for a multipart request that has a body', () {
      expect(resolver.isMultipart(_request('')), isTrue);
    });

    test('is false for GET, for other types and when disabled', () {
      expect(
        resolver.isMultipart(_request('', method: HttpMethod.get)),
        isFalse,
      );
      expect(
        resolver.isMultipart(_request('', contentType: 'text/plain')),
        isFalse,
      );
      expect(
        MultipartResolver(
          const MultipartProperties(enabled: false),
        ).isMultipart(_request('')),
        isFalse,
      );
      expect(
        resolver.isMultipart(MockServerHttpRequest(HttpMethod.post, '/')),
        isFalse,
      );
    });
  });

  test(
    'the properties take the sizes of the settings; a blank location is none',
    () {
      final properties = MultipartProperties.from(
        MultipartSettings()..location = '  ',
      );
      expect(properties.location, isNull);
      expect(properties.maxFileSize, 1024 * 1024);
      expect(properties.maxPartCount, 50);
      expect(
        MultipartProperties.from(
          MultipartSettings()..location = ' /tmp/x ',
        ).location,
        '/tmp/x',
      );
    },
  );

  group('reading', () {
    test('fields, with the charset of the part', () async {
      final request = MockServerHttpRequest(HttpMethod.post, '/upload');
      request.headers.set(
        'content-type',
        'multipart/form-data; boundary=$_boundary',
      );
      final latin = _part(
        'Content-Disposition: form-data; name="l"\r\n'
            'Content-Type: text/plain; charset=ISO-8859-1',
        'é',
      );
      final odd = _part(
        'Content-Disposition: form-data; name="o"\r\n'
            'Content-Type: not a media type',
        'x',
      );
      final utf = _part('Content-Disposition: form-data; name="u"', 'é');
      // The first field is written as Latin-1 bytes.
      final bytes = <int>[
        ...latin1.encode(latin),
        ...utf8.encode('$odd$utf--$_boundary--\r\n'),
      ];
      request.setBody(bytes);
      final resolved = await MultipartResolver().resolve(request);
      expect(resolved.fields['l'], ['é']);
      expect(resolved.fields['o'], ['x']);
      expect(resolved.fields['u'], ['é']);
      expect(resolved.part('u')!.$2, utf8.encode('é'));
      expect(resolved.part('missing'), isNull);
    });

    test('a part without a name is skipped', () async {
      final request = _request(
        _form([
          _part('Content-Disposition: form-data', 'ignored'),
          _part('Content-Disposition: form-data; name="a"', '1'),
        ]),
      );
      final resolved = await MultipartResolver().resolve(request);
      expect(resolved.fields, {
        'a': ['1'],
      });
    });

    test(
      'a file is stored, read back, copied and deleted by cleanup',
      () async {
        final resolver = MultipartResolver();
        final request = _request(
          _form([
            _part(
              'Content-Disposition: form-data; name="f"; filename="a.txt"\r\n'
                  'Content-Type: text/plain',
              'hello',
            ),
            _part(
              'Content-Disposition: form-data; name="e"; filename="empty.txt"',
              '',
            ),
          ]),
        );
        final first = resolver.resolve(request);
        expect(resolver.resolve(request), same(first));
        final resolved = await first;
        final file = resolved.files['f']!.single;
        expect(file.originalFilename, 'a.txt');
        expect(file.contentType, 'text/plain');
        expect(file.size, 5);
        expect(file.isEmpty, isFalse);
        expect(file.toString(), 'MultipartFile(f, a.txt, 5 bytes)');
        expect(utf8.decode(await file.bytes), 'hello');
        expect(
          utf8.decode([
            for (final chunk in await file.openRead().toList()) ...chunk,
          ]),
          'hello',
        );
        expect(resolved.files['e']!.single.isEmpty, isTrue);

        final directory = await io.Directory.systemTemp.createTemp('multipart');
        addTearDown(() => directory.delete(recursive: true));
        final copy = '${directory.path}${io.Platform.pathSeparator}copy.txt';
        await file.transferTo(copy);
        expect(await io.File(copy).readAsString(), 'hello');

        await resolver.cleanup(request);
        // Cleaning up twice is harmless.
        await resolver.cleanup(request);
      },
    );
  });

  group('failures answer with a status that names the cause', () {
    test('no boundary is a 400', () async {
      final request = _request('x', contentType: 'multipart/form-data');
      await expectLater(
        MultipartResolver().resolve(request),
        throwsA(_problem(400, 'no boundary')),
      );
    });

    test('a body that stops in the middle is a 400', () async {
      final request = _request(
        '--$_boundary\r\nContent-Disposition: form-data; name="a"\r\n\r\nva',
      );
      await expectLater(
        MultipartResolver().resolve(request),
        throwsA(_problem(400, 'Failed to parse multipart request')),
      );
    });

    test('a text field over the file size limit is a 413', () async {
      final request = _request(
        _form([
          _part('Content-Disposition: form-data; name="big"', 'x' * 20),
        ]),
      );
      await expectLater(
        MultipartResolver(
          const MultipartProperties(maxFileSize: 10),
        ).resolve(request),
        throwsA(_problem(413, 'part "big"')),
      );
    });

    test('a file over the file size limit is a 413', () async {
      final request = _request(
        _form([
          _part(
            'Content-Disposition: form-data; name="f"; filename="f.bin"',
            'x' * 20,
          ),
        ]),
      );
      await expectLater(
        MultipartResolver(
          const MultipartProperties(maxFileSize: 10),
        ).resolve(request),
        throwsA(_problem(413, 'file "f"')),
      );
    });

    test('a request over the request size limit is a 413', () async {
      final request = _request(
        _form([
          _part('Content-Disposition: form-data; name="a"', 'x' * 100),
        ]),
      );
      await expectLater(
        MultipartResolver(
          const MultipartProperties(maxRequestSize: 50),
        ).resolve(request),
        throwsA(_problem(413, 'the request is larger than 50 bytes')),
      );
    });

    test('more parts than allowed is a 413', () async {
      final request = _request(
        _form([
          for (var i = 0; i < 3; i++)
            _part('Content-Disposition: form-data; name="p$i"', '$i'),
        ]),
      );
      await expectLater(
        MultipartResolver(
          const MultipartProperties(maxPartCount: 2),
        ).resolve(request),
        throwsA(_problem(413, 'more than 2 parts')),
      );
    });
  });
}
