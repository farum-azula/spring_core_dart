import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// An `http:` / `https:` resource, read with a GET request, like Spring's
/// `UrlResource`; `DefaultResourceLoader` returns one for such locations.
///
/// Reading is asynchronous only ([supportsSyncRead] is `false`); a status
/// of 400 or above fails the read. [exists] cannot ask the server
/// synchronously and is `true`; [existsAsync] sends the `HEAD` request
/// Spring's `exists()` sends, so a 404 means not found. Config data
/// (`spring.config.import=optional:http://…`) and `@PropertySource`
/// (`ignoreResourceNotFound`) check it before reading. Reading needs
/// `dart:io` (not on the web).
///
/// ```dart
/// final resource = DefaultResourceLoader()
///     .getResource('https://example.com/config/app.properties');
/// final text = await resource.readAsString();
/// final sibling = resource.createRelative('app-dev.properties');
/// ```
///
/// Spring (Java):
/// ```java
/// Resource resource = new UrlResource("https://example.com/config/app.properties");
/// String text = resource.getContentAsString(StandardCharsets.UTF_8);
/// ```
class UrlResource extends AbstractResource {
  /// A resource for [url].
  const UrlResource(this.url);

  /// The URL read.
  final Uri url;

  /// Always `true`: a synchronous request is not possible; see
  /// [existsAsync].
  @override
  bool exists() => true;

  /// Whether the server has the resource: a `HEAD` request (a `GET` if the
  /// server rejects `HEAD`) answered below 400, like Spring's `exists()`.
  /// A 404 or a connection error means it does not exist.
  ///
  /// ```dart
  /// if (await resource.existsAsync()) {
  ///   final text = await resource.readAsString();
  /// }
  /// ```
  Future<bool> existsAsync() => FileAccess.urlExists(url);

  @override
  String get description => 'URL [$url]';

  @override
  Uri get uri => url;

  @override
  String? get filename {
    final segments = url.pathSegments;
    return segments.isEmpty || segments.last.isEmpty ? null : segments.last;
  }

  @override
  Future<Uint8List> readAsBytes() => FileAccess.readUrl(url);

  /// [relativePath] resolved against this URL (a leading `/` is ignored,
  /// like Spring's).
  @override
  Resource createRelative(String relativePath) => UrlResource(
    url.resolve(
      relativePath.startsWith('/') ? relativePath.substring(1) : relativePath,
    ),
  );
}
