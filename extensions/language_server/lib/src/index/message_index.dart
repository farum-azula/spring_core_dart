import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';

final _addedCodes = Expando<Set<String>>('message codes added in code');

/// The message bundles of the workspace (`messages.properties`,
/// `messages_ja.properties`, ..., or the bundles of
/// `spring.messages.basename`) and the codes some code registers itself
/// (`StaticMessageSource().addMessage('code', ...)`).
///
/// The bundles are found again when a config file changes; the codes of a
/// package are collected again only when a file's own codes changed.
final class MessageIndex implements ProjectFilesListener {
  /// The messages of [files]; [packages] says which package a file is in.
  MessageIndex(this.files, this.packages) {
    files.listen(this);
  }

  /// The files of the workspace.
  final ProjectFiles files;

  /// The packages of the workspace.
  final PackageLayout packages;

  Map<String, String>? _bundles;

  // Packages with `spring.messages.use-code-as-default-message=true`: an
  // unknown code is not an error there.
  final _codeAsDefault = <String>{};

  final _addedByPackage = <String, Set<String>>{};

  @override
  void configFilesChanged() => _bundles = null;

  @override
  void dartFileChanged(String path, DartFile? before, DartFile? after) {
    if (_addedByPackage.isEmpty) {
      return;
    }
    final had = before == null ? const <String>{} : _addedIn(before);
    final has = after == null
        ? const <String>{}
        : _addedIn(after, keep: files.isOpen(path));
    if (had.length != has.length || !had.containsAll(has)) {
      _addedByPackage.clear();
    }
  }

  /// The paths of the message bundles; their keys are no properties.
  Set<String> get bundlePaths => _bundlePackages.keys.toSet();

  /// The definitions of the message [code] in every message bundle, the
  /// default bundle first. With [from], only the bundles of that file's
  /// package.
  List<PropertyEntry> messages(String code, {String? from}) {
    final package = from == null ? null : packages.packageRootOf(from);
    return [
      for (final MapEntry(key: path, value: bundlePackage)
          in _bundlePackages.entries)
        if (package == null || bundlePackage == package)
          for (final entry
              in files.configFiles[path] ?? const <PropertyEntry>[])
            if (entry.key == code) entry,
    ]..sort((a, b) => a.fileName.compareTo(b.fileName));
  }

  /// The message codes of the bundles of the package of [path].
  Set<String> messageCodes(String path) {
    final package = packages.packageRootOf(path);
    return {
      for (final MapEntry(key: bundle, value: bundlePackage)
          in _bundlePackages.entries)
        if (bundlePackage == package)
          for (final entry
              in files.configFiles[bundle] ?? const <PropertyEntry>[])
            entry.key,
    };
  }

  /// Whether the package of [path] has a message bundle; only then are the
  /// message codes of its files checked.
  bool hasMessageBundles(String path) =>
      _bundlePackages.values.contains(packages.packageRootOf(path));

  /// Whether an unknown code is reported in the package of [path]: it has
  /// bundles, and does not use the code as the default message.
  bool checksCodes(String path) =>
      hasMessageBundles(path) &&
      !_codeAsDefault.contains(packages.packageRootOf(path));

  /// Whether [code] is defined for [path]: in a bundle of its package, or
  /// registered in the code of the package.
  bool defines(String path, String code) =>
      _addedInPackage(path).contains(code) ||
      messages(code, from: path).isNotEmpty;

  // Codes registered in code in the package of [path].
  Set<String> _addedInPackage(String path) {
    final package = packages.packageRootOf(path);
    return _addedByPackage[package] ??= {
      for (final file in files.dartFiles)
        if (packages.packageRootOf(file.path) == package) ..._addedIn(file),
    };
  }

  // The first strings of the `addMessage('code', ...)` calls of [file].
  static Set<String> _addedIn(DartFile file, {bool keep = false}) =>
      _addedCodes[file] ??= {
        for (final string in DartFileFacts.read(file, keep: keep).strings)
          if (string.method == 'addMessage' &&
              identical(
                string
                    .invocation!
                    .argumentList
                    .arguments
                    .firstOrNull
                    ?.argumentExpression,
                string.literal,
              ))
            string.value,
      };

  // The message bundles by path, with their package: `.properties` files
  // under a `resources/` directory whose name (without the locale suffix)
  // is a basename of their package's `spring.messages.basename`
  // (`messages` by default; dots or slashes separate folders:
  // `i18n/messages`). Each package has its own setting.
  Map<String, String> get _bundlePackages => _bundles ??= _findBundles();

  Map<String, String> _findBundles() {
    final basenames = <String, Set<String>>{};
    final common = <String, Set<String>>{};
    _codeAsDefault.clear();
    for (final MapEntry(key: path, value: entries)
        in files.configFiles.entries) {
      for (final entry in entries) {
        _readSetting(path, entry, basenames, common);
      }
    }
    final result = <String, String>{};
    for (final path in files.configFiles.keys) {
      if (!path.endsWith('.properties')) {
        continue;
      }
      final relative = PackageLayout.resourcePath(path);
      if (relative == null) {
        continue;
      }
      final package = packages.packageRootOf(path);
      final names = basenames[package] ?? const {'messages'};
      if (names.any(
            (basename) =>
                relative == basename || relative.startsWith('${basename}_'),
          ) ||
          (common[package]?.contains(relative) ?? false)) {
        result[path] = package;
      }
    }
    return result;
  }

  // The `spring.messages.*` settings of [entry] of the config file [path].
  void _readSetting(
    String path,
    PropertyEntry entry,
    Map<String, Set<String>> basenames,
    Map<String, Set<String>> common,
  ) {
    if (entry.key == 'spring.messages.use-code-as-default-message' &&
        entry.value.trim().toLowerCase() == 'true') {
      _codeAsDefault.add(packages.packageRootOf(path));
    }
    if (entry.key == 'spring.messages.common-messages') {
      for (final name in _locations(entry.value)) {
        final dot = name.lastIndexOf('.');
        common
            .putIfAbsent(packages.packageRootOf(path), () => {})
            .add(name.substring(0, dot < 0 ? name.length : dot));
      }
    }
    if (entry.key == 'spring.messages.basename') {
      final names = basenames.putIfAbsent(
        packages.packageRootOf(path),
        () => {},
      );
      for (final name in _locations(entry.value)) {
        names.add(name.replaceAll('.', '/'));
      }
    }
  }

  // The names of a comma-separated list of locations, without
  // `resources:`.
  static Iterable<String> _locations(String value) sync* {
    for (final name in value.split(',')) {
      final trimmed = name.trim().replaceFirst(RegExp('^resources:'), '');
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }
}
