import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';
import 'package:dart_spring_language_server/src/metadata.dart';

/// Joins the beans of the Spring metadata (dependencies'
/// auto-configuration, the package's own at the last build) to the beans
/// found in the source.
///
/// A bean declared in a file of the workspace is taken from the source,
/// the live truth; the metadata then only adds the supertypes and the
/// members SpEL can reach.
final class MetadataBeans {
  /// Joins the metadata of [metadata] for the packages of [files].
  MetadataBeans(this.files, this.packages, this.classes, this.metadata);

  /// The files whose packages' metadata is read.
  final ProjectFiles files;

  /// Finds the package of each file.
  final PackageLayout packages;

  /// The classes of the workspace.
  final ClassIndex classes;

  /// The metadata of the packages.
  final MetadataStore metadata;

  /// Adds the beans of the metadata to [beans] (those of the source), and
  /// sets the types every bean provides.
  void join(List<BeanInfo> beans) {
    final local = <String, BeanInfo>{};
    for (final bean in beans) {
      local.putIfAbsent(bean.name, () => bean);
    }
    final seen = <SpringMetadata>{};
    final roots = {
      for (final path in files.dartPaths) packages.packageRootOf(path),
    };
    final fromMetadata = <BeanInfo>[];
    for (final root in roots) {
      final view = metadata.viewFor(root);
      for (final meta in view.metadata) {
        if (!seen.add(meta)) {
          continue;
        }
        for (final bean in meta.beans) {
          if (local[bean.name] case final declared?) {
            declared
              ..members = bean.members
              ..extraTypes = bean.types;
            continue;
          }
          if (_bean(view, bean) case final found?) {
            fromMetadata.add(found);
          }
        }
      }
    }
    beans.addAll(fromMetadata);
    for (final bean in beans) {
      bean.providedTypes = {
        ...classes.supertypesOf(bean.typeName),
        ...bean.extraTypes,
      };
    }
  }

  // A bean the source does not declare; `null` when its class was removed
  // from the source since the last build.
  BeanInfo? _bean(MetadataView view, MetaBean bean) {
    final path = view.resolve(bean.source);
    final declared = path == null ? null : files.loaded(path);
    final klass = declared?.classes
        .where((c) => c.name == bean.type)
        .firstOrNull;
    // The class is gone from the whole workspace. A bean declared elsewhere
    // than its class (a `BeanDefinition` or `@Bean` in a configuration
    // file) is kept.
    if (declared != null && klass == null && !classes.contains(bean.type)) {
      return null;
    }
    return BeanInfo(
      name: bean.name,
      typeName: bean.type,
      kind: BeanKind.component,
      path: path ?? '',
      declaringClass: klass?.name,
      qualifiers: bean.qualifiers.toSet(),
      primary: bean.primary,
      profiles: bean.profiles,
      // A class of the workspace is found in the live source.
      line: klass != null || bean.line == null ? null : bean.line! - 1,
      members: bean.members,
      fromMetadata: true,
      scope: bean.scope,
      origin: bean.source,
      backsOff: bean.conditions.any(
        (c) =>
            c.startsWith('@ConditionalOnMissingBean') ||
            c.startsWith('@Fallback'),
      ),
    )..extraTypes = bean.types;
  }
}
