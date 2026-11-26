import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart' as path_provider;

/// Writes [bytes] as [fileName] into the user's Downloads folder
/// (`path_provider`'s `getDownloadsDirectory`) and returns its path. A
/// file of that name already there is kept: the new one gets `-2`, `-3`
/// before its extension.
Future<String> writeToDownloads(String fileName, Uint8List bytes) async {
  final directory = await path_provider.getDownloadsDirectory();
  if (directory == null) {
    throw StateError('This platform has no Downloads folder');
  }
  await directory.create(recursive: true);
  final dot = fileName.lastIndexOf('.');
  final stem = dot < 0 ? fileName : fileName.substring(0, dot);
  final extension = dot < 0 ? '' : fileName.substring(dot);
  var file = File('${directory.path}${Platform.pathSeparator}$fileName');
  for (var n = 2; file.existsSync(); n++) {
    file = File('${directory.path}${Platform.pathSeparator}$stem-$n$extension');
  }
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Hands [bytes] to the browser as a download: not outside a browser.
void browserDownload(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('No browser here');
