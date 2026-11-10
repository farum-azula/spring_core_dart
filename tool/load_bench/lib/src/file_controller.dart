// Scenarios "download-*" and "upload-*": files streamed from and to
// disk. Neither direction holds a body in memory, which the report
// shows with the server's memory.
import 'dart:io';

import 'package:load_bench/src/bench_files.dart';
import 'package:load_bench/src/bench_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
class FileController {
  FileController(this._files, this._properties);

  final BenchFiles _files;
  final BenchProperties _properties;

  /// `GET /files/small`, `/files/medium`, `/files/huge`: a `Resource`,
  /// streamed from the file; a `Range` header gets a 206 with that part.
  @GetMapping('/files/{name:small|medium|huge}')
  Resource download(@PathVariable() String name) =>
      FileSystemResource(_files.path(name));

  /// `POST /upload/multipart`: `multipart/form-data` with the file in the
  /// part `file`. The resolver streams it to a temporary file, which is
  /// deleted when the request ends.
  @PostMapping('/upload/multipart')
  Uploaded multipart(@RequestPart('file') MultipartFile file) =>
      Uploaded(file.size);

  /// `PUT /upload/raw`: the body as it is, piped to a file as it arrives
  /// and deleted once counted. `bench.upload.max-size` is its limit.
  @PutMapping('/upload/raw')
  Future<Uploaded> raw(ServerHttpRequest request) async {
    request.attributes[maxRequestBodySizeAttribute] = _properties.upload.maxSize
        .toBytes();
    final file = File(_files.newUpload());
    try {
      await request.body.cast<List<int>>().pipe(file.openWrite());
      return Uploaded(await file.length());
    } finally {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }
}

/// The answer of an upload: the bytes the server received.
class Uploaded {
  const Uploaded(this.bytes);

  final int bytes;
}
