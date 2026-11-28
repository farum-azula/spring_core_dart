import 'package:spring_web_dart/src/client/streaming_body.dart';

/// The body of the file at [path] and its name, for
/// `MultipartBodyPart.fromPath`: without `dart:io` there is no file.
({StreamingBody body, String filename}) fileSource(String path) =>
    throw UnsupportedError(
      'MultipartBodyPart.fromPath reads a file on disk and needs dart:io; '
      'in a browser or an edge runtime send the content with '
      'MultipartBodyPart.stream or MultipartBodyPart.file',
    );
