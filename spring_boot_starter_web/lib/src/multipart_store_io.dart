import 'dart:io';
import 'dart:typed_data';

/// The content of an uploaded file: in memory, or a temporary file.
abstract interface class StoredFile {
  /// The size in bytes.
  int get size;

  /// Whether it is a temporary file to delete after the request.
  bool get isTemporary;

  /// The content.
  Future<Uint8List> readBytes();

  /// The content, streamed.
  Stream<List<int>> openRead();

  /// Copies (or moves) the content to [path].
  Future<void> copyTo(String path);

  /// Deletes the temporary file.
  Future<void> delete();
}

/// Writes one uploaded file: in memory up to [threshold] bytes, then to a
/// temporary file in [location].
final class FileWriter {
  /// A writer keeping up to [threshold] bytes in memory.
  FileWriter({required this.threshold, this.location});

  /// Bytes kept in memory before switching to a file.
  final int threshold;

  /// The directory of the temporary files (`null`: the system's).
  final String? location;

  final _memory = BytesBuilder(copy: false);
  File? _file;
  IOSink? _sink;
  var _size = 0;

  /// Adds [chunk].
  Future<void> add(List<int> chunk) async {
    _size += chunk.length;
    if (_sink == null && _memory.length + chunk.length <= threshold) {
      _memory.add(chunk);
      return;
    }
    if (_sink == null) {
      final directory = location == null
          ? Directory.systemTemp
          : Directory(location!);
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'upload_${DateTime.now().microsecondsSinceEpoch}_'
        '${identityHashCode(this)}.tmp',
      );
      _file = file;
      final sink = file.openWrite();
      _sink = sink;
      if (_memory.length > 0) {
        sink.add(_memory.takeBytes());
      }
    }
    _sink!.add(chunk);
  }

  /// Deletes what was written.
  Future<void> abort() async {
    await _sink?.close();
    if (_file case final file? when file.existsSync()) {
      await file.delete();
    }
  }

  /// The stored content.
  Future<StoredFile> close() async {
    final sink = _sink;
    if (sink == null) {
      return _MemoryFile(_memory.takeBytes());
    }
    await sink.close();
    return _TemporaryFile(_file!, _size);
  }
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
  Future<void> copyTo(String path) => File(path).writeAsBytes(_bytes);

  @override
  Future<void> delete() async {}
}

final class _TemporaryFile implements StoredFile {
  _TemporaryFile(this._file, this.size);

  final File _file;
  var _moved = false;

  @override
  final int size;

  @override
  bool get isTemporary => true;

  @override
  Future<Uint8List> readBytes() => _file.readAsBytes();

  @override
  Stream<List<int>> openRead() => _file.openRead();

  // Like Spring's transferTo: the temporary file is moved when it can be.
  @override
  Future<void> copyTo(String path) async {
    if (!_moved) {
      try {
        await _file.rename(path);
        _moved = true;
        return;
      } on FileSystemException {
        // Another device: copy below.
      }
    }
    await _file.copy(path);
  }

  @override
  Future<void> delete() async {
    if (!_moved && _file.existsSync()) {
      await _file.delete();
    }
  }
}
