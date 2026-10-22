import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/http_headers.dart';

/// An [HttpTransport] on the browser's `fetch` (Flutter web, Dart on the
/// web), through `dart:js_interop`. Follows redirects; the request's
/// timeout aborts the request (`AbortController`). Non-2xx responses are
/// ordinary responses; network failures (also CORS) throw
/// [HttpTransportException].
///
/// ```dart
/// import 'package:spring_web_dart/browser.dart';
///
/// final transport = FetchHttpTransport();
/// final response = await transport.send(
///   HttpRequest(method: HttpMethod.get, url: Uri.parse('/api/books')),
/// );
/// ```
///
/// Spring (Java): no browser in Java; the closest is a
/// `ClientHttpRequestFactory` such as `JdkClientHttpRequestFactory`.
class FetchHttpTransport implements HttpTransport {
  /// A transport on `fetch`.
  FetchHttpTransport();

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final controller = _AbortController();
    var timedOut = false;
    final timeout = request.timeout;
    final timer = timeout == null
        ? null
        : Timer(timeout, () {
            timedOut = true;
            controller.abort();
          });
    try {
      final headers = JSObject();
      request.headers.toMap().forEach(
        (name, value) => headers.setProperty(name.toJS, value.toJS),
      );
      final body = request.body;
      final init = body == null
          ? _RequestInit(
              method: request.method.value.toJS,
              headers: headers,
              signal: controller.signal,
            )
          : _RequestInit(
              method: request.method.value.toJS,
              headers: headers,
              body: (body is Uint8List ? body : Uint8List.fromList(body)).toJS,
              signal: controller.signal,
            );
      final response = await _fetch(request.url.toString().toJS, init).toDart;
      final responseHeaders = HttpHeaders();
      response.headers.forEach(
        ((JSString value, JSString name, JSAny? _) => responseHeaders.add(
          name.toDart,
          value.toDart,
        )).toJS,
      );
      final buffer = await response.arrayBuffer().toDart;
      return HttpResponse(
        response.status,
        headers: responseHeaders,
        body: buffer.toDart.asUint8List(),
        request: request,
      );
    } on HttpTransportException {
      rethrow;
    } catch (error) {
      throw HttpTransportException(
        timedOut
            ? 'no response within ${timeout!.inMilliseconds} ms'
            : 'request failed: $error',
        request: request,
        cause: error,
        isTimeout: timedOut,
      );
    } finally {
      timer?.cancel();
    }
  }

  @override
  void close() {}
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString resource, _RequestInit init);

extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({
    JSString method,
    JSObject headers,
    JSAny body,
    _AbortSignal signal,
  });
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external _AbortSignal get signal;
  external void abort();
}

extension type _AbortSignal._(JSObject _) implements JSObject {}

extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external _Headers get headers;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Headers._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}
