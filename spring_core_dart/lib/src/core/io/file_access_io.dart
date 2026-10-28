import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// The file and network access of the resource classes, through
/// `dart:io`.
///
/// Internal: a conditional import (`dart.library.io`) picks this file in
/// `FileSystemResource`, `UrlResource`, the resource loader, the pattern
/// resolver and the config data loader, and the stub elsewhere, so none of
/// them imports `dart:io` and the library still compiles for the web.
/// Spring has no equivalent; it uses `java.io.File` and
/// `java.nio.file.Files` directly.
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

  /// The bytes of the file at [path] from [start] (inclusive) to [end]
  /// (exclusive), streamed.
  static Stream<List<int>> openRead(String path, [int? start, int? end]) =>
      File(path).openRead(start, end);

  /// The body of a GET request to [url]. A status of 400 or above throws
  /// an [HttpException]; network errors propagate.
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

  /// Whether [url] answers: a `HEAD` request (repeated as a `GET` when
  /// the server rejects `HEAD` with 405 or 501) with a status below 400.
  /// A connection error counts as "does not exist". Spring's
  /// `AbstractFileResolvingResource.exists()` checks the same way.
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

  /// [path] made absolute against the current working directory.
  static String absolute(String path) => File(path).absolute.path;

  /// The size in bytes of the file at [path]; throws when it is missing.
  static int length(String path) => File(path).lengthSync();

  /// The last modification time of the file at [path]; throws when it is
  /// missing.
  static DateTime lastModified(String path) => File(path).lastModifiedSync();

  /// The paths of all files under [directory], at any depth, with `/`
  /// separators and sorted, so results are the same on every platform.
  static List<String> listFilesRecursively(String directory) => [
    for (final entity in Directory(directory).listSync(recursive: true))
      if (entity is File) entity.path.replaceAll(r'\', '/'),
  ]..sort();

  /// The paths of the directories directly in [directory], with `/`
  /// separators and sorted; empty if [directory] does not exist or may not
  /// be read.
  static List<String> listDirectories(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    try {
      return [
        for (final entity in dir.listSync())
          if (entity is Directory) entity.path.replaceAll(r'\', '/'),
      ]..sort();
    } on FileSystemException {
      // Not readable (an Android app's working directory is `/`): skipped,
      // as Spring skips a directory it may not read.
      return const [];
    }
  }

  /// The paths of the files directly in [directory], with `/` separators
  /// and sorted; empty if [directory] does not exist or may not be read.
  static List<String> listFiles(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      return const [];
    }
    try {
      return [
        for (final entity in dir.listSync())
          if (entity is File) entity.path.replaceAll(r'\', '/'),
      ]..sort();
    } on FileSystemException {
      // Not readable (an Android app's working directory is `/`): skipped,
      // as Spring skips a directory it may not read.
      return const [];
    }
  }

  /// The file path behind a `package:` [uri], looked up in the package
  /// config of the running program. `null` when it cannot be resolved,
  /// which is always the case in an AOT executable (it has no package
  /// config).
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
