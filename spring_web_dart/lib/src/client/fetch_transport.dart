import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
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
    final (response, headers, timer, _) = await _fetchResponse(request);
    try {
      final buffer = await response.arrayBuffer().toDart;
      return HttpResponse(
        response.status,
        headers: headers,
        body: buffer.toDart.asUint8List(),
        request: request,
      );
    } catch (error) {
      throw HttpTransportException(
        'request failed: $error',
        request: request,
        cause: error,
        isTimeout: timer.timedOut,
      );
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    final (response, headers, timer, abort) = await _fetchResponse(request);
    // The timeout covers the headers only.
    timer.cancel();
    final reader = response.body?.getReader();
    var cancelled = false;
    late final StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () async {
        try {
          while (reader != null && !cancelled) {
            final chunk = await reader.read().toDart;
            if (chunk.done) {
              break;
            }
            final value = chunk.value;
            if (value != null && !cancelled) {
              body.add(value.toDart);
            }
          }
        } catch (error) {
          if (!cancelled) {
            body.addError(
              HttpTransportException(
                'response broke: $error',
                request: request,
                cause: error,
              ),
            );
          }
        }
        if (!cancelled) {
          await body.close();
        }
      },
      onCancel: () {
        cancelled = true;
        abort.abort();
      },
    );
    return StreamedHttpResponse(
      response.status,
      headers: headers,
      body: body.stream,
      request: request,
    );
  }

  // Starts [request]; returns when the status and headers have arrived.
  Future<(_Response, HttpHeaders, _Deadline, _AbortController)> _fetchResponse(
    HttpRequest request,
  ) async {
    final controller = _AbortController();
    final timer = _Deadline(request.timeout, () => controller.abort());
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
      return (response, responseHeaders, timer, controller);
    } catch (error) {
      timer.cancel();
      final timeout = request.timeout;
      throw HttpTransportException(
        timer.timedOut
            ? 'no response within ${timeout!.inMilliseconds} ms'
            : 'request failed: $error',
        request: request,
        cause: error,
        isTimeout: timer.timedOut,
      );
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
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

/// Aborts a request when its timeout runs out.
final class _Deadline {
  _Deadline(Duration? timeout, void Function() abort) {
    if (timeout != null) {
      _timer = Timer(timeout, () {
        timedOut = true;
        abort();
      });
    }
  }

  Timer? _timer;

  /// Whether the timeout ran out.
  bool timedOut = false;

  void cancel() => _timer?.cancel();
}

extension type _Headers._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
}
