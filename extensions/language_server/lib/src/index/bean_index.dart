import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';
import 'package:dart_spring_language_server/src/index/metadata_beans.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/index/source_beans.dart';
import 'package:dart_spring_language_server/src/metadata.dart';

/// Every bean of the workspace: those its sources declare
/// ([SourceBeans]) and those of the Spring metadata ([MetadataBeans]), and
/// which of them an injection point or a name selects.
///
/// Built on first use, and again when the declarations of the workspace
/// ([ClassIndex.generation]) or its metadata changed. A bean's position is
/// looked up in the current parse when navigation needs it, so typing
/// that moves a declaration does not build the beans again.
final class BeanIndex {
  /// The beans of [files], with their classes in [classes].
  BeanIndex(
    this.files,
    this.packages,
    this.classes,
    this.metadata,
    this.sourceBeans,
  ) : _metadataBeans = MetadataBeans(files, packages, classes, metadata);

  /// The files the beans are declared in.
  final ProjectFiles files;

  /// Finds the package of a file.
  final PackageLayout packages;

  /// The classes of the workspace.
  final ClassIndex classes;

  /// The metadata of the packages.
  final MetadataStore metadata;

  /// Finds the beans of one file.
  final SourceBeans sourceBeans;

  final MetadataBeans _metadataBeans;

  List<BeanInfo>? _beans;
  ({int classes, int metadata}) _builtFor = (classes: -1, metadata: -1);

  /// How many times the beans were built; tests read it to see that typing
  /// inside a method body does not build them again.
  int get builds => _builds;
  var _builds = 0;

  /// Every bean declared in the workspace: the classes with a stereotype
  /// annotation, the `@Bean` methods inside them, the repositories, and the
  /// beans of the metadata. Built on first use after a change.
  List<BeanInfo> get beans {
    final current = (classes: classes.generation, metadata: metadata.version);
    final cached = _beans;
    if (cached != null && current == _builtFor) {
      return cached;
    }
    _builtFor = current;
    _builds++;
    final stereotypes = classes.stereotypes;
    final result = [
      for (final file in files.dartFiles) ...sourceBeans.of(file, stereotypes),
    ];
    _metadataBeans.join(result);
    return _beans = result;
  }

  /// The beans that can be injected where [type] is asked for, `@Primary`
  /// ones first: what go to definition on an injection point lists. With
  /// [qualifier], only the beans whose name, alias or `@Qualifier` it is.
  ///
  /// With [from] (a file), only the beans that package can see: its own and
  /// those of its dependencies. A workspace holds many packages, and their
  /// tests and examples often declare beans of the same type.
  List<BeanInfo> beansOfType(String type, {String? qualifier, String? from}) {
    final visible = from == null ? null : _visibleRoots(from);
    return [
      for (final bean in beans)
        if (bean.providedTypes.contains(type))
          if (qualifier == null || bean.matches(qualifier))
            if (visible == null || _isVisible(bean, visible)) bean,
    ]..sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0));
  }

  /// The beans that answer to [name], by bean name, by
  /// `@Bean(aliases: ...)` or by `@Qualifier`.
  List<BeanInfo> beansNamed(String name) => [
    for (final bean in beans)
      if (bean.matches(name)) bean,
  ];

  /// The beans whose `@BuildContextAccess` getter is called [name]
  /// (`context.basket`).
  List<BeanInfo> beansWithContextGetter(String name) => [
    for (final bean in beans)
      if (bean.contextGetter == name) bean,
  ];

  // The package roots a file sees (its package and its dependencies),
  // symlinks resolved, and the names of the packages.
  ({Set<String> roots, Set<String> packages}) _visibleRoots(String path) {
    final root = packages.packageRootOf(path);
    final view = metadata.viewFor(root);
    return (
      roots: {
        for (final visible in {root, ...view.packageRoots.values})
          PackageLayout.realPath(visible),
      },
      packages: view.packageRoots.keys.toSet(),
    );
  }

  bool _isVisible(
    BeanInfo bean,
    ({Set<String> roots, Set<String> packages}) visible,
  ) {
    if (bean.path.isNotEmpty) {
      // The bean's own package, not just a folder above it: a package
      // nested in another (an example inside a starter) has its own root.
      final own = packages.ownPackageOf(bean.path);
      return own == null || visible.roots.contains(own);
    }
    final origin = bean.origin;
    if (origin == null || !origin.startsWith('package:')) {
      return true;
    }
    final name = origin.substring('package:'.length).split('/').first;
    return visible.packages.contains(name);
  }
}
