import 'dart:io';
import 'dart:typed_data';

/// File system access through `dart:io`.
///
/// Internal: chosen by a conditional import (`dart.library.io`) in
/// `FileSystemResource` and `PathMatchingResourcePatternResolver`, so the
/// rest of the library compiles on the web. Spring has no equivalent; it
/// uses `java.io.File` / `java.nio.file.Files` directly.
abstract final class FileAccess {
  /// Always `true`: the file system is available.
  static bool get isSupported => true;

  /// Whether [path] is an existing file.
  static bool isFile(String path) => File(path).existsSync();

  /// Whether [path] is an existing directory.
  static bool isDirectory(String path) => Directory(path).existsSync();

  /// The bytes of the file at [path], read synchronously.
  static Uint8List readBytesSync(String path) => File(path).readAsBytesSync();

  /// The bytes of the file at [path], read asynchronously.
  static Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  /// [path] made absolute against the current directory.
  static String absolute(String path) => File(path).absolute.path;

  /// Size in bytes of the file at [path].
  static int length(String path) => File(path).lengthSync();

  /// Last modification time of the file at [path].
  static DateTime lastModified(String path) => File(path).lastModifiedSync();

  /// Paths of all files under [directory], using `/` separators, sorted so
  /// results are deterministic across platforms.
  static List<String> listFilesRecursively(String directory) => [
    for (final entity in Directory(directory).listSync(recursive: true))
      if (entity is File) entity.path.replaceAll(r'\', '/'),
  ]..sort();

  /// Paths of the directories directly in [directory], using `/`
  /// separators, sorted; empty if [directory] is not a directory.
  static List<String> listDirectories(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    return [
      for (final entity in dir.listSync())
        if (entity is Directory) entity.path.replaceAll(r'\', '/'),
    ]..sort();
  }
}
