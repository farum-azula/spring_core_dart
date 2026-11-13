import 'dart:typed_data';

import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show
        AbstractResource,
        HttpMethod,
        HttpRequest,
        HttpTransport,
        platformHttpTransport;

/// A model's file at an address (`https://cdn.example.com/hero.glb`),
/// read with one GET: in a browser too, where the framework's own
/// `UrlResource` cannot read (it needs `dart:io`).
///
/// Only `https`, and `http` with [allowInsecure]
/// (`spring.remote.allow-insecure`). The request goes through the app's
/// `HttpTransport` bean when it has one, else the platform's. In a
/// browser the server must allow the page's origin (CORS), as for any
/// request of the page to another origin.
final class RemoteModelResource extends AbstractResource {
  /// The file at [url].
  RemoteModelResource(this.url, {this.transport, this.allowInsecure = false});

  /// Where the file is.
  final Uri url;

  /// The HTTP client; the platform's when `null`.
  final HttpTransport? transport;

  /// Whether `http` is accepted.
  final bool allowInsecure;

  @override
  String get description => 'model [$url]';

  /// Always `true`: the server is asked only when the file is read.
  @override
  bool exists() => true;

  @override
  Future<Uint8List> readAsBytes() async {
    if (url.scheme != 'https' && !(allowInsecure && url.scheme == 'http')) {
      throw StateError(
        'The model at $url is not read: only https is '
        '(http too with spring.remote.allow-insecure=true).',
      );
    }
    final own = transport == null ? platformHttpTransport() : null;
    try {
      final response = await (transport ?? own!).send(
        HttpRequest(method: HttpMethod.get, url: url),
      );
      if (!response.statusCode.is2xxSuccessful) {
        throw StateError(
          'The model at $url was not read: the server answered '
          '${response.statusCode.value}.',
        );
      }
      return response.bodyBytes;
    } finally {
      own?.close();
    }
  }

  @override
  Uint8List readAsBytesSync() => throw UnsupportedError(
    'The model at $url is read from the network: asynchronously only.',
  );
}
