import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_starter_feign/spring_auto_configuration.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'catalog.dart';
import 'uploads.dart';

/// One part of a recorded multipart body.
typedef Part = ({
  String? name,
  String? filename,
  String? contentType,
  List<int> bytes,
});

extension on Part {
  String get text => utf8.decode(bytes);
}

/// The parts of the multipart body of [request], read with the server's
/// parser.
Future<List<Part>> partsOf(HttpRequest request) async {
  final contentType = MediaType.parse(request.headers.contentType!);
  expect(contentType.type, 'multipart');
  expect(contentType.subtype, 'form-data');
  final boundary = MultipartParser.boundaryOf(contentType)!;
  final parts = <Part>[];
  await for (final part in MultipartParser(
    boundary,
  ).bind(Stream.value(request.body!))) {
    final bytes = [for (final chunk in await part.content.toList()) ...chunk];
    parts.add((
      name: part.name,
      filename: part.filename,
      contentType: part.headers.contentType,
      bytes: bytes,
    ));
  }
  return parts;
}

/// A file that counts how often its content is read.
final class CountingFile extends InMemoryMultipartFile {
  CountingFile(super.name, super.content, {super.originalFilename});

  var reads = 0;

  @override
  Future<Uint8List> get bytes {
    reads++;
    return super.bytes;
  }
}

