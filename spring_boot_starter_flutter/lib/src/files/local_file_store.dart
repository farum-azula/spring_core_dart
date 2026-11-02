import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart' show SpringLog;
import 'package:spring_boot_starter_flutter/src/files/file_paths.dart';
import 'package:spring_boot_starter_flutter/src/files/file_store.dart';

/// The [FileStore] on the device's file system (every platform with
/// `dart:io`): the places are the directories `path_provider` finds.
///
/// Writes go to a temporary file beside the target and are renamed over it,
/// so a crash or an error leaves the old file. Temporary files and folders
/// live in the folder of this run, `<system temp>/spring/<run id>/`, which
/// is deleted by [close]; a run that died leaves its folder behind, and the
/// next start deletes it (a folder is a dead run's when nobody holds the
/// lock on its `.lock` file; the operating system drops the lock with the
/// process).
///
/// Internal to the starter; an app that wants another store declares a
/// `FileStore` bean.
class LocalFileStore implements FileStore {
  /// A store whose places are the folders [directory] gives (called once
  /// per place, the folder is created). The folders of runs are under
  /// [runsDirectory] (`<system temp>/spring` by default).
  LocalFileStore({
    required Future<String> Function(FilePlace place) directory,
    Directory? runsDirectory,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _directory = directory,
       _runs =
           runsDirectory ?? Directory('${Directory.systemTemp.path}/spring');

  static const _log = SpringLog('spring_boot_starter_flutter.FileStore');

  // Run folders of this process that are alive: a lock of the same process
  // cannot tell (fcntl locks belong to the process), so they are skipped.
  static final _liveRuns = <String>{};

  final Future<String> Function(FilePlace place) _directory;
  final Directory _runs;
  final _roots = <FilePlace, Future<String>>{};
  final _random = Random.secure();

  RandomAccessFile? _lock;
  Future<Directory>? _runStart;
  Future<void> _cleaned = Future.value();
  bool _cleanStarted = false;

  Future<String> _root(FilePlace place) => _roots[place] ??= () async {
    final path = await _directory(place);
    await Directory(path).create(recursive: true);
    return path;
  }();

  Future<String> _full(FilePlace place, String path) async {
    final relative = normalizeFilePath(path);
    final root = await _root(place);
    return '$root${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}';
  }

  String _nonce() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 32).toRadixString(36)}';

