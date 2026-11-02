import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/files/file_paths.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';

/// The files of one [FilePlace]: what `files.cache` and `files.documents`
/// give, and what [FileTemplate] itself does for `support`.
///
/// Paths are relative to the place and use `/`; an absolute path or one
/// with `..` throws an `ArgumentError`, so a file never leaves its place.
/// Every method reports errors in the returned `Future`.
final class FileArea {
  FileArea._(this._template, this.place);

  final FileTemplate _template;

  /// The place these files are in.
  final FilePlace place;

  FileStore get _store => _template.fileStore;

  /// Writes [value] to [path], replacing what was there, atomically: a
  /// reader and a crash see the old file or the new one, never half of it.
  ///
  /// A `String` is written as UTF-8 text, a `List<int>` (`Uint8List`) as
  /// bytes, anything else as JSON with the application's `ObjectMapper`
  /// (the class needs `@Introspected()` or a JSON serializer). Creates the
  /// folders above the file.
  Future<void> write(String path, Object value) async {
    final bytes = switch (value) {
      final String text => utf8.encode(text),
      final List<int> bytes => bytes,
      _ => utf8.encode(_template.objectMapper.writeValueAsString(value)),
    };
    await _store.write(place, normalizeFilePath(path), bytes);
  }

  /// The file at [path] as a [T], or `null` when there is none: `String`
  /// (UTF-8), `Uint8List` or `List<int>` (bytes), anything else is JSON
  /// read with the `ObjectMapper`; pass [type] for generic types
  /// (`ListType<Book>(...)`), as for `ObjectMapper.readValue`.
  ///
  /// Throws a `JsonMappingException` when the content does not fit [T].
  Future<T?> read<T>(String path, [TypeInfo<T>? type]) async {
    final bytes = await _store.read(place, normalizeFilePath(path));
    if (bytes == null) {
      return null;
    }
    if (T == String) {
      return utf8.decode(bytes) as T;
    }
    if (T == Uint8List || T == List<int>) {
      return bytes as T;
    }
    return _template.objectMapper.readValue<T>(utf8.decode(bytes), type);
  }

  /// The file at [path] as UTF-8 text; `null` when there is none.
  Future<String?> readString(String path) => read<String>(path);

  /// The file at [path] as bytes; `null` when there is none.
  Future<Uint8List?> readBytes(String path) => read<Uint8List>(path);

  /// Whether a file exists at [path].
  Future<bool> exists(String path) async =>
      _store.exists(place, normalizeFilePath(path));

  /// Deletes the file at [path], or the folder and all that is in it;
  /// returns whether something was deleted.
  Future<bool> delete(String path) async =>
      _store.delete(place, normalizeFilePath(path));

  /// The paths (relative to the place, sorted) of the files below the
  /// folder [prefix] when it ends in `/` or is empty, else of the files
  /// whose path starts with [prefix].
  Future<List<String>> list([String prefix = '']) => _store.list(place, prefix);

  /// When the file at [path] was last written; `null` when there is none.
  Future<DateTime?> modifiedAt(String path) async =>
      _store.modifiedAt(place, normalizeFilePath(path));
}

