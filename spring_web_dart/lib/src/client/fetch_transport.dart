import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:spring_web_dart/src/client/address/allowed_addresses.dart';
import 'package:spring_web_dart/src/client/http_redirects.dart';
import 'package:spring_web_dart/src/client/http_request.dart';
import 'package:spring_web_dart/src/client/http_response.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/streamed_http_response.dart';
import 'package:spring_web_dart/src/http_headers.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// The [HttpTransport] for code running in a browser (Flutter web, Dart
/// compiled to JavaScript or WebAssembly), built on the browser's `fetch`
/// through `dart:js_interop`.
///
/// `platformHttpTransport()` returns one in the browser, so applications
/// rarely create it. The browser stays in charge of the request: it adds
/// cookies and its own headers, applies CORS, and has no connection
/// timeout.
///
/// How it treats an [HttpRequest]:
///
/// - Several values of one header are sent joined with `, `.
/// - Cookies go with requests to the page's own origin only, unless
///   [credentials] says otherwise ([FetchCredentials.include] for an API
///   on another origin of the same site).
/// - Redirects are followed unless `followRedirects` is `false`; then
///   `fetch` runs with `redirect: 'manual'` and the browser gives an
///   opaque response with status 0, without its `Location`.
/// - A request with a credential header (`HttpSecrets.isSensitiveHeader`
///   and its `sensitiveHeaders`) does not leave a redirect to `fetch`,
///   which keeps custom headers across origins. In an edge runtime the
///   transport follows it as `IoHttpTransport` does: another origin gets
///   no credential, `https` to `http` is not followed. A browser hides the
///   target of a redirect, so there it follows only when the browser
///   protects every credential header itself (`Authorization`, `Cookie`,
///   `Proxy-Authorization`); with any other, such as `X-Api-Key`, a
///   redirect fails with an [HttpTransportException], even to the same
///   origin, and the target gets nothing.
/// - `timeout` (the whole exchange) and `readTimeout` (each wait for
///   data) abort the request through an `AbortController`, and an
///   [HttpTransportException] with `isTimeout` is thrown.
/// - When `abort` completes before the status and headers arrive, the
///   request is aborted the same way and an [HttpTransportException] is
///   thrown.
/// - With [allowedAddresses], the URL is checked before `fetch` is
///   called: its host by name, an address literal by address (`fetch`
///   cannot resolve names, see [AllowedAddresses]). In a server runtime
///   the transport then follows every redirect itself and checks each;
///   a browser follows them by itself and never shows them, so only the
///   first URL is checked there.
/// - Non-2xx responses are ordinary responses. Network failures,
///   including a request the browser blocks for CORS, throw an
///   [HttpTransportException].
///
/// ```dart
/// import 'package:spring_web_dart/browser.dart';
///
/// // A relative URL goes to the origin that served the web app.
/// final transport = FetchHttpTransport();
/// final response = await transport.send(
///   HttpRequest(method: HttpMethod.get, url: Uri.parse('/api/books')),
/// );
/// ```
///
/// Spring (Java): no browser in Java; the closest is a
/// `ClientHttpRequestFactory` such as `JdkClientHttpRequestFactory`.
class FetchHttpTransport implements HttpTransport {
  /// A transport on `fetch`. The browser decides about connections,
  /// proxies and certificates; [credentials] says whether it sends its
  /// cookies, which a server that keeps the login in a session cookie
  /// needs when the API has another origin than the page.
  ///
  /// [allowedAddresses] limits the hosts and addresses it calls; `null`
  /// (the default) calls any.
  FetchHttpTransport({
    this.credentials = FetchCredentials.sameOrigin,
    this.allowedAddresses,
  });

  /// Whether the browser sends cookies with the requests (the
  /// `credentials` option of `fetch`).
  final FetchCredentials credentials;

  /// The hosts and addresses the transport may call, or `null` for any.
  final AllowedAddresses? allowedAddresses;

