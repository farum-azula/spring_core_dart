import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);

/// A `blob:` address of [bytes] (of [contentType]) the page's players can
/// play: a resource kept in IndexedDB, played without the network.
Uri? blobUri(Uint8List bytes, String? contentType) {
  final options = JSObject();
  if (contentType != null) {
    options.setProperty('type'.toJS, contentType.toJS);
  }
  return Uri.parse(
    _createObjectUrl(_Blob(<JSAny>[bytes.toJS].toJS, options)),
  );
}
