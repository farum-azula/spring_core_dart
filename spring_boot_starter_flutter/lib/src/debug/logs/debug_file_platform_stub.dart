import 'dart:typed_data';

/// Writes [bytes] as [fileName] into the user's Downloads folder and
/// returns its path: not without dart:io.
Future<String> writeToDownloads(String fileName, Uint8List bytes) =>
    throw UnsupportedError('No Downloads folder here');

/// Hands [bytes] to the browser as the download [fileName]: not outside a
/// browser.
void browserDownload(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('No browser here');
