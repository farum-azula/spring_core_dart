import 'dart:typed_data';

/// The content of an uploaded file (in memory: no files without
/// `dart:io`).
abstract interface class StoredFile {
  /// The size in bytes.
  int get size;

  /// Whether it is a temporary file to delete after the request.
  bool get isTemporary;

  /// The content.
  Future<Uint8List> readBytes();

  /// The content, streamed.
  Stream<List<int>> openRead();

  /// Copies the content to [path] (not supported here).
  Future<void> copyTo(String path);

  /// Deletes the temporary file.
  Future<void> delete();
}

/// Keeps an uploaded file in memory.
final class FileWriter {
  /// A writer ([threshold] and [location] are ignored: memory only).
  FileWriter({required this.threshold, this.location});

  /// Ignored.
  final int threshold;

  /// Ignored.
  final String? location;

  final _memory = BytesBuilder(copy: false);

  /// Adds [chunk].
  Future<void> add(List<int> chunk) async => _memory.add(chunk);

  /// Drops what was written.
  Future<void> abort() async => _memory.clear();

  /// The stored content.
  Future<StoredFile> close() async => _MemoryFile(_memory.takeBytes());
}

final class _MemoryFile implements StoredFile {
  _MemoryFile(this._bytes);

  final Uint8List _bytes;

  @override
  int get size => _bytes.length;

  @override
  bool get isTemporary => false;

  @override
  Future<Uint8List> readBytes() async => _bytes;

  @override
  Stream<List<int>> openRead() => Stream.value(_bytes);

  @override
  Future<void> copyTo(String path) =>
      throw UnsupportedError('transferTo needs dart:io');

  @override
  Future<void> delete() async {}
}