  @override
  Future<HttpResponse> send(HttpRequest request) async {
    final (response, headers, timer, abort) = await _fetchResponse(request);
    // The read timeout: the longest wait for each chunk of the body.
    final idle = _Deadline(request.readTimeout, () => abort.abort());
    try {
      final Uint8List body;
      // Reading chunk by chunk restarts the read timeout.
      final reader = request.readTimeout == null
          ? null
          : response.body?.getReader();
      if (reader == null) {
        body = (await response.arrayBuffer().toDart).toDart.asUint8List();
      } else {
        final bytes = BytesBuilder(copy: false);
        while (true) {
          final chunk = await reader.read().toDart;
          if (chunk.done) {
            break;
          }
          idle.restart();
          if (chunk.value case final value?) {
            bytes.add(value.toDart);
          }
        }
        body = bytes.takeBytes();
      }
      return HttpResponse(
        response.status,
        headers: headers,
        body: body,
        request: request,
      );
    } catch (error) {
      throw HttpTransportException(
        idle.timedOut
            ? 'no data within ${request.readTimeout!.inMilliseconds} ms '
                  '(read timeout)'
            : 'request failed: $error',
        request: request,
        cause: error,
        isTimeout: timer.timedOut || idle.timedOut,
      );
    } finally {
      timer.cancel();
      idle.cancel();
    }
  }

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    final (response, headers, timer, abort) = await _fetchResponse(request);
    // The timeouts cover the headers only.
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
        } on Object catch (error) {
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
    final wait = _Deadline(request.readTimeout, () => controller.abort());
    // The caller gave the request up (HttpRequest.abort) before the
    // response arrived; later the body's subscription aborts it.
    var aborted = false;
    var answered = false;
    unawaited(
      request.abort?.then((_) {
        if (!answered) {
          aborted = true;
          controller.abort();
        }
      }),
    );
    try {
      final followsItself = _followsItself(request);
      var method = request.method;
      var url = request.url;
      var body = request.body;
      final sent = HttpHeaders()..addHeaders(request.headers);
      late _Response response;
      for (var redirects = 0; ; redirects++) {
        allowedAddresses?.checkUrl(url);
        response = await _fetch(
          url.toString().toJS,
          _init(method, sent, body, controller.signal, followsItself),
        ).toDart;
        if (followsItself || !request.followRedirects) {
          break;
        }
        if (response.type == 'opaqueredirect') {
          throw HttpTransportException(
            'redirect not followed: the browser hides its target, and the '
            'request carries the credential headers '
            '${HttpRedirects.credentialHeaders(sent, request).join(', ')}',
            request: request,
            isRetryable: false,
          );
        }
        final next = redirects < HttpRedirects.maxRedirects
            ? HttpRedirects.next(
                method,
                url,
                response.status,
                response.headers.get('location'),
              )
            : null;
        if (next == null) {
          break;
        }
        unawaited(response.body?.cancel().toDart);
        wait.restart();
        HttpRedirects.applyHop(sent, request, url, next.url);
        if (next.method != method) {
          body = null;
          sent.remove('content-type');
        }
        method = next.method;
        url = next.url;
      }
      answered = true;
      wait.cancel();
      final responseHeaders = HttpHeaders();
      response.headers.forEach(
        ((JSString value, JSString name, JSAny? _) => responseHeaders.add(
          name.toDart,
          value.toDart,
        )).toJS,
      );
      return (response, responseHeaders, timer, controller);
    } on HttpTransportException {
      timer.cancel();
      wait.cancel();
      rethrow;
    } catch (error) {
      timer.cancel();
      wait.cancel();
      throw HttpTransportException(
        timer.timedOut
            ? 'no response within ${request.timeout!.inMilliseconds} ms'
            : wait.timedOut
            ? 'no data within ${request.readTimeout!.inMilliseconds} ms '
                  '(read timeout)'
            : aborted
            ? 'request aborted'
            : 'request failed: $error',
        request: request,
        cause: error,
        isTimeout: timer.timedOut || wait.timedOut,
      );
    }
  }

  // Whether `fetch` may follow the redirects of [request] by its own rules:
  // nothing to protect, or a browser that protects all of it.
  bool _followsItself(HttpRequest request) {
    if (!request.followRedirects) {
      return false;
    }
    // A server runtime shows its redirects: each is checked here.
    if (allowedAddresses != null && !_guardsForbiddenHeaders) {
      return false;
    }
    final credentials = HttpRedirects.credentialHeaders(
      request.headers,
      request,
    );
    return credentials.isEmpty ||
        (_guardsForbiddenHeaders &&
            credentials.every(
              (name) => _protectedByBrowser.contains(name.toLowerCase()),
            ));
  }

  _RequestInit _init(
    HttpMethod method,
    HttpHeaders sent,
    List<int>? body,
    _AbortSignal signal,
    bool followsItself,
  ) {
    final headers = JSObject();
    sent.toMap().forEach(
      (name, value) => headers.setProperty(name.toJS, value.toJS),
    );
    final redirect = (followsItself ? 'follow' : 'manual').toJS;
    return body == null
        ? _RequestInit(
            method: method.value.toJS,
            headers: headers,
            signal: signal,
            redirect: redirect,
            credentials: credentials.value.toJS,
          )
        : _RequestInit(
            method: method.value.toJS,
            headers: headers,
            body: (body is Uint8List ? body : Uint8List.fromList(body)).toJS,
            signal: signal,
            redirect: redirect,
            credentials: credentials.value.toJS,
          );
  }

  // What a browser's `fetch` removes on a redirect to another origin
  // (`Authorization`) or never lets a page set (the other two).
  static const Set<String> _protectedByBrowser = {
    'authorization',
    'cookie',
    'proxy-authorization',
  };

  // A browser's `Request` drops the forbidden header `Cookie`; the `fetch`
  // of a server runtime (Deno, workerd, Node) keeps it.
  static final bool _guardsForbiddenHeaders = () {
    try {
      final headers = JSObject()..setProperty('cookie'.toJS, 'x'.toJS);
      return !_Request(
        'http://localhost/'.toJS,
        _RequestInit(headers: headers),
      ).headers.has('cookie'.toJS);
    } on Object {
      return false;
    }
  }();

  @override
  void close() {}
}

