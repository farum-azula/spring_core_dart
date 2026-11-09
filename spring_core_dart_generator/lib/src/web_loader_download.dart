import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Gets the text at an `https` address; `null` when it cannot (offline,
/// an error status). Tests give their own.
typedef WebLoaderFetch = Future<String?> Function(Uri uri);

/// The `web:` of a loader downloaded at build time (`https://...`,
/// `github:...`), kept in `.dart_tool/spring/loaders/` so a build offline
/// uses the last copy; with a pin (`web-sha256`) a file of another digest
/// is refused and not kept.
final class WebLoaderDownload {
  /// Downloads through [fetch] (the network by default) and keeps copies
  /// in [cache].
  WebLoaderDownload({
    required this.cache,
    WebLoaderFetch? fetch,
    bool allowInsecure = false,
    this.extension = '.html',
    this.pinProperty = 'web-sha256',
    this.limit = maxBytes,
  }) : _fetch = fetch ?? ((uri) => _network(uri, allowInsecure: allowInsecure));

  /// The extension of the copies (`.html` for a loader, `.json` for a JSON
  /// Schema).
  final String extension;

  /// The property that pins a file, named when its digest differs.
  final String pinProperty;

  /// The size a file may have.
  final int limit;

  /// The size a loader's file may have: 512 KiB.
  static const int maxBytes = 512 * 1024;

  /// How long a download may take.
  static const Duration timeout = Duration(seconds: 10);

  /// The folder of the copies.
  final Directory cache;

  final WebLoaderFetch _fetch;

  /// The text of [uri] (pinned to [sha256] when given) and a problem to
  /// report, if any: the downloaded text, else the copy of an earlier
  /// build, else `null`.
  Future<({String? text, String? problem})> read(
    Uri uri,
    String? sha256,
  ) async {
    final copy = File(
      '${cache.path}/${_hex(utf8.encode('$uri\n${sha256 ?? ''}'))}$extension',
    );
    String? problem;
    try {
      final text = await _fetch(uri).timeout(timeout);
      if (text == null) {
        problem = '$uri could not be downloaded';
      } else if (utf8.encode(text).length > limit) {
        problem = '$uri is bigger than ${limit ~/ 1024} KiB';
      } else if (sha256 != null && _hex(utf8.encode(text)) != sha256) {
        problem = '$uri does not have the SHA-256 of $pinProperty: refused';
      } else {
        await copy.parent.create(recursive: true);
        await copy.writeAsString(text);
        return (text: text, problem: null);
      }
    } on Object catch (error) {
      problem = '$uri could not be downloaded ($error)';
    }
    if (copy.existsSync()) {
      return (
        text: await copy.readAsString(),
        problem: '$problem; the copy of an earlier build is used',
      );
    }
    return (text: null, problem: problem);
  }

  static String _hex(List<int> bytes) => sha256.convert(bytes).toString();

  static Future<String?> _network(
    Uri uri, {
    required bool allowInsecure,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    if (allowInsecure) {
      client.badCertificateCallback = (_, _, _) => true;
    }
    try {
      var target = uri;
      for (var hops = 0; hops < 5; hops++) {
        final request = await client.getUrl(target)
          ..followRedirects = false;
        final response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          final next = location == null ? null : target.resolve(location);
          if (next == null ||
              !(next.scheme == 'https' ||
                  (allowInsecure && next.scheme == 'http'))) {
            return null;
          }
          target = next;
          continue;
        }
        if (response.statusCode != 200) {
          await response.drain<void>();
          return null;
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
          if (bytes.length > maxBytes) {
            throw const FormatException('the file is bigger than 512 KiB');
          }
        }
        return utf8.decode(bytes);
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
