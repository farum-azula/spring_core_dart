// Uploads and downloads over a real socket (dart:io): a large upload that
// goes to a temporary file, a streamed file with a Range request.
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final app = springBootTest(
    testApplication,
    webEnvironment: WebEnvironment.randomPort,
    properties: {
      'logging.level.root': 'warn',
      'server.address': '127.0.0.1',
      'spring.servlet.multipart.max-file-size': '20MB',
      'spring.servlet.multipart.max-request-size': '20MB',
      'spring.servlet.multipart.file-size-threshold': '1KB',
    },
  );

  Uri uri(String path) =>
      Uri.parse('http://127.0.0.1:${app.localServerPort}$path');

  test(
    'a 12 MB upload, above the server body limit, through a temporary file',
    () async {
      final content = List.generate(12 * 1024 * 1024, (i) => i % 251);
      final body = MultipartBody([
        MultipartBodyPart.file('file', content, filename: 'big.bin'),
      ]);
      final client = io.HttpClient();
      try {
        final request = await client.postUrl(uri('/files/save'));
        request.headers.set('Content-Type', body.contentType);
        request.add(body.encode());
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(await utf8.decodeStream(response), '${content.length}');
      } finally {
        client.close(force: true);
      }
    },
  );

  test('a file download with a Range request', () async {
    final file = io.File(
      '${io.Directory.systemTemp.createTempSync('range_').path}/a.txt',
    )..writeAsStringSync('abcdefghij');
    final client = io.HttpClient();
    try {
      final request = await client.getUrl(
        uri('/files/file?path=${Uri.encodeQueryComponent(file.path)}'),
      );
      request.headers.set('Range', 'bytes=3-5');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.headers.value('content-range'), 'bytes 3-5/10');
      expect(await utf8.decodeStream(response), 'def');
    } finally {
      client.close(force: true);
    }
  });
}
