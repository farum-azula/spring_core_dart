import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/strings/string_roles.dart';

final _keyPattern = RegExp(r'^[A-Za-z][\w.\-]*$');

/// The property keys the code of each package reads: `${key}` in
/// annotation strings, `@ConditionalOnProperty('key')`,
/// `getProperty('key')` (what the string roles say a string reads).
///
/// They are known to the editor for completion and hovers, but never make
/// a key "unknown" or "known" for the checks: only the metadata does. Each
/// file's keys are kept for its parse; a change of a file starts a new
/// [generation] only when that file's keys changed.
final class CodeKeyIndex implements ProjectFilesListener {
  /// The keys the files of [files] read, as [roles] find them.
  CodeKeyIndex(this.files, this.packages, this.roles) {
    files.listen(this);
  }

  /// The files of the workspace.
  final ProjectFiles files;

  /// The packages of the workspace.
  final PackageLayout packages;

  /// The roles that say which keys a string reads.
  final StringRoles roles;

  final _byFile = Expando<Set<String>>('keys read');
  Map<String, Set<String>>? _byPackage;

  /// Starts again whenever a file's keys change, so a schema built from
  /// them is built again.
  int get generation => _generation;
  var _generation = 0;

  @override
  void dartFileChanged(String path, DartFile? before, DartFile? after) {
    if (_byPackage == null) {
      return;
    }
    final had = before == null ? const <String>{} : _keysOf(before);
    final has = after == null
        ? const <String>{}
        : _keysOf(after, keep: files.isOpen(path));
    if (had.length != has.length || !had.containsAll(has)) {
      _byPackage = null;
      _generation++;
    }
  }

  @override
  void configFilesChanged() {}

  /// The keys the code of the package at [root] reads.
  Set<String> keysOf(String root) =>
      (_byPackage ??= _collect())[root] ?? const {};

  Map<String, Set<String>> _collect() {
    final result = <String, Set<String>>{};
    for (final file in files.dartFiles) {
      final keys = _keysOf(file);
      if (keys.isNotEmpty) {
        (result[packages.packageRootOf(file.path)] ??= {}).addAll(keys);
      }
    }
    return result;
  }

  Set<String> _keysOf(DartFile file, {bool keep = false}) => _byFile[file] ??= {
    for (final string in DartFileFacts.read(file, keep: keep).strings)
      for (final key in roles.keysRead(string))
        if (_keyPattern.hasMatch(key)) key,
  };
}
