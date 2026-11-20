import 'dart:io';

import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';

/// Directories the scan never enters: tool and build output, and the
/// platform folders of a Flutter app, which hold no Spring sources.
/// Hidden directories (a leading `.`) are skipped as well.
const _skippedDirectories = {
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
  'ios',
  'android',
  'macos',
  'windows',
  'linux',
};

/// Told when the files of a [ProjectFiles] change, so that what is built
/// from them can be kept, updated or dropped.
abstract interface class ProjectFilesListener {
  /// The parse of the Dart file [path] changed: [before] is the one the
  /// workspace had (null for a new file), [after] the new one (null when
  /// the file is gone).
  void dartFileChanged(String path, DartFile? before, DartFile? after);

  /// A config file changed, appeared or went.
  void configFilesChanged();
}

/// The files of the open project: its Dart files, parsed for syntax, and
/// the entries of its config files, each from the open document's unsaved
/// text when there is one, else from the disk.
///
/// Files are read from disk when their modification time changes,
/// skipping the generated `*.spring.dart` and `*.g.dart`; the unsaved text
/// of an open document ([setOverlay]) wins over the disk. The
/// [ProjectFilesListener]s hear of every change.
final class ProjectFiles {
  /// The files under the directories [roots]. Nothing is read until
  /// [refresh] or a lookup.
  ProjectFiles(this.roots);

  /// The workspace folders the editor opened, scanned recursively.
  final List<String> roots;

