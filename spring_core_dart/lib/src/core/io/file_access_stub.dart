import 'dart:typed_data';

/// The file and network access of the resource classes on a platform
/// without `dart:io` (the web): no file exists, and reading throws
/// [UnsupportedError].
///
/// Internal: a conditional import picks this file, or the `dart:io`
/// variant, so resources and config data compile everywhere. On the web,
/// `file:` locations are simply never found and `classpath:` resources
/// come from the generated code instead. Spring has no equivalent: the
/// JVM always has a file system.
abstract final class FileAccess {
  /// Always `false`: there is no file system.
  static bool get isSupported => false;

  /// Always `false`.
  static bool isFile(String path) => false;

  /// Always `false`.
  static bool isDirectory(String path) => false;

  /// Throws [UnsupportedError].
  static Uint8List readBytesSync(String path) => _unsupported();

  /// Completes with an [UnsupportedError].
  static Future<Uint8List> readBytes(String path) async => _unsupported();

  /// Throws [UnsupportedError].
  static Stream<List<int>> openRead(String path, [int? start, int? end]) =>
      _unsupported();

  /// Completes with an [UnsupportedError].
  static Future<Uint8List> readUrl(Uri url) async =>
      throw UnsupportedError('Reading URLs is not supported');

  /// Always `true`, so that the following read fails with a clear "URLs
  /// are not supported" error instead of a misleading "not found".
  static Future<bool> urlExists(Uri url) async => true;

  /// Returns [path] unchanged.
  static String absolute(String path) => path;

  /// Always empty.
  static List<String> listFilesRecursively(String directory) => const [];

  /// Always empty.
  static List<String> listDirectories(String directory) => const [];

  /// Always empty.
  static List<String> listFiles(String directory) => const [];

  /// Always `null`: there are no package files to point to.
  static String? resolvePackageUri(String uri) => null;

  /// Throws [UnsupportedError].
  static int length(String path) => _unsupported();

  /// Throws [UnsupportedError].
  static DateTime lastModified(String path) => _unsupported();

  static Never _unsupported() =>
      throw UnsupportedError('File system access is not supported');
}
