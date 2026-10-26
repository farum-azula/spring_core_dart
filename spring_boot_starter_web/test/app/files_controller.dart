import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'models.dart';

class Upload {
  const Upload({
    required this.name,
    required this.filename,
    required this.size,
    required this.contentType,
    required this.note,
    required this.text,
  });

  final String name;
  final String? filename;
  final int size;
  final String? contentType;
  final String note;
  final String text;
}

class Stored {
  const Stored({required this.title, required this.files, this.cover});

  final String title;
  final List<String> files;
  final int? cover;
}

@RestController()
@RequestMapping('/files')
class FilesController {
  @PostMapping.of(path: '/upload', consumes: MediaType.multipartFormData)
  Future<Upload> upload(
    @RequestPart('file') MultipartFile file,
    @RequestParam('note') String note,
  ) async => Upload(
    name: file.name,
    filename: file.originalFilename,
    size: file.size,
    contentType: file.contentType,
    note: note,
    text: utf8.decode(await file.bytes, allowMalformed: true),
  );

  @PostMapping('/many')
  Future<List<String>> many(
    @RequestPart('files') List<MultipartFile> files,
  ) async => [
    for (final file in files) '${file.originalFilename}:${file.size}',
  ];

  @PostMapping('/book')
  Stored book(
    @RequestPart('book') @Valid() NewBook book, {
    @RequestPart.of(name: 'cover', required: false) MultipartFile? cover,
  }) => Stored(title: book.title, files: const [], cover: cover?.size);

  @PostMapping('/save')
  Future<int> save(@RequestPart('file') MultipartFile file) async {
    final target =
        '${io.Directory.systemTemp.createTempSync('upload_test_').path}/saved.bin';
    await file.transferTo(target);
    return io.File(target).lengthSync();
  }

  @GetMapping('/report')
  ResponseEntity<Resource> report() =>
      ResponseEntity.ok(
        ByteArrayResource(
          Uint8List.fromList(utf8.encode('isbn,title\n1,Dune\n')),
        ) as Resource,
      ).copyWithHeaders({
        'Content-Type': 'text/csv',
        'Content-Disposition': 'attachment; filename="report.csv"',
      });

  @GetMapping('/file')
  Resource file(@RequestParam('path') String path) => FileSystemResource(path);

  @GetMapping('/stream')
  Stream<Uint8List> stream() => Stream.fromIterable([
    Uint8List.fromList([1, 2]),
    Uint8List.fromList([3]),
  ]);

  @GetMapping.of(path: '/export', produces: 'text/csv')
  StreamingResponseBody export() => StreamingResponseBody((out) async {
    for (var i = 1; i <= 3; i++) {
      out.write('$i,book $i\n');
      await out.flush();
    }
  });
}

extension on ResponseEntity<Resource> {
  ResponseEntity<Resource> copyWithHeaders(Map<String, String> values) {
    final headers = HttpHeaders();
    values.forEach(headers.set);
    return ResponseEntity<Resource>(statusCode, body: body, headers: headers);
  }
}