  @override
  Future<void> write(FilePlace place, String path, List<int> bytes) async {
    final target = await _full(place, path);
    await File(target).parent.create(recursive: true);
    final temporary = File('$target.${_nonce()}$atomicWriteSuffix');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target);
    } on Object {
      try {
        if (temporary.existsSync()) {
          temporary.deleteSync();
        }
      } on FileSystemException {
        // The first error is the one to report.
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List?> read(FilePlace place, String path) async {
    final file = File(await _full(place, path));
    try {
      return await file.readAsBytes();
    } on PathNotFoundException {
      return null;
    } on FileSystemException {
      // A folder where a file was asked for reads as missing.
      if (await FileSystemEntity.isDirectory(file.path)) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool> exists(FilePlace place, String path) async =>
      File(await _full(place, path)).exists();

  @override
  Future<bool> delete(FilePlace place, String path) async {
    final full = await _full(place, path);
    switch (await FileSystemEntity.type(full, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return false;
      case FileSystemEntityType.directory:
        await Directory(full).delete(recursive: true);
      default:
        await File(full).delete();
    }
    return true;
  }

  @override
  Future<List<String>> list(FilePlace place, String prefix) async {
    final wanted = FilePrefix(prefix);
    final root = await _root(place);
    final start = wanted.directory.isEmpty
        ? root
        : '$root${Platform.pathSeparator}'
              '${wanted.directory.replaceAll('/', Platform.pathSeparator)}';
    final directory = Directory(start);
    if (!await directory.exists()) {
      return const [];
    }
    final prefixLength = root.length + 1;
    final found = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || entity.path.endsWith(atomicWriteSuffix)) {
        continue;
      }
      final relative = entity.path
          .substring(prefixLength)
          .replaceAll(Platform.pathSeparator, '/');
      if (wanted.matches(relative)) {
        found.add(relative);
      }
    }
    return found..sort();
  }

  @override
  Future<DateTime?> modifiedAt(FilePlace place, String path) async {
    final file = File(await _full(place, path));
    try {
      return await file.lastModified();
    } on PathNotFoundException {
      return null;
    }
  }

  // The folder of this run, made on the first temporary file; the folders
  // of dead runs are removed first (once per store).
  Future<Directory> _runDirectory() => _runStart ??= () async {
    if (!_cleanStarted) {
      _cleanStarted = true;
      _cleaned = _removeDeadRuns();
    }
    await _cleaned;
    final directory = Directory('${_runs.path}/${_runId()}');
    await directory.create(recursive: true);
    _liveRuns.add(directory.path);
    try {
      _lock = await File('${directory.path}/.lock').open(mode: FileMode.write);
      await _lock!.lock(FileLock.exclusive);
    } on FileSystemException catch (error) {
      _log.debug(() => 'the run folder could not be locked: $error');
    }
    return directory;
  }();

  String _runId() => '${_nonce()}-$pid';

  /// Removes the run folders nobody holds any more. Done once, before the
  /// first temporary file of the store; also callable on its own, for a
  /// start that wants the cleaning done now.
  Future<void> removeDeadRuns() => _cleaned = _removeDeadRuns();

  Future<void> _removeDeadRuns() async {
    try {
      if (!await _runs.exists()) {
        return;
      }
      await for (final entity in _runs.list()) {
        if (entity is! Directory || _liveRuns.contains(entity.path)) {
          continue;
        }
        if (await _isDead(entity)) {
          try {
            await entity.delete(recursive: true);
            _log.debug(() => 'removed the leftovers of a run: ${entity.path}');
          } on FileSystemException catch (error) {
            _log.debug(() => 'could not remove ${entity.path}: $error');
          }
        }
      }
    } on FileSystemException catch (error) {
      _log.debug(() => 'the old run folders could not be cleaned: $error');
    }
  }

  Future<bool> _isDead(Directory run) async {
    final lockFile = File('${run.path}/.lock');
    if (!await lockFile.exists()) {
      // Made a moment ago by a run that has not locked yet, or a folder
      // that is not ours: leave it unless it is old.
      final age = DateTime.now().difference((await run.stat()).modified);
      return age > const Duration(days: 1);
    }
    RandomAccessFile? handle;
    try {
      handle = await lockFile.open(mode: FileMode.append);
      await handle.lock(FileLock.exclusive);
      return true;
    } on FileSystemException {
      return false; // held: the run is alive
    } finally {
      await handle?.close();
    }
  }

  @override
  Future<TempFile> createTemp({String suffix = ''}) async {
    final run = await _runDirectory();
    final file = File('${run.path}/${_nonce()}${_safeSuffix(suffix)}');
    await file.create();
    return _LocalTempFile(file);
  }

  @override
  Future<TempDirectory> createTempDir() async {
    final run = await _runDirectory();
    final directory = Directory('${run.path}/${_nonce()}');
    await directory.create();
    return _LocalTempDirectory(directory);
  }

  static String _safeSuffix(String suffix) {
    if (suffix.contains('/') || suffix.contains('\\')) {
      throw ArgumentError.value(suffix, 'suffix', 'must not contain a slash');
    }
    return suffix;
  }

  @override
  Future<void> close() async {
    final started = _runStart;
    if (started == null) {
      return;
    }
    _runStart = null;
    Directory? run;
    try {
      run = await started;
    } on Object {
      return;
    }
    final lock = _lock;
    _lock = null;
    try {
      await lock?.close();
    } on FileSystemException {
      // Closing the lock only matters for deleting the folder on Windows.
    }
    try {
      if (await run.exists()) {
        await run.delete(recursive: true);
      }
    } on FileSystemException catch (error) {
      _log.warning(
        () => 'the temporary files of this run could not be removed: $error',
      );
    } finally {
      _liveRuns.remove(run.path);
    }
  }
}

final class _LocalTempFile implements TempFile {
  _LocalTempFile(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<void> writeAsBytes(List<int> bytes) =>
      _file.writeAsBytes(bytes, flush: true);

  @override
  Future<void> writeAsString(String text) => writeAsBytes(utf8.encode(text));

  @override
  Future<Uint8List> readAsBytes() => _file.readAsBytes();

  @override
  Future<String> readAsString() => _file.readAsString();

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<void> delete() async {
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Gone already.
    }
  }
}

final class _LocalTempDirectory implements TempDirectory {
  _LocalTempDirectory(this._directory);

  final Directory _directory;

  @override
  String get path => _directory.path;

  @override
  Future<void> delete() async {
    try {
      await _directory.delete(recursive: true);
    } on PathNotFoundException {
      // Gone already.
    }
  }
}