@JS('fetch')
external JSPromise<_Response> _fetch(JSString resource, _RequestInit init);

@JS('Request')
extension type _Request._(JSObject _) implements JSObject {
  external factory _Request(JSString url, _RequestInit init);
  external _Headers get headers;
}

extension type _RequestInit._(JSObject _) implements JSObject {
  external factory _RequestInit({
    JSString method,
    JSObject headers,
    JSAny body,
    _AbortSignal signal,
    JSString redirect,
    JSString credentials,
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
  external String get type;
  external _Headers get headers;
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
  external JSPromise<JSAny?> cancel();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

/// A timer that aborts a request when its timeout runs out. With a `null`
/// timeout it never fires.
final class _Deadline {
  _Deadline(this._timeout, this._abort) {
    restart();
  }

  final Duration? _timeout;
  final void Function() _abort;
  Timer? _timer;

  /// Whether the timeout ran out and the request was aborted.
  bool timedOut = false;

  /// Starts the timeout again from now: for an idle timeout, when data
  /// arrived. Does nothing once it has run out.
  void restart() {
    final timeout = _timeout;
    _timer?.cancel();
    if (timeout != null && !timedOut) {
      _timer = Timer(timeout, () {
        timedOut = true;
        _abort();
      });
    }
  }

  void cancel() => _timer?.cancel();
}

extension type _Headers._(JSObject _) implements JSObject {
  external void forEach(JSFunction callback);
  external bool has(JSString name);
  external String? get(String name);
}
