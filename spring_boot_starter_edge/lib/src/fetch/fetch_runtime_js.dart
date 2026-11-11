import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_edge/src/edge_scheduled.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_application.dart';
import 'package:spring_boot_starter_edge/src/fetch/fetch_exchange.dart';
import 'package:spring_boot_starter_edge/src/fetch/platform_environment_js.dart';

/// On a JavaScript runtime: gives the platform's entry file the handler,
/// as `globalThis.__springEdge`:
///
/// - `fetch(request, env, context)`: a `Promise` of the `Response` to a
///   `Request`; `env` is an object of the environment variables,
///   `context` an object with `platform`, `remoteAddress` and
///   `waitUntil(promise)`, all optional;
/// - `start(env, context)`: starts the context before the first request,
///   where the platform has its environment when the instance loads;
/// - `scheduled(event, env, context)`: the platform ran the function by a
///   schedule; `event` has `schedule` (a text) and `time` (milliseconds
///   since 1970), both optional. The `Promise` fails when a handler did.
///
/// Nothing starts here: a platform may forbid timers and requests while
/// it loads the script.
void startFetchApplication(
  SpringApplication Function() application,
  Map<String, Object?> properties,
) {
  FetchApplication? function;
  FetchApplication of(_Context? context) => function ??= FetchApplication(
    application,
    runtime: context?.platform ?? 'fetch',
    properties: properties,
  );

  _global['__springEdge'] = _Handler(
    fetch: ((_Request request, JSObject? env, _Context? context) {
      return _answer(of(context), request, env, context).toJS;
    }).toJS,
    scheduled: ((_Scheduled? event, JSObject? env, _Context? context) {
      platformEnvironment = env ?? platformEnvironment;
      final time = event?.time;
      return of(context)
          .scheduled(
            EdgeScheduledEvent(
              time: time == null
                  ? DateTime.now().toUtc()
                  : DateTime.fromMillisecondsSinceEpoch(
                      time.toInt(),
                      isUtc: true,
                    ),
              schedule: event?.schedule,
              platform: context?.platform,
            ),
            environment: _environment(env),
          )
          .then<JSAny?>((_) => null)
          .toJS;
    }).toJS,
    start: ((JSObject? env, _Context? context) {
      platformEnvironment = env ?? platformEnvironment;
      return of(context)
          .start(environment: _environment(env))
          .then<JSAny?>((_) => null)
          .toJS;
    }).toJS,
  );
}

Future<_Response> _answer(
  FetchApplication function,
  _Request request,
  JSObject? env,
  _Context? context,
) async {
  platformEnvironment = env ?? platformEnvironment;
  final FetchRequest incoming;
  try {
    incoming = _request(request, context);
  } on FormatException {
    return _response(
      FetchResponse(400, const [
        ('content-type', 'application/problem+json'),
      ], bytes: utf8.encode('{"title":"Bad Request","status":400}')),
    );
  }
  return _response(
    await function.fetch(incoming, environment: _environment(env)),
  );
}

// The string values of the platform's environment object; a Worker's
// bindings that are objects (KV, D1) are not properties.
Map<String, String> _environment(JSObject? env) {
  if (env == null) {
    return const {};
  }
  final values = <String, String>{};
  for (final key in _keys(env).toDart) {
    final value = env.getProperty<JSAny?>(key);
    if (value.isA<JSString>()) {
      values[key.toDart] = (value! as JSString).toDart;
    }
  }
  return values;
}

FetchRequest _request(_Request request, _Context? context) {
  final headers = <(String, String)>[];
  request.headers.forEach(
    ((JSString value, JSString name) {
      headers.add((name.toDart, value.toDart));
    }).toJS,
  );
  final body = request.body;
  final waitUntil = context?.waitUntil;
  return FetchRequest(
    request.method,
    Uri.parse(request.url),
    headers: headers,
    body: body == null ? null : _read(body),
    context: FetchContext(
      platform: context?.platform,
      remoteAddress: context?.remoteAddress,
      waitUntil: waitUntil == null
          ? null
          : (work) => waitUntil.callAsFunction(
              null,
              work.then<JSAny?>((_) => null).toJS,
            ),
    ),
  );
}

// The body of the request, read from the platform only while someone
// listens.
Stream<Uint8List> _read(_ReadableStream body) async* {
  final reader = body.getReader();
  try {
    while (true) {
      final chunk = await reader.read().toDart;
      if (chunk.done) {
        break;
      }
      final value = chunk.value;
      if (value != null) {
        yield value.toDart;
      }
    }
  } finally {
    // After the end it does nothing; before it, the rest is not wanted.
    reader.cancel().toDart.ignore();
  }
}

_Response _response(FetchResponse response) {
  final headers = _Headers();
  for (final (name, value) in response.headers) {
    headers.append(name, value);
  }
  final JSAny? body;
  if (response.bytes case final bytes?) {
    body = bytes.toJS;
  } else if (response.stream case final stream?) {
    body = _stream(stream);
  } else {
    body = null;
  }
  return _Response(
    body,
    _ResponseInit(status: response.status, headers: headers),
  );
}

// A JavaScript stream that asks the Dart one for a chunk when the
// platform wants one, so a slow client holds the writer back.
_ReadableStream _stream(Stream<Uint8List> stream) {
  final iterator = StreamIterator(stream);
  return _ReadableStream(
    _Source(
      pull: ((_Controller controller) {
        return () async {
          try {
            if (await iterator.moveNext()) {
              controller.enqueue(iterator.current.toJS);
            } else {
              controller.close();
            }
          } on Object catch (error) {
            // The response breaks; the reason stays in the log.
            controller.error('$error'.toJS);
          }
        }().then<JSAny?>((_) => null).toJS;
      }).toJS,
      cancel: ((JSAny? reason) {
        return iterator.cancel().then<JSAny?>((_) => null).toJS;
      }).toJS,
    ),
  );
}

@JS('globalThis')
external JSObject get _global;

@JS('Object.keys')
external JSArray<JSString> _keys(JSObject object);

extension type _Handler._(JSObject _) implements JSObject {
  external factory _Handler({
    JSFunction fetch,
    JSFunction start,
    JSFunction scheduled,
  });
}

extension type _Scheduled._(JSObject _) implements JSObject {
  external String? get schedule;
  external double? get time;
}

extension type _Context._(JSObject _) implements JSObject {
  external String? get platform;
  external String? get remoteAddress;
  external JSFunction? get waitUntil;
}

extension type _Request._(JSObject _) implements JSObject {
  external String get method;
  external String get url;
  external _Headers get headers;
  external _ReadableStream? get body;
}

@JS('Headers')
extension type _Headers._(JSObject _) implements JSObject {
  external factory _Headers();
  external void forEach(JSFunction callback);
  external void append(String name, String value);
}

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body, _ResponseInit init);
}

extension type _ResponseInit._(JSObject _) implements JSObject {
  external factory _ResponseInit({int status, _Headers headers});
}

@JS('ReadableStream')
extension type _ReadableStream._(JSObject _) implements JSObject {
  external factory _ReadableStream(_Source source);
  external _Reader getReader();
}

extension type _Source._(JSObject _) implements JSObject {
  external factory _Source({JSFunction pull, JSFunction cancel});
}

extension type _Controller._(JSObject _) implements JSObject {
  external void enqueue(JSUint8Array chunk);
  external void close();
  external void error(JSAny? reason);
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_ReadResult> read();
  external JSPromise<JSAny?> cancel();
}

extension type _ReadResult._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}
