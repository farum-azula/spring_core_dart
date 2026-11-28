import 'dart:io';

import 'package:spring_web_dart/src/client/streaming_body.dart';

/// The body of the file at [path] (opened again for each attempt, its
/// length read now) and its name, for `MultipartBodyPart.fromPath`.
/// Throws a [FileSystemException] when the file cannot be read.
({StreamingBody body, String filename}) fileSource(String path) {
  final file = File(path);
  return (
    body: StreamingBody.repeatable(file.openRead, length: file.lengthSync()),
    filename: file.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
      orElse: () => path,
    ),
  );
}
