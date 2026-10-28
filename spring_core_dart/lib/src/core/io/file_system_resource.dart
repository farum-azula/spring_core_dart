import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// A [Resource] for a file (or directory) on the local file system, given
/// by its path.
///
/// `file:` locations resolve to it, which is how `./application.yml` next
/// to a server binary or `file:./data/import.csv` is read. An application
/// gets it from a resource loader, or creates one directly for a path it
/// already knows, for example to serve a file with [openRead]. It can be
/// read synchronously where `dart:io` exists; on the web it never exists.
/// A directory exists but is not readable ([isReadable] is `false`), as in
/// Spring.
///
/// ```dart
/// // A config file next to the program, with its profile variant.
/// final resource = FileSystemResource('config/application.properties');
/// if (resource.exists()) {
///   final text = resource.readAsStringSync();
///   final dev = resource.createRelative('application-dev.properties');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// var resource = new FileSystemResource("config/application.properties");
/// if (resource.exists()) {
///   String text = resource.getContentAsString(StandardCharsets.UTF_8);
///   Resource dev = resource.createRelative("application-dev.properties");
/// }
/// ```
class FileSystemResource extends AbstractResource {
  /// Creates the resource for [path], relative to the working directory or
  /// absolute. Nothing is read or checked yet.
  ///
  /// The path is normalized: `\` becomes `/`, `.` and empty segments are
  /// removed, and `..` cancels the previous segment (leading `..` segments
  /// of a relative path are kept).
  FileSystemResource(String path) : path = _clean(path);

  /// Creates the resource for a `file:` URL, percent-decoded like Spring's
  /// `ResourceUtils.getFile`: `file:my%20dir/a.txt` is `my dir/a.txt`.
  ///
  /// `file:///abs` and `file:/abs` are absolute paths; only a local host
  /// (`file://localhost/abs`) is supported. A `%` that is not a valid
  /// escape is kept as written.
  ///
  /// ```dart
  /// FileSystemResource.fromFileUrl('file:///srv/my%20app/a.properties')
  ///     .path; // /srv/my app/a.properties
  /// ```
  factory FileSystemResource.fromFileUrl(String url) {
    var rest = url.startsWith('file:') ? url.substring(5) : url;
    // `file://host/path`: only an empty (local) host is supported.
    if (rest.startsWith('///')) {
      rest = rest.substring(2);
    } else if (rest.startsWith('//localhost/')) {
      rest = rest.substring('//localhost'.length);
    }
    if (rest.contains('%')) {
      try {
        rest = Uri.decodeComponent(rest);
      } on ArgumentError {
        // Not a valid escape: a literal `%` in the path.
      }
    }
    return FileSystemResource(rest);
  }

  /// The normalized path, relative or absolute as it was given.
  final String path;

  // Like Spring's StringUtils.cleanPath: `.` and empty segments are
  // dropped and `..` removes the previous segment. Leading `..` segments of
  // a relative path are kept; at the root of an absolute path (`/` or a
  // Windows drive like `C:/`) they are dropped. An empty relative path
  // becomes `.`.
  static String _clean(String path) {
    var normalized = path.replaceAll(r'\', '/');
    var root = '';
    final drive = RegExp('^[a-zA-Z]:/').firstMatch(normalized);
    if (drive != null) {
      root = drive[0]!;
    } else if (normalized.startsWith('/')) {
      root = '/';
    }
    normalized = normalized.substring(root.length);
    final segments = <String>[];
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
          continue;
        }
        if (root.isNotEmpty) {
          continue;
        }
      }
      segments.add(segment);
    }
    final joined = segments.join('/');
    if (root.isNotEmpty) {
      return '$root$joined';
    }
    return joined.isEmpty ? '.' : joined;
  }

  @override
  bool exists() => FileAccess.isFile(path) || FileAccess.isDirectory(path);

  /// Whether this is an existing file, which can be read; `false` for a
  /// directory.
  @override
  bool get isReadable => FileAccess.isFile(path);

  /// Whether [path] is an existing directory.
  bool get isDirectory => FileAccess.isDirectory(path);

  @override
  String get filename => path.split('/').last;

  @override
  String get description => 'file [${FileAccess.absolute(path)}]';

  @override
  Uri get uri => Uri.file(FileAccess.absolute(path));

  @override
  bool get supportsSyncRead => FileAccess.isSupported;

  /// The size of the file in bytes, for a `Content-Length` header for
  /// example. Throws when the file does not exist.
  int contentLength() => FileAccess.length(path);

  /// When the file was last changed, for caching headers for example.
  /// Throws when the file does not exist.
  DateTime lastModified() => FileAccess.lastModified(path);

  @override
  Future<Uint8List> readAsBytes() => FileAccess.readBytes(path);

  /// Streams the content from byte [start] (included) to [end] (excluded),
  /// the whole file by default, without holding it in memory: for a
  /// download or an HTTP `Range` request.
  Stream<List<int>> openRead([int? start, int? end]) =>
      FileAccess.openRead(path, start, end);

  @override
  Uint8List readAsBytesSync() => FileAccess.readBytesSync(path);

  /// The file at [relativePath] from this file's directory, such as a
  /// sibling; [relativePath] may contain `..`.
  @override
  FileSystemResource createRelative(String relativePath) {
    final slash = path.lastIndexOf('/');
    final parent = slash < 0 ? '' : path.substring(0, slash + 1);
    return FileSystemResource('$parent$relativePath');
  }

  /// Whether [other] is a file resource with the same normalized path.
  @override
  bool operator ==(Object other) =>
      other is FileSystemResource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
