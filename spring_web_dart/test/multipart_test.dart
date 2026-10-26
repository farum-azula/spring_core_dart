import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

Future<List<(MultipartPart, Uint8List)>> _parse(
  Uint8List body,
  String boundary, {
  int chunk = 1 << 20,
}) async {
  final chunks = [
    for (var i = 0; i < body.length; i += chunk)
      body.sublist(i, min(i + chunk, body.length)),
  ];
  final result = <(MultipartPart, Uint8List)>[];
  await for (final part in MultipartParser(
    boundary,
  ).bind(Stream.fromIterable(chunks))) {
    final bytes = BytesBuilder();
    await part.content.forEach(bytes.add);
    result.add((part, bytes.takeBytes()));
  }
  return result;
}

void main() {
  final binary = Uint8List.fromList([
    for (var i = 0; i < 5000; i++) i % 256,
    // Bytes that look like a boundary start.
    ...ascii.encode('\r\n--not-the-boundary\r\n'),
    13, 10, 45,
  ]);

  final body = MultipartBody([
    MultipartBodyPart.field('title', 'Dune'),
    MultipartBodyPart.field('note', 'línea\r\ndos'),
    MultipartBodyPart.file('cover', binary, filename: 'dune.png'),
    MultipartBodyPart.json('meta', '{"pages":412}'),
    MultipartBodyPart.file('empty', const [], filename: 'empty.txt'),
  ], boundary: 'XyZ-boundary');

  for (final chunk in [1, 2, 7, 64, 1 << 20]) {
    test('round trip in chunks of $chunk bytes', () async {
      final parts = await _parse(body.encode(), body.boundary, chunk: chunk);
      expect(parts.map((p) => p.$1.name), [
        'title',
        'note',
        'cover',
        'meta',
        'empty',
      ]);
      expect(utf8.decode(parts[0].$2), 'Dune');
      expect(utf8.decode(parts[1].$2), 'línea\r\ndos');
      expect(parts[2].$1.filename, 'dune.png');
      expect(parts[2].$1.headers.contentType, 'image/png');
      expect(parts[2].$2, binary);
      expect(parts[3].$1.headers.contentType, 'application/json');
      expect(parts[4].$2, isEmpty);
      expect(parts[4].$1.isFile, isTrue);
      expect(parts[0].$1.isFile, isFalse);
    });
  }

  test('a preamble and an epilogue are ignored', () async {
    final text =
        'preamble\r\n--b\r\nContent-Disposition: form-data; name="a"\r\n\r\n1\r\n--b--\r\nepilogue';
    final parts = await _parse(utf8.encode(text), 'b');
    expect(parts.single.$1.name, 'a');
    expect(utf8.decode(parts.single.$2), '1');
  });

  test('malformed bodies fail', () async {
    expect(
      _parse(utf8.encode('no boundary here'), 'b'),
      throwsA(isA<MultipartException>()),
    );
    expect(
      _parse(
        utf8.encode(
          '--b\r\nContent-Disposition: form-data; name="a"\r\n\r\nunfinished',
        ),
        'b',
      ),
      throwsA(isA<MultipartException>()),
    );
    expect(
      _parse(utf8.encode('--b\r\nbroken header\r\n\r\nx\r\n--b--'), 'b'),
      throwsA(isA<MultipartException>()),
    );
  });

  test('the boundary of a Content-Type', () {
    expect(
      MultipartParser.boundaryOf(MediaType.parse(body.contentType)),
      'XyZ-boundary',
    );
    expect(
      MultipartParser.boundaryOf(MediaType.parse('application/json')),
      isNull,
    );
  });

  test('MediaTypeFactory', () {
    expect(MediaTypeFactory.getMediaType('a/b/c.PNG'), 'image/png');
    expect(MediaTypeFactory.getMediaType('noext'), isNull);
  });
}