void main() {
  late MockHttpTransport server;
  late ApplicationContextRunner runner;

  setUp(() {
    server = MockHttpTransport();
    runner = const ApplicationContextRunner()
        .withUserConfiguration(uploadsModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => server);
  });

  test('a file, a JSON part and a text field; @RequestParam stays in the '
      'query', () async {
    server
        .when(HttpMethod.post, '/books/978-0/files?draft=true')
        .respond(200, body: 'stored');
    await runner.runAsync((context) async {
      final result = await context.getBean<UploadClient>().upload(
        '978-0',
        MockMultipartFile('ignored', 'cover.png', 'image/png', [1, 2, 3]),
        const Book(isbn: '978-0', title: 'Dune'),
        'first edition',
        true,
      );
      expect(result, 'stored');
      final request = server.lastRequest;
      // The encoder's type with its boundary replaces `consumes`.
      expect(
        request.headers.contentType,
        startsWith('multipart/form-data; boundary='),
      );
      expect(request.url.queryParameters, {'draft': 'true'});
      final parts = await partsOf(request);
      expect(parts.map((p) => p.name), ['file', 'meta', 'note']);
      final [file, meta, note] = parts;
      expect(file.filename, 'cover.png');
      expect(file.contentType, 'image/png');
      expect(file.bytes, [1, 2, 3]);
      expect(meta.filename, isNull);
      expect(meta.contentType, MediaType.applicationJson);
      expect(jsonDecode(meta.text), {'isbn': '978-0', 'title': 'Dune'});
      expect(note.filename, isNull);
      expect(note.contentType, isNull);
      expect(note.text, 'first edition');
    });
  });

  test('every kind of part, without consumes', () async {
    server.when(HttpMethod.post, '/kinds').respond(200, body: 'ok');
    await runner.runAsync((context) async {
      await context.getBean<UploadClient>().kinds(
        [
          InMemoryMultipartFile('a', [1], originalFilename: 'a.pdf'),
          InMemoryMultipartFile(
            'b',
            [2],
            originalFilename: 'b.bin',
            contentType: 'application/x-b',
          ),
          InMemoryMultipartFile('c', [3], originalFilename: 'c.unknown'),
        ],
        Uint8List.fromList([4, 5]),
        [6, 7],
        42,
        Shelf.science,
        DateTime.utc(2026, 1, 2, 3, 4, 5),
        ['x', 'y'],
        {'lang': 'en', 'n': 1},
        const [Book(isbn: '1', title: 'A')],
      );
      final parts = await partsOf(server.lastRequest);
      expect(parts.map((p) => p.name), [
        'files',
        'files',
        'files',
        'raw',
        'ints',
        'count',
        'shelf',
        'at',
        'tags',
        'tags',
        'labels',
        'books',
      ]);
      // Files: the name of the @RequestPart; the content type from the
      // file, else from the file name, else octet-stream.
      expect(parts.take(3).map((p) => p.filename), [
        'a.pdf',
        'b.bin',
        'c.unknown',
      ]);
      expect(parts.take(3).map((p) => p.contentType), [
        'application/pdf',
        'application/x-b',
        MediaType.applicationOctetStream,
      ]);
      expect(parts.take(3).map((p) => p.bytes), [
        [1],
        [2],
        [3],
      ]);
      // Bytes: a file part without a file name.
      for (final (index, bytes) in [
        (3, [4, 5]),
        (4, [6, 7]),
      ]) {
        expect(parts[index].filename, isNull);
        expect(parts[index].contentType, MediaType.applicationOctetStream);
        expect(parts[index].bytes, bytes);
      }
      // Single values: text fields.
      expect(parts.sublist(5, 10).map((p) => p.text), [
        '42',
        'science',
        '2026-01-02T03:04:05.000Z',
        'x',
        'y',
      ]);
      expect(
        parts.sublist(5, 10).map((p) => p.contentType),
        everyElement(isNull),
      );
      // A Map and a list of objects: JSON parts.
      expect(parts[10].contentType, MediaType.applicationJson);
      expect(jsonDecode(parts[10].text), {'lang': 'en', 'n': 1});
      expect(parts[11].contentType, MediaType.applicationJson);
      expect(jsonDecode(parts[11].text), [
        {'isbn': '1', 'title': 'A'},
      ]);
    });
  });

  group('optional parts', () {
    test('null leaves out a part that is not required', () async {
      server.when(HttpMethod.post, '/optional').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        final client = context.getBean<UploadClient>() as dynamic;
        // Not reachable with the typed interface; the proxy accepts null.
        await client.optional(
          InMemoryMultipartFile('f', [1], originalFilename: 'f.txt'),
          note: null,
        );
        final parts = await partsOf(server.lastRequest);
        expect(parts.map((p) => p.name), ['file']);
        expect(parts.single.contentType, 'text/plain');
      });
    });

    test('given, they are sent', () async {
      server.when(HttpMethod.post, '/optional').respond(200, body: 'ok');
      await runner.runAsync((context) async {
        await context.getBean<UploadClient>().optional(
          InMemoryMultipartFile('f', [1], originalFilename: 'f.txt'),
          note: 'hi',
          cover: InMemoryMultipartFile('c', [2], originalFilename: 'c.jpg'),
        );
        final parts = await partsOf(server.lastRequest);
        expect(parts.map((p) => p.name), ['file', 'note', 'cover']);
        expect(parts.last.contentType, 'image/jpeg');
      });
    });

    test('a required part that is null is an error naming it', () async {
      await runner.runAsync((context) async {
        final client = context.getBean<UploadClient>() as dynamic;
        await expectLater(
          client.optional(null, note: 'hi') as Future<Object?>,
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'file')
                .having(
                  (e) => '${e.message}',
                  'message',
                  allOf(contains('@RequestPart "file"'), contains('optional')),
                ),
          ),
        );
        expect(server.requests, isEmpty);
      });
    });
  });

  test('a retry resends the same body; the files are read once', () async {
    var calls = 0;
    server.when(HttpMethod.post, '/optional').respondWith((request) async {
      if (++calls == 1) {
        throw HttpTransportException('reset', request: request);
      }
      return HttpResponse(200, body: utf8.encode('ok'), request: request);
    });
    final file = CountingFile('f', [1, 2], originalFilename: 'f.txt');
    await runner
        .withBean<Retryer>(
          () => const DefaultRetryer(
            period: Duration(milliseconds: 1),
            maxAttempts: 3,
          ),
        )
        .runAsync((context) async {
          await context.getBean<UploadClient>().optional(file, note: 'n');
          final [first, second] = server.requests;
          expect(second.body, first.body);
          expect(second.headers.contentType, first.headers.contentType);
          expect((await partsOf(second)).map((p) => p.name), ['file', 'note']);
          expect(file.reads, 1);
        });
  });

  test('wrong multipart methods fail at startup with the reason', () {
    const ApplicationContextRunner()
        .withUserConfiguration(badUploadsModule)
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
        .withBean<HttpTransport>(() => MockHttpTransport())
        .run((context) {
          final failure = '${context.startupFailure}';
          expect(failure, contains('Invalid Feign client BadUploadClient'));
          expect(
            failure,
            contains(
              'BadUploadClient.both: a multipart method takes @RequestPart '
              'parameters, not @RequestBody (book)',
            ),
          );
          expect(
            failure,
            contains(
              'BadUploadClient.json has @RequestPart parameters but consumes '
              '"application/json"',
            ),
          );
          expect(
            failure,
            contains('BadUploadClient.roles: parameter a has several roles'),
          );
        });
  });
}
