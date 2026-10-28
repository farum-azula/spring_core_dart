import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// A [Resource] on a web server, read with an HTTP GET request.
///
/// `http:` and `https:` locations resolve to it, so configuration can be
/// imported from a config server (`spring.config.import=https://...`) and
/// `@PropertySource` can name a URL. Applications get it from a resource
/// loader; they rarely create one.
///
/// Reading is asynchronous only ([supportsSyncRead] is `false`), so such
/// imports need an asynchronous start (`runAsync`, Flutter). A status of
/// 400 or above fails the read. [exists] cannot ask the server
/// synchronously and is always `true`; [existsAsync] sends the `HEAD`
/// request Spring's `exists()` sends, so a 404 means not found. Config
/// data (`optional:https://...`) and `@PropertySource`
/// (`ignoreResourceNotFound`) check it before reading. Reading needs
/// `dart:io`, so it does not work on the web.
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
  /// Creates the resource for [url]; nothing is requested yet.
  const UrlResource(this.url);

  /// The URL that is requested.
  final Uri url;

  /// Always `true`, because the server cannot be asked synchronously; use
  /// [existsAsync] to find out.
  @override
  bool exists() => true;

  /// Asks the server whether the resource is there: a `HEAD` request (a
  /// `GET` when the server rejects `HEAD`) answered below 400, like
  /// Spring's `exists()`. A 404 or a connection error means it does not
  /// exist. Always `true` on the web, where reading then fails.
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

  /// The resource at [relativePath] resolved against this URL, such as a
  /// profile variant next to a config file. A leading `/` is ignored, as
  /// in Spring, so the path stays relative to this URL's directory.
  @override
  Resource createRelative(String relativePath) => UrlResource(
    url.resolve(
      relativePath.startsWith('/') ? relativePath.substring(1) : relativePath,
    ),
  );
}
