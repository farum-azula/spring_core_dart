import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Where the content of one uploaded file waits while the request is
/// handled: in memory for a small file, else in a temporary file.
///
/// Internal to the `MultipartResolver`; a controller sees the file as a
/// `MultipartFile`. This is the `dart:io` version.
abstract interface class StoredFile {
  /// The size of the content in bytes.
  int get size;

  /// Whether the content is in a temporary file that must be deleted
  /// when the request ends.
  bool get isTemporary;

  /// The whole content, read into memory.
  Future<Uint8List> readBytes();

  /// The content as a stream, without loading it whole.
  Stream<List<int>> openRead();

  /// Puts the content at [path]. A temporary file is moved there when
  /// possible (then it is no longer deleted, and no longer readable at
  /// its old place), else copied; content in memory is written.
  Future<void> copyTo(String path);

  /// Deletes the temporary file, unless it was moved away; nothing for
  /// content in memory.
  Future<void> delete();
}

/// Stores one uploaded file as its bytes arrive: in memory up to
/// [threshold] bytes, then in a temporary file.
///
/// Temporary files go to a directory of this process that only its user
/// can open (`0700`, made with `mkdtemp`) inside [location], or inside the
/// system's temporary directory; each has a random name and is created
/// exclusively, so another user can neither read an upload nor plant a
/// file or a link under its name. When that directory disappears (the
/// system cleans its temporary directory: macOS after some days unused,
/// `systemd-tmpfiles`), a new one is made for the next file.
final class FileWriter {
  /// A writer that keeps up to [threshold] bytes in memory.
  FileWriter({required this.threshold, this.location});

  /// The most bytes kept in memory; past it, everything goes to a file.
  final int threshold;

  /// The directory in which the private directory of the temporary files
  /// is made, created when missing; `null` for the system's temporary
  /// directory.
  final String? location;

  // The private directory per location, made once per process.
  static final _directories = <String, Future<Directory>>{};
  static final _random = Random.secure();

  static Future<Directory> _privateDirectory(String? location) {
    final key = location ?? '';
    if (_directories[key] case final existing?) {
      return existing;
    }
    final created = _directories[key] = _create(location);
    // A failure is not kept: the next upload tries again.
    unawaited(
      created.then<void>(
        (_) {},
        onError: (Object _) => _directories.remove(key),
      ),
    );
    return created;
  }

  static Future<Directory> _create(String? location) async {
    final parent = location == null
        ? Directory.systemTemp
        : Directory(location);
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    return await parent.createTemp('spring_uploads_');
  }

  // A new empty file of random name in the private directory, made again
  // when it was removed since.
  static Future<File> _createFile(String? location) async {
    final directory = await _privateDirectory(location);
    try {
      return await _newFile(directory);
    } on FileSystemException {
      if (directory.existsSync()) {
        rethrow;
      }
      final key = location ?? '';
      if (identical(await _directories[key], directory)) {
        _directories.remove(key)?.ignore();
      }
      return await _newFile(await _privateDirectory(location));
    }
  }

  static Future<File> _newFile(Directory directory) => File(
    '${directory.path}${Platform.pathSeparator}${_randomName()}',
  ).create(exclusive: true);

  static String _randomName() {
    final out = StringBuffer('upload_');
    for (var i = 0; i < 16; i++) {
      out.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return '$out.tmp';
  }

  final _memory = BytesBuilder(copy: false);
  File? _file;
  IOSink? _sink;
  var _size = 0;

  /// Stores the next [chunk] of the file, switching to a temporary file
  /// when the content outgrows [threshold].
  Future<void> add(List<int> chunk) async {
    _size += chunk.length;
    if (_sink == null && _memory.length + chunk.length <= threshold) {
      _memory.add(chunk);
      return;
    }
    if (_sink == null) {
      final file = await _createFile(location);
      _file = file;
      final sink = file.openWrite();
      _sink = sink;
      if (_memory.length > 0) {
        sink.add(_memory.takeBytes());
      }
    }
    _sink!.add(chunk);
  }

  /// Gives up the file, deleting the temporary file if one was started;
  /// used when the file passes a size limit.
  Future<void> abort() async {
    await _sink?.close();
    if (_file case final file? when file.existsSync()) {
      await file.delete();
    }
  }

  /// Finishes the file and returns its stored content.
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
