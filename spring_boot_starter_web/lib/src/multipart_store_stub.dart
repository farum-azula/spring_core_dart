import 'dart:typed_data';

/// Where the content of one uploaded file waits while the request is
/// handled.
///
/// Internal to the multipart resolver; a controller sees the file as a
/// `MultipartFile`. This is the version for platforms without
/// `dart:io`, where there are no files: the content stays in memory.
abstract interface class StoredFile {
  /// The size of the content in bytes.
  int get size;

  /// Whether the content is in a temporary file to delete when the
  /// request ends; always `false` here.
  bool get isTemporary;

  /// The whole content.
  Future<Uint8List> readBytes();

  /// The content as a stream.
  Stream<List<int>> openRead();

  /// Puts the content at [path]; throws an [UnsupportedError] here, since
  /// there is no file system.
  Future<void> copyTo(String path);

  /// Deletes the temporary file; nothing to do here.
  Future<void> delete();
}

/// Stores one uploaded file in memory as its bytes arrive.
final class FileWriter {
  /// A writer; [threshold] and [location] are accepted for the same
  /// signature as the `dart:io` version, and ignored.
  FileWriter({required this.threshold, this.location});

  /// Ignored: everything stays in memory.
  final int threshold;

  /// Ignored: there are no temporary files.
  final String? location;

  final _memory = BytesBuilder(copy: false);

  /// Stores the next [chunk] of the file.
  Future<void> add(List<int> chunk) async => _memory.add(chunk);

  /// Gives up the file, dropping what was stored.
  Future<void> abort() async => _memory.clear();

  /// Finishes the file and returns its stored content.
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
