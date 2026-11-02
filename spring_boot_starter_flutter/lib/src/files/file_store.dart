import 'dart:typed_data';

/// Where a file of the app lives.
enum FilePlace {
  /// The app's private data (the default): kept, backed up with the
  /// device, never cleared by the system.
  support,

  /// The cache: the system may clear it when space runs out, so only for
  /// what can be made again.
  cache,

  /// The user's documents: visible to the user (desktop, the Files app of
  /// iOS).
  documents,
}

/// A temporary file made by a [FileStore]: it lives in the folder of the
/// run, and goes away with its block, with the context, or at the next
/// start.
///
/// On the web it is kept in memory and has no [path]: reading it throws an
/// `UnsupportedError`.
abstract interface class TempFile {
  /// The file's path on disk, for code that needs a real file (a
  /// `dart:io` `File(temp.path)`, a plugin); throws an `UnsupportedError`
  /// where there is no file system (the web).
  String get path;

  /// Replaces the file's content with [bytes].
  Future<void> writeAsBytes(List<int> bytes);

  /// Replaces the file's content with [text], in UTF-8.
  Future<void> writeAsString(String text);

  /// The file's whole content.
  Future<Uint8List> readAsBytes();

  /// The file's whole content as UTF-8 text.
  Future<String> readAsString();

  /// Whether the file still exists.
  Future<bool> exists();

  /// Deletes the file; nothing happens when it is gone.
  Future<void> delete();
}

/// A temporary folder made by a [FileStore]; see [TempFile].
abstract interface class TempDirectory {
  /// The folder's path; throws an `UnsupportedError` where there is no file
  /// system.
  String get path;

  /// Deletes the folder and what is in it; nothing happens when it is
  /// gone.
  Future<void> delete();
}

/// The bytes of the app's files, by place and path: what [FileTemplate]
/// writes through. Declare a bean of this type to replace the default (an
/// encrypting store, a remote one): `FileTemplate` and everything above it,
/// the theme cache too, follow.
///
/// The paths it receives are already checked (relative, `/`-separated, no
/// `..`). An implementation writes atomically: a reader sees the old file
/// or the new one, never half of it.
abstract interface class FileStore {
  /// Replaces the file at [path] of [place] with [bytes], creating the
  /// folders above it.
  Future<void> write(FilePlace place, String path, List<int> bytes);

  /// The file's content, or `null` when there is none.
  Future<Uint8List?> read(FilePlace place, String path);

  /// Whether a file exists at [path].
  Future<bool> exists(FilePlace place, String path);

  /// Deletes the file at [path], or the folder with all that is in it;
  /// returns whether something was deleted.
  Future<bool> delete(FilePlace place, String path);

  /// The paths of the files matching [prefix] (a folder when it ends in
  /// `/` or is empty, else the start of a path), sorted; relative to the
  /// place.
  Future<List<String>> list(FilePlace place, String prefix);

  /// When the file was last written, or `null` when there is none.
  Future<DateTime?> modifiedAt(FilePlace place, String path);

  /// A new empty temporary file with a unique name, ending in [suffix].
  Future<TempFile> createTemp({String suffix = ''});

  /// A new empty temporary folder with a unique name; throws an
  /// `UnsupportedError` where there is no file system.
  Future<TempDirectory> createTempDir();

  /// Releases the store: removes what this run left in the temporary
  /// folder. Called when the context closes.
  Future<void> close();
}