/// The app's own files: settings, downloads, caches, exports, written and
/// read as text, bytes or objects, in the right directory of every
/// platform.
///
/// `FileTemplate` itself works in [support] (the app's private data, kept);
/// [cache] and [documents] are the other places. Writes are atomic, paths
/// cannot leave their place, objects go through the application's
/// `ObjectMapper`. The bytes go through a [FileStore] bean, which an app
/// can replace (to encrypt, to keep files on a server). On the web the
/// files are in IndexedDB.
///
/// ```dart
/// @Service()
/// class Library {
///   Library(this.files);
///   final FileTemplate files;
///
///   Future<void> save(List<Book> books) => files.write('catalog.json', books);
///
///   Future<List<Book>> load() async =>
///       await files.read<List<Book>>(
///         'catalog.json',
///         const ListType<Book>(ClassType<Book>()),
///       ) ??
///       [];
///
///   Future<void> cacheCover(String id, Uint8List png) =>
///       files.cache.write('covers/$id.png', png); // the system may clear it
///
///   Future<void> export(String csv) =>
///       files.documents.write('books.csv', csv); // the user sees it
/// }
/// ```
///
/// Temporary files ([temp], [tempDir], [createTemp]) have unique names in
/// a folder of the run (`<system temp>/spring/<run id>/`): deleted after
/// their block, when the context closes, and, for a run that died, at the
/// next start. On the web they are in memory and have no path.
///
/// Spring has nothing like it (Java has `Files` and `Path`); it is shaped
/// like the other templates (`JdbcTemplate`, `RestTemplate`): a template
/// over a replaceable lower layer.
class FileTemplate {
  /// A template over [fileStore], with [objectMapper] (a default
  /// `ObjectMapper` when omitted; the bean gets the application's).
  FileTemplate(this.fileStore, {ObjectMapper? objectMapper})
    : objectMapper = objectMapper ?? ObjectMapper() {
    support = FileArea._(this, FilePlace.support);
    cache = FileArea._(this, FilePlace.cache);
    documents = FileArea._(this, FilePlace.documents);
  }

  /// Where the bytes go.
  final FileStore fileStore;

  /// Turns objects into JSON and back.
  final ObjectMapper objectMapper;

  /// The app's private data (the default place of this template's own
  /// methods): kept, backed up, never cleared by the system.
  late final FileArea support;

  /// The cache: the system may clear it when space runs out.
  late final FileArea cache;

  /// The user's documents: visible to the user.
  late final FileArea documents;

  /// Like [FileArea.write], in [support].
  Future<void> write(String path, Object value) => support.write(path, value);

  /// Like [FileArea.read], in [support].
  Future<T?> read<T>(String path, [TypeInfo<T>? type]) =>
      support.read<T>(path, type);

  /// Like [FileArea.exists], in [support].
  Future<bool> exists(String path) => support.exists(path);

  /// Like [FileArea.delete], in [support].
  Future<bool> delete(String path) => support.delete(path);

  /// Like [FileArea.list], in [support].
  Future<List<String>> list([String prefix = '']) => support.list(prefix);

  /// Like [FileArea.modifiedAt], in [support].
  Future<DateTime?> modifiedAt(String path) => support.modifiedAt(path);

  /// Runs [block] with a new temporary file and returns its result; the
  /// file is deleted afterwards, also when [block] throws. The name ends in
  /// [suffix] (`.png`) for code that looks at the extension.
  ///
  /// ```dart
  /// final small = await files.temp(suffix: '.jpg', (file) async {
  ///   await file.writeAsBytes(photo);
  ///   return compress(File(file.path)); // a real path, not on the web
  /// });
  /// ```
  Future<T> temp<T>(
    FutureOr<T> Function(TempFile file) block, {
    String suffix = '',
  }) async {
    final file = await fileStore.createTemp(suffix: suffix);
    try {
      return await block(file);
    } finally {
      await file.delete();
    }
  }

  /// Runs [block] with a new temporary folder and returns its result; the
  /// folder and what is in it are deleted afterwards, also when [block]
  /// throws. Fails with an `UnsupportedError` on the web.
  Future<T> tempDir<T>(FutureOr<T> Function(TempDirectory dir) block) async {
    final directory = await fileStore.createTempDir();
    try {
      return await block(directory);
    } finally {
      await directory.delete();
    }
  }

  /// A new temporary file for when a block is not enough; the caller
  /// deletes it with [TempFile.delete]. What it leaves is removed when the
  /// context closes and at the next start.
  Future<TempFile> createTemp({String suffix = ''}) =>
      fileStore.createTemp(suffix: suffix);

  /// A new temporary folder, like [createTemp].
  Future<TempDirectory> createTempDir() => fileStore.createTempDir();

  /// Removes this run's temporary files. The context calls it when it
  /// closes.
  Future<void> close() => fileStore.close();
}
