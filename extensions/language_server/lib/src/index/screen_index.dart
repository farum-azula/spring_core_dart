import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// The screens of the packages (spring_boot_starter_flutter's navigation):
/// their `@ScreenRoute` classes, and the routes of their metadata
/// (`ScreenRoutes` in Dart configuration) whose class is in the workspace.
final class ScreenIndex {
  /// The screens among [classes], with the routes of [metadata].
  ScreenIndex(this.classes, this.packages, this.metadata);

  /// The classes of the workspace.
  final ClassIndex classes;

  /// The packages of the workspace.
  final PackageLayout packages;

  /// The metadata of the packages.
  final MetadataStore metadata;

  /// The screens of the package of [path], each with its route.
  List<(MetaRoute, ClassInfo)> screens(String path) {
    final package = packages.packageRootOf(path);
    final result = <(MetaRoute, ClassInfo)>[];
    final seen = <String>{};
    for (final info in classes.allClasses) {
      if (packages.packageRootOf(info.path) != package) {
        continue;
      }
      for (final annotation in info.declaration.metadata) {
        final first = annotation.arguments?.arguments.firstOrNull;
        if (annotationName(annotation) == 'ScreenRoute' &&
            annotation.constructorName == null &&
            first is SimpleStringLiteral &&
            seen.add('${first.value} ${info.name}')) {
          result.add((
            MetaRoute(path: first.value, className: info.name),
            info,
          ));
        }
      }
    }
    for (final route in metadata.viewFor(package).routes) {
      if (route.className case final name?
          when !seen.contains('${route.path} $name')) {
        for (final info in classes.classesNamed(name)) {
          if (packages.packageRootOf(info.path) == package &&
              seen.add('${route.path} $name')) {
            result.add((route, info));
          }
        }
      }
    }
    return result;
  }

  /// The screens of the package of [from] whose pattern is [value] or
  /// matches the address [value] (its query and fragment left out), as a
  /// target to go to.
  DeclarationTarget screensOf(String from, String value) {
    final pattern = value.split('?').first.split('#').first;
    return DeclarationTarget("Screen of '$pattern'", [
      for (final (route, info) in screens(from))
        if (route.path == pattern ||
            !pattern.contains('{') && route.matches(pattern))
          DeclarationSite(
            info.path,
            info.nameOffset,
            info.name.length,
            'class `${info.name}` (`${route.path}`)',
          ),
    ]);
  }
}
