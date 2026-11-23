import 'dart:io';

/// The files below a directory that the server may read: the directory
/// must resolve to a place inside its package root, links are not
/// followed (a link to the home directory, or a cycle, is not listed),
/// `build`, `.dart_tool` and hidden directories are left out, and the
/// listing stops after [limit] files.
///
/// A listing is kept with the modification times of the directories it
/// walked and of its files: [files] lists again only when one of the
/// directories changed, and [changed] says which files to read again.
final class ConfinedFiles {
  /// A listing of [directory], which must lie inside [root].
  ConfinedFiles(this.root, this.directory, {this.limit = 2000});

  /// The package root the listing may not leave.
  final String root;

  /// The directory listed.
  final String directory;

  /// The most files listed.
  final int limit;

  final _directories = <String, DateTime>{};
  final _files = <String, DateTime>{};
  var _listed = false;

  static const _skipped = {'build', 'node_modules'};

  /// The files, listed again when a directory walked has changed.
  List<File> files() {
    if (!_listed || _directories.entries.any(_changed)) {
      _list();
    }
    return [for (final path in _files.keys) File(path)];
  }

  /// Whether [file] (one of [files]) changed since it was last asked
  /// about; true the first time.
  bool changed(File file) {
    final DateTime modified;
    try {
      modified = file.lastModifiedSync();
    } on FileSystemException {
      return true;
    }
    if (_files[file.path] == modified) {
      return false;
    }
    _files[file.path] = modified;
    return true;
  }

  static bool _changed(MapEntry<String, DateTime> directory) {
    try {
      return Directory(directory.key).statSync().modified != directory.value;
    } on FileSystemException {
      return true;
    }
  }

  void _list() {
    _listed = true;
    final before = Map.of(_files);
    _directories.clear();
    _files.clear();
    final String start;
    try {
      final base = Directory(root).resolveSymbolicLinksSync();
      start = Directory(directory).resolveSymbolicLinksSync();
      if (start != base &&
          !start.startsWith('$base${Platform.pathSeparator}')) {
        return;
      }
    } on FileSystemException {
      return;
    }
    // The listed paths keep the directory as named (not resolved), as the
    // index knows them.
    final pending = [(start, directory)];
    while (pending.isNotEmpty && _files.length < limit) {
      final (real, named) = pending.removeLast();
      final List<FileSystemEntity> entries;
      try {
        _directories[real] = Directory(real).statSync().modified;
        entries = Directory(real).listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entity in entries) {
        final name = entity.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => '',
        );
        final path = '$named${Platform.pathSeparator}$name';
        if (entity is Directory) {
          if (!name.startsWith('.') && !_skipped.contains(name)) {
            pending.add((entity.path, path));
          }
        } else if (entity is File) {
          _files[path] = before[path] ?? DateTime(0);
          if (_files.length >= limit) {
            break;
          }
        }
      }
    }
  }
}
