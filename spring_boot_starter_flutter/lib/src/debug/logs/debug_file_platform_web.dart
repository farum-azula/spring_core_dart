import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

/// Writes [bytes] into a Downloads folder: not in a browser.
Future<String> writeToDownloads(String fileName, Uint8List bytes) =>
    throw UnsupportedError('No Downloads folder in a browser');

/// Hands [bytes] to the browser as the download [fileName]: a `Blob` of
/// [mimeType] behind an `<a download>` clicked once, its address revoked
/// a minute later.
void browserDownload(String fileName, Uint8List bytes, String mimeType) {
  final options = JSObject()..setProperty('type'.toJS, mimeType.toJS);
  final url = _createObjectUrl(_Blob(<JSAny>[bytes.toJS].toJS, options));
  final document = globalContext.getProperty<JSObject>('document'.toJS);
  final anchor = document.callMethod<JSObject>('createElement'.toJS, 'a'.toJS)
    ..setProperty('href'.toJS, url.toJS)
    ..setProperty('download'.toJS, fileName.toJS);
  document
      .getProperty<JSObject>('body'.toJS)
      .callMethod<JSAny?>('appendChild'.toJS, anchor);
  anchor
    ..callMethod<JSAny?>('click'.toJS)
    ..callMethod<JSAny?>('remove'.toJS);
  Timer(const Duration(minutes: 1), () => _revokeObjectUrl(url));
}