  final _dart = <String, DartFile>{};
  final _modified = <String, DateTime>{};
  final _overlays = <String, String>{};
  final _configOverlays = <String, String>{};
  final _config = <String, List<PropertyEntry>>{};
  final _configModified = <String, DateTime>{};
  final _listeners = <ProjectFilesListener>[];
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);

  /// Tells [listener] of every change from now on.
  void listen(ProjectFilesListener listener) => _listeners.add(listener);

  /// Every parsed Dart file, in the order they were first read.
  Iterable<DartFile> get dartFiles => _dart.values;

  /// The paths of the parsed Dart files.
  Iterable<String> get dartPaths => _dart.keys;

  /// The parsed Dart file at [path] if it was read already; unlike
  /// [dartFile], it never reads the disk.
  DartFile? loaded(String path) => _dart[path];

  /// Whether the editor has the document [path] open ([setOverlay]).
  bool isOpen(String path) =>
      _overlays.containsKey(path) || _configOverlays.containsKey(path);

  /// The entries of every config file, by path, in the order the files
  /// were first read.
  Map<String, List<PropertyEntry>> get configFiles => _config;

  /// Sets the unsaved [text] of the document open at [path]; with `null`
  /// (the document was closed), the file on disk counts again.
  ///
  /// A Dart document is parsed at once, so the next query sees it. A config
  /// file ([isConfigFile]) is read as properties, so its unsaved keys count
  /// for navigation and for the unknown-key check. Other files are ignored.
  void setOverlay(String path, String? text) {
    if (!path.endsWith('.dart')) {
      _setConfigOverlay(path, text);
      return;
    }
    if (text == null) {
      _overlays.remove(path);
      _modified.remove(path); // read from disk again at the next scan
      return;
    }
    _overlays[path] = text;
    _putDart(path, DartFile.parse(path, text));
  }

  void _setConfigOverlay(String path, String? text) {
    if (!isConfigFile(path)) {
      return;
    }
    if (text == null) {
      _configOverlays.remove(path);
      _configModified.remove(path); // read from disk again
    } else {
      _configOverlays[path] = text;
      // Unsaved keys count for navigation and checks right away.
      _config[path] = ConfigFormat.of(path).entries(path, text);
    }
    _configChanged();
  }

  /// Whether [path] is a config file of the application, whose keys are
  /// indexed and whose values are highlighted: any `.properties` file, and
  /// YAML named `application*` or under a `resources/` directory. Not every
  /// YAML: `${{ }}` in a CI workflow is no placeholder.
  static bool isConfigFile(String path) => ConfigFormat.isConfigFile(path);

  /// Scans [roots] again: re-reads the files changed on disk and forgets
  /// those that are gone. Returns whether it scanned.
  ///
  /// Queries call it, so to stay cheap it scans at most once per [interval]
  /// (2 seconds by default) unless [force] is set. The server forces it on
  /// `initialized`, on save and when watched files change.
  bool refresh({
    bool force = false,
    Duration interval = const Duration(seconds: 2),
  }) {
    final now = DateTime.now();
    if (!force && now.difference(_lastScan) < interval) {
      return false;
    }
    _lastScan = now;
    final seenDart = <String>{};
    final seenConfig = <String>{};
    for (final root in roots) {
      final directory = Directory(root);
      if (directory.existsSync()) {
        _walk(directory, seenDart, seenConfig);
      }
    }
    for (final path in [..._dart.keys]) {
      if (!seenDart.contains(path) && !_overlays.containsKey(path)) {
        final before = _dart.remove(path);
        _modified.remove(path);
        _dartChanged(path, before, null);
      }
    }
    final before = _config.length;
    _config.removeWhere((path, _) => !seenConfig.contains(path));
    if (_config.length != before) {
      _configChanged();
    }
    return true;
  }

  void _walk(Directory directory, Set<String> dart, Set<String> config) {
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entries) {
      final name = entity.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (entity is Directory) {
        if (!name.startsWith('.') && !_skippedDirectories.contains(name)) {
          _walk(entity, dart, config);
        }
      } else if (entity is File) {
        if (_isSource(name)) {
          dart.add(entity.path);
          _readDart(entity);
        } else if (isConfigFile(entity.path)) {
          config.add(entity.path);
          _readConfig(entity);
        }
      }
    }
  }

  // A Dart file of the sources, not one the generator writes: a module's
  // `.spring.dart`, `.g.dart`, and the files beside a module's
  // `.spring.dart` (its descriptions, the binding of its
  // `@ConfigurationProperties` classes, its proxies, an app's debug part).
  static bool _isSource(String name) =>
      name.endsWith('.dart') &&
      !name.endsWith('.spring.dart') &&
      !name.endsWith('.g.dart') &&
      !name.endsWith('.spring.introspection.dart') &&
      !name.endsWith('.spring.properties.dart') &&
      !name.endsWith('.spring.proxies.dart') &&
      !name.endsWith('.spring.debug.dart') &&
      !name.endsWith('.spring.env.dart');

  void _readDart(File file) {
    if (_overlays.containsKey(file.path)) {
      return;
    }
    final modified = file.lastModifiedSync();
    if (_modified[file.path] == modified) {
      return;
    }
    _modified[file.path] = modified;
    try {
      _putDart(file.path, DartFile.parse(file.path, file.readAsStringSync()));
    } on FileSystemException {
      final before = _dart.remove(file.path);
      _dartChanged(file.path, before, null);
    }
  }

  void _putDart(String path, DartFile file) {
    final before = _dart[path];
    _dart[path] = file;
    _dartChanged(path, before, file);
  }

  void _readConfig(File file) {
    if (_configOverlays.containsKey(file.path)) {
      return; // the open document wins
    }
    final modified = file.lastModifiedSync();
    if (_configModified[file.path] == modified) {
      return;
    }
    _configModified[file.path] = modified;
    try {
      final text = file.readAsStringSync();
      _config[file.path] = ConfigFormat.of(file.path).entries(file.path, text);
    } on FileSystemException {
      _config.remove(file.path);
    }
    _configChanged();
  }

  /// The parsed Dart file at [path]: the open document's text if there is
  /// one, else the file on disk, read on first use. `null` when [path] is
  /// not a Dart file or does not exist.
  DartFile? dartFile(String path) {
    if (!path.endsWith('.dart')) {
      return null;
    }
    final existing = _dart[path];
    if (existing != null) {
      return existing;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    _readDart(file);
    return _dart[path];
  }

  /// The text of the file at [path]: the open document's, else the file on
  /// disk; `null` when it cannot be read.
  String? textOf(String path) {
    if (path.endsWith('.dart')) {
      return dartFile(path)?.text;
    }
    if (_configOverlays[path] case final open?) {
      return open;
    }
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  // A listener made while others hear of a change hears of the next one.
  void _dartChanged(String path, DartFile? before, DartFile? after) {
    for (final listener in [..._listeners]) {
      listener.dartFileChanged(path, before, after);
    }
  }

  void _configChanged() {
    for (final listener in [..._listeners]) {
      listener.configFilesChanged();
    }
  }
}
