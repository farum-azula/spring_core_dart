import 'dart:typed_data';

/// File system access is not available on this platform (web).
///
/// Internal: the fallback of a conditional import; files never exist and
/// reading throws [UnsupportedError]. Spring has no equivalent (the JVM
/// always has a file system).
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

  /// Completes with an [UnsupportedError].
  static Future<Uint8List> readUrl(Uri url) async =>
      throw UnsupportedError('Reading URLs is not supported');

  /// Returns [path] unchanged.
  static String absolute(String path) => path;

  /// Always empty.
  static List<String> listFilesRecursively(String directory) => const [];

  /// Always empty.
  static List<String> listDirectories(String directory) => const [];

  /// Always empty.
  static List<String> listFiles(String directory) => const [];

  /// Always `null`: there are no package files.
  static String? resolvePackageUri(String uri) => null;

  /// Throws [UnsupportedError].
  static int length(String path) => _unsupported();

  /// Throws [UnsupportedError].
  static DateTime lastModified(String path) => _unsupported();

  static Never _unsupported() =>
      throw UnsupportedError('File system access is not supported');
}
