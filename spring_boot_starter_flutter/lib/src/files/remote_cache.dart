import 'dart:async';
import 'dart:typed_data';

import 'package:spring_web_dart/spring_web_dart.dart'
    show
        HttpHeaders,
        HttpMethod,
        HttpRequest,
        HttpTransport,
        platformHttpTransport;

/// A downloaded file: its [bytes] and the response [headers].
///
/// Internal to the starter.
typedef RemoteFile = ({Uint8List bytes, HttpHeaders headers});

/// Downloads files for the starter's caches (the theme from a URL, images
/// from the network): GET with the request headers, redirects followed by
/// hand, a size limit, a timeout, and `null` for a `304 Not Modified`.
///
/// Only `https` is followed, `http` too when [get] is told so. The HTTP
/// client is [transport], else the platform's, made on the first request
/// and closed by [close].
///
/// Internal to the starter.
final class RemoteFetcher {
  /// A fetcher with the limits [timeout] and [maxBytes]; [transport] is
  /// the client to use (not closed by [close]).
  RemoteFetcher({
    HttpTransport? transport,
    required this.timeout,
    required this.maxBytes,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _transport = transport;

  /// The longest a request may take.
  final Duration timeout;

  /// The most bytes a file may have.
  final int maxBytes;

  static final _conditional = {
    HttpHeaders.ifNoneMatchHeader.toLowerCase(),
    HttpHeaders.ifModifiedSinceHeader.toLowerCase(),
  };

  HttpTransport? _transport;
  bool _ownsTransport = false;

  HttpTransport get _http {
    if (_transport == null) {
      _transport = platformHttpTransport(connectTimeout: timeout);
      _ownsTransport = true;
    }
    return _transport!;
  }

  /// The response to a GET of [uri] with [headers] (and `Accept:
  /// [accept]`), or `null` for a 304. Throws a `StateError` for another
  /// status, a redirect to a scheme that is not allowed, a file over
  /// [maxBytes] or too many redirects.
  Future<RemoteFile?> get(
    Uri uri,
    Map<String, String> headers, {
    required String accept,
    bool allowHttp = false,
    Duration? timeout,
  }) async {
    final limit = timeout ?? this.timeout;
    var current = uri;
    for (var hops = 0; hops <= 5; hops++) {
      final sameOrigin =
          current.scheme == uri.scheme &&
          current.host == uri.host &&
          current.port == uri.port;
      final response = await _http.stream(
        HttpRequest(
          method: HttpMethod.get,
          url: current,
          headers: HttpHeaders({
            HttpHeaders.acceptHeader: accept,
            // Credentials do not follow a redirect to another origin (host,
            // port or scheme: no https to http downgrade either).
            for (final MapEntry(:key, :value) in headers.entries)
              if (sameOrigin || _conditional.contains(key.toLowerCase()))
                key: value,
          }),
          timeout: limit,
          readTimeout: limit,
          followRedirects: false,
        ),
      );
      final status = response.statusCode;
      if (status == 304) {
        await response.body.drain<void>();
        return null;
      }
      if (const {301, 302, 303, 307, 308}.contains(status.value)) {
        await response.body.drain<void>();
        final location = response.headers[HttpHeaders.locationHeader];
        final next = location == null ? null : current.resolve(location);
        if (next == null ||
            !(next.scheme == 'https' || (allowHttp && next.scheme == 'http'))) {
          throw StateError(
            'redirected to ${location ?? 'nowhere'}, not '
            '${allowHttp ? 'http(s)' : 'https'}',
          );
        }
        current = next;
        continue;
      }
      if (status.value < 200 || status.value > 299) {
        await response.body.drain<void>();
        throw StateError('the server answered $status');
      }
      final length = int.tryParse(
        response.headers[HttpHeaders.contentLengthHeader] ?? '',
      );
      if (length != null && length > maxBytes) {
        await response.body.drain<void>();
        throw StateError('the file is $length bytes; the limit is $maxBytes');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.body) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw StateError('the file is over the limit of $maxBytes bytes');
        }
      }
      return (bytes: builder.takeBytes(), headers: response.headers);
    }
    throw StateError('too many redirects');
  }

  /// Closes the HTTP client if the fetcher made it.
  void close() {
    if (_ownsTransport) {
      _transport?.close();
      _transport = null;
      _ownsTransport = false;
    }
  }
}

/// What `meta.json` of a cache folder remembers about the file: where it
/// came from, its digest, when it was fetched and the validators of the
/// conditional request (`ETag`, `Last-Modified`).
///
/// Internal to the starter.
final class RemoteMeta {
  /// The meta of a file from [source] with [sha256], fetched at
  /// [fetchedAt].
  const RemoteMeta({
    required this.source,
    required this.sha256,
    required this.fetchedAt,
    this.etag,
    this.lastModified,
  });

  /// The meta in [json] (decoded `meta.json`).
  factory RemoteMeta.fromJson(Object? json) {
    final map = json as Map<String, Object?>;
    return RemoteMeta(
      source: map['source']! as String,
      sha256: map['sha256']! as String,
      fetchedAt: DateTime.parse(map['fetchedAt']! as String),
      etag: map['etag'] as String?,
      lastModified: map['lastModified'] as String?,
    );
  }

  /// The `source` as configured.
  final String source;

  /// The digest of the cached file.
  final String sha256;

  /// When the file was last fetched or confirmed current.
  final DateTime fetchedAt;

  /// The `ETag` of the response, if any.
  final String? etag;

  /// The `Last-Modified` of the response, if any.
  final String? lastModified;

  /// The same meta, fetched (confirmed by a 304) at [fetchedAt].
  RemoteMeta copyWith({required DateTime fetchedAt}) => RemoteMeta(
    source: source,
    sha256: sha256,
    fetchedAt: fetchedAt,
    etag: etag,
    lastModified: lastModified,
  );

  /// The conditional request headers this meta allows.
  Map<String, String> get conditionalHeaders => {
    HttpHeaders.ifNoneMatchHeader: ?etag,
    HttpHeaders.ifModifiedSinceHeader: ?lastModified,
  };

  /// The JSON to write as `meta.json`.
  Map<String, Object?> toJson() => {
    'source': source,
    'sha256': sha256,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'etag': ?etag,
    'lastModified': ?lastModified,
  };
}
