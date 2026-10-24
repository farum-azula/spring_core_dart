import 'dart:io';
import 'dart:isolate';
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

  /// The body of a GET request to [url]; a status of 400 or above throws
  /// an [HttpException].
  static Future<Uint8List> readUrl(Uri url) async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(url)).close();
      if (response.statusCode >= 400) {
        await response.drain<void>();
        throw HttpException(
          'Cannot read URL [$url]: HTTP ${response.statusCode}',
          uri: url,
        );
      }
      final builder = BytesBuilder(copy: false);
      await response.forEach(builder.add);
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }

  /// Whether [url] exists, like Spring's `AbstractFileResolvingResource
  /// .exists()`: a `HEAD` request (a `GET` when the server rejects `HEAD`
  /// with 405 or 501) that answers below 400. A connection error means it
  /// does not exist.
  static Future<bool> urlExists(Uri url) async {
    final client = HttpClient();
    try {
      var response = await (await client.headUrl(url)).close();
      await response.drain<void>();
      if (response.statusCode == HttpStatus.methodNotAllowed ||
          response.statusCode == HttpStatus.notImplemented) {
        response = await (await client.getUrl(url)).close();
        await response.drain<void>();
      }
      return response.statusCode < 400;
    } on IOException {
      return false;
    } finally {
      client.close();
    }
  }

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

  /// Paths of the files directly in [directory], using `/` separators,
  /// sorted; empty if [directory] is not a directory.
  static List<String> listFiles(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    return [
      for (final entity in dir.listSync())
        if (entity is File) entity.path.replaceAll(r'\', '/'),
    ]..sort();
  }

  /// The file path of a `package:` [uri] through the package config of
  /// the running program; `null` when it cannot be resolved (an AOT
  /// executable has no package config).
  static String? resolvePackageUri(String uri) {
    try {
      final resolved = Isolate.resolvePackageUriSync(Uri.parse(uri));
      return resolved != null && resolved.isScheme('file')
          ? resolved.toFilePath().replaceAll(r'\', '/')
          : null;
    } on Object {
      return null;
    }
  }
}
