import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/declaration_signature.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/pointcuts.dart';

/// The top-level classes of the workspace by simple name, their
/// supertypes, and the annotations that make a class a bean.
///
/// A change of a file that keeps its [declarationSignature] (typing inside
/// a method body) only swaps that file's classes for those of the new
/// parse; any other change starts a new [generation], which tells what is
/// built from the classes (the beans) to build again.
final class ClassIndex implements ProjectFilesListener {
  /// The classes of [files]; [packages] says which package a class is in.
  ClassIndex(this.files, this.packages) {
    files.listen(this);
  }

  /// The files the classes are read from.
  final ProjectFiles files;

  /// The packages of the workspace.
  final PackageLayout packages;

  Map<String, List<ClassInfo>>? _byName;
  Set<String>? _stereotypes;

  /// Starts again whenever a file's declarations change: a class, an
  /// annotation, a supertype or a `@Bean` method appeared, went or
  /// changed, or a file appeared or went. Tests read it to see that typing
  /// inside a method body builds nothing again.
  int get generation => _generation;
  var _generation = 0;

  @override
  void dartFileChanged(String path, DartFile? before, DartFile? after) {
    if (before != null &&
        after != null &&
        declarationSignature(before) == declarationSignature(after)) {
      _swap(before.classes, after.classes);
      return;
    }
    _generation++;
    _byName = null;
    _stereotypes = null;
  }

  @override
  void configFilesChanged() {}

  // The same classes at new offsets: each takes its old one's place.
  void _swap(List<ClassInfo> before, List<ClassInfo> after) {
    final index = _byName;
    if (index == null) {
      return;
    }
    for (var i = 0; i < before.length && i < after.length; i++) {
      final named = index[before[i].name];
      final at = named?.indexOf(before[i]) ?? -1;
      if (at >= 0) {
        named![at] = after[i];
      }
    }
  }

  Map<String, List<ClassInfo>> get _index => _byName ??= _build();

  Map<String, List<ClassInfo>> _build() {
    final index = <String, List<ClassInfo>>{};
    for (final file in files.dartFiles) {
      for (final info in file.classes) {
        (index[info.name] ??= []).add(info);
      }
    }
    return index;
  }

  /// The classes of the workspace called [name] (top-level, by simple name).
  List<ClassInfo> classesNamed(String name) =>
      _index[name] ?? const <ClassInfo>[];

  /// Whether the workspace declares a class called [name].
  bool contains(String name) => _index.containsKey(name);

  /// Every top-level class of the workspace.
  Iterable<ClassInfo> get allClasses => _index.values.expand((c) => c);

  /// The classes by name.
  Iterable<MapEntry<String, List<ClassInfo>>> get byName => _index.entries;

  /// Every type name that a class called [name] can be used as: itself and
  /// its supertypes (`extends`, `implements`, `with`), followed through the
  /// classes of the workspace by simple name. A type from a dependency ends
  /// its branch.
  Set<String> supertypesOf(String name) {
    final result = <String>{};
    final pending = [name];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!result.add(current)) {
        continue;
      }
      for (final info in _index[current] ?? const <ClassInfo>[]) {
        pending.addAll(info.supertypes);
      }
    }
    return result;
  }

  /// The names of the annotations that make a class a bean: the
  /// [baseStereotypes], plus the classes of the workspace that extend one of
  /// them (a custom `UseCase` annotation that extends `Component`).
  Set<String> get stereotypes => _stereotypes ??= {
    ...baseStereotypes,
    for (final MapEntry(key: name, value: infos) in _index.entries)
      if (infos.isNotEmpty &&
          supertypesOf(name).skip(1).any(baseStereotypes.contains))
        name,
  };

  /// Whether the class [node] is a bean the container creates or wires:
  /// it has a stereotype or `@Configurable`.
  bool isBeanClass(ClassDeclaration? node) {
    if (node == null) {
      return false;
    }
    final names = {for (final a in node.metadata) annotationName(a)};
    return names.any(stereotypes.contains) || names.contains('Configurable');
  }

  /// The classes whose name matches [pattern] (`*` and `..` wildcards);
  /// those of the package of [from] when it has any (a test class
  /// elsewhere may have the same name).
  List<ClassInfo> classesMatching(String from, String pattern) =>
      samePackageFirst(from, [
        for (final MapEntry(:key, :value) in _index.entries)
          if (wildcardMatches(pattern, key)) ...value,
      ]);

  /// Those of [classes] in the package of [from], or all of them when none
  /// is.
  List<ClassInfo> samePackageFirst(String from, List<ClassInfo> classes) {
    final package = packages.packageRootOf(from);
    final local = [
      for (final info in classes)
        if (packages.packageRootOf(info.path) == package) info,
    ];
    return local.isNotEmpty ? local : classes;
  }
}
