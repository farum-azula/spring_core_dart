import 'dart:async';
import 'dart:typed_data';

/// A request as a fetch platform hands it to the function: what a
/// JavaScript `Request` holds, in Dart.
///
/// The platform's entry makes one from its `Request` (or, on AWS Lambda,
/// from the event); a test makes one itself and gives it to
/// `FetchApplication.fetch`.
///
/// ```dart
/// final response = await application.fetch(
///   FetchRequest('GET', Uri.parse('https://example.com/books?page=2')),
/// );
/// ```
final class FetchRequest {
  /// A [method] request for [uri] (absolute, still percent-encoded) with
  /// [headers] as name and value pairs, a name once for each of its
  /// values.
  const FetchRequest(
    this.method,
    this.uri, {
    this.headers = const [],
    this.body,
    this.context = const FetchContext(),
  });

  /// The method as it was sent: `GET`, `POST`.
  final String method;

  /// The address the client asked for.
  final Uri uri;

  /// The headers, a pair for every value.
  final List<(String, String)> headers;

  /// The body as it arrives; `null` for a request without one.
  final Stream<Uint8List>? body;

  /// What the platform says about this request besides HTTP.
  final FetchContext context;
}

/// What a platform gives with a request besides the request itself: who
/// sent it, and how to keep working after the answer.
///
/// - Supabase Edge Functions: `EdgeRuntime.waitUntil`; the address of the
///   connection, which is the platform's gateway.
/// - Cloudflare Workers: `ctx.waitUntil`; the address of the client from
///   `CF-Connecting-IP`, which Cloudflare sets itself.
/// - AWS Lambda: the entry waits for the work before it ends the
///   invocation; the client's address from the event (`sourceIp`).
final class FetchContext {
  /// The context of one request on [platform].
  const FetchContext({this.platform, this.remoteAddress, this.waitUntil});

  /// `supabase`, `cloudflare`, `aws`; `null` in a test.
  final String? platform;

  /// The address the platform names as the sender of the request, when it
  /// names one it stands for itself; never read from a header a client
  /// can set.
  final String? remoteAddress;

  /// Tells the platform to keep the instance until the work ends, after
  /// the response was sent; `null` where the platform has no such call.
  final void Function(Future<void> work)? waitUntil;
}

/// The answer of the function: what goes into a JavaScript `Response`.
///
/// Either [bytes] (the whole body, the usual case) or [stream] (an event
/// stream, a download: the body is sent while it is produced), or neither
/// for an answer without a body.
final class FetchResponse {
  /// An answer with [status] and [headers] (a pair for every value).
  const FetchResponse(
    this.status,
    this.headers, {
    this.bytes,
    this.stream,
  }) : assert(
         bytes == null || stream == null,
         'A response has its body once',
       );

  /// The status code, 200 to 599.
  final int status;

  /// The headers, a pair for every value (`Set-Cookie` once per cookie).
  final List<(String, String)> headers;

  /// The whole body, when it was complete before the answer went out.
  final Uint8List? bytes;

  /// The body as it is produced. An error in it means the answer broke
  /// after its status was sent: the platform cuts the response.
  final Stream<Uint8List>? stream;

  /// The first value of the header [name], whatever its case.
  String? header(String name) {
    final wanted = name.toLowerCase();
    for (final (key, value) in headers) {
      if (key.toLowerCase() == wanted) {
        return value;
      }
    }
    return null;
  }

  /// The whole body, read to its end: [bytes], or everything [stream]
  /// gives.
  Future<Uint8List> readBytes() async {
    if (bytes case final all?) {
      return all;
    }
    final source = stream;
    if (source == null) {
      return Uint8List(0);
    }
    final builder = BytesBuilder(copy: false);
    await source.forEach(builder.add);
    return builder.takeBytes();
  }
}
