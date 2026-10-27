// Uploads (multipart) and downloads (Resource, byte streams) through
// MockMvc: the same dispatcher a server uses, without a socket.
import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final app = springBootTest(
    testApplication,
    properties: {
      'logging.level.root': 'warn',
      'spring.servlet.multipart.max-file-size': '64KB',
      'spring.servlet.multipart.max-request-size': '256KB',
    },
  );

  group('multipart', () {
    test('a file and a text field', () async {
      await app.mockMvc
          .multipart(
            '/files/upload',
            files: [
              MockMultipartFile(
                'file',
                'notes.txt',
                'text/plain',
                utf8.encode('hello'),
              ),
            ],
            params: {'note': 'first'},
          )
          .andExpect(
            status: 200,
            json: {
              'name': 'file',
              'filename': 'notes.txt',
              'size': 5,
              'contentType': 'text/plain',
              'note': 'first',
              'text': 'hello',
            },
          );
    });

    test('several files of one field', () async {
      await app.mockMvc
          .multipart(
            '/files/many',
            files: [
              MockMultipartFile('files', 'a.bin', null, [1, 2, 3]),
              MockMultipartFile('files', 'b.bin', null, [4]),
            ],
          )
          .andExpect(json: ['a.bin:3', 'b.bin:1']);
    });

    test('a JSON part with @Valid, an optional file part', () async {
      MockMultipartFile book(Object json) => MockMultipartFile(
        'book',
        null,
        'application/json',
        utf8.encode(jsonEncode(json)),
      );
      await app.mockMvc
          .multipart(
            '/files/book',
            files: [
              book({'isbn': '9999', 'title': 'Ubik'}),
            ],
          )
          .andExpect(
            status: 200,
            json: {'title': 'Ubik', 'files': <Object?>[], 'cover': null},
          );
      await app.mockMvc
          .multipart(
            '/files/book',
            files: [
              book({'isbn': '9999', 'title': 'Ubik'}),
              MockMultipartFile('cover', 'c.png', 'image/png', [1, 2]),
            ],
          )
          .andExpect(json: containsPair('cover', 2));
      await app.mockMvc
          .multipart(
            '/files/book',
            files: [
              book({'isbn': '', 'title': ''}),
            ],
          )
          .andExpect(
            status: 400,
            json: containsPair('detail', 'Invalid request content.'),
          );
    });

    test('a missing part is a 400, not multipart is a 400', () async {
      await app.mockMvc
          .multipart('/files/upload', params: {'note': 'x'})
          .andExpect(
            status: 400,
            json: containsPair(
              'detail',
              "Required part 'file' is not present.",
            ),
          );
      await app.mockMvc
          .post('/files/upload', json: {'a': 1})
          .andExpect(status: 415);
    });

    test(
      'files above max-file-size and requests above max-request-size are 413',
      () async {
        final big = List.filled(70 * 1024, 7);
        await app.mockMvc
            .multipart(
              '/files/many',
              files: [MockMultipartFile('files', 'big.bin', null, big)],
            )
            .andExpect(status: 413);
        final medium = List.filled(60 * 1024, 7);
        await app.mockMvc
            .multipart(
              '/files/many',
              files: [
                for (var i = 0; i < 5; i++)
                  MockMultipartFile('files', '$i.bin', null, medium),
              ],
            )
            .andExpect(status: 413);
      },
    );

    test('temporary files are deleted after the request', () async {
      List<String> uploads() => [
        for (final entity in io.Directory.systemTemp.listSync())
          if (entity.path
                  .split(io.Platform.pathSeparator)
                  .last
                  .startsWith('upload_') &&
              entity.path.endsWith('.tmp'))
            entity.path,
      ];
      final before = uploads().toSet();
      await app.mockMvc
          .multipart(
            '/files/many',
            files: [
              MockMultipartFile('files', 'a.bin', null, [1, 2, 3]),
            ],
          )
          .andExpect(status: 200);
      expect(uploads().toSet().difference(before), isEmpty);
    });

    test('transferTo moves the upload to a file', () async {
      await app.mockMvc
          .multipart(
            '/files/save',
            files: [
              MockMultipartFile('file', 'x.bin', null, List.filled(1000, 1)),
            ],
          )
          .andExpect(status: 200, json: 1000);
    });
  });

  group('resources and byte streams', () {
    late io.File file;

    setUpAll(() {
      file = io.File(
        '${io.Directory.systemTemp.createTempSync('resource_test_').path}/book.txt',
      )..writeAsStringSync('0123456789');
    });

    test('ResponseEntity<Resource> with its headers', () async {
      await app.mockMvc
          .get('/files/report')
          .andExpect(
            status: 200,
            headers: {
              'Content-Type': 'text/csv',
              'Content-Disposition': 'attachment; filename="report.csv"',
              'Accept-Ranges': 'bytes',
            },
            body: 'isbn,title\n1,Dune\n',
          );
    });

    test('a FileSystemResource: type, length, Last-Modified, 304', () async {
      final result = await app.mockMvc
          .get('/files/file', params: {'path': file.path})
          .andExpect(status: 200, body: '0123456789', contentType: 'text/plain')
          .andReturn();
      final modified = result.response.headers['Last-Modified']!;
      expect(result.response.headers['Content-Length'], '10');
      await app.mockMvc
          .get(
            '/files/file',
            params: {'path': file.path},
            headers: {'If-Modified-Since': modified},
          )
          .andExpect(status: 304, body: '');
    });

    test('Range requests: 206, suffix, open end, 416, ignored lists', () async {
      Future<void> range(
        String value,
        int status,
        String body, [
        String? contentRange,
      ]) => app.mockMvc
          .get(
            '/files/file',
            params: {'path': file.path},
            headers: {'Range': value},
          )
          .andExpect(
            status: status,
            body: body,
            headers: {'Content-Range': ?contentRange},
          );
      await range('bytes=2-4', 206, '234', 'bytes 2-4/10');
      await range('bytes=-3', 206, '789', 'bytes 7-9/10');
      await range('bytes=8-', 206, '89', 'bytes 8-9/10');
      await range('bytes=5-100', 206, '56789', 'bytes 5-9/10');
      await range('bytes=20-30', 416, '', 'bytes */10');
      await range('bytes=0-1,4-5', 200, '0123456789');
      await range('items=0-1', 200, '0123456789');
    });

    test('a missing file is a 404', () async {
      await app.mockMvc
          .get('/files/file', params: {'path': '/nonexistent/x'})
          .andExpect(status: 404);
    });

    test(
      'Stream<Uint8List> is bytes, StreamingResponseBody writes itself',
      () async {
        final bytes = await app.mockMvc
            .get('/files/stream')
            .andExpect(status: 200, contentType: 'application/octet-stream')
            .andReturn();
        expect(bytes.response.bodyBytes, [1, 2, 3]);
        await app.mockMvc
            .get('/files/export')
            .andExpect(
              contentType: 'text/csv',
              body: '1,book 1\n2,book 2\n3,book 3\n',
            );
      },
    );
  });
}
