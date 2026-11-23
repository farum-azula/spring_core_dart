// A controller's `Pageable` or `Sort` lets a client order by any property
// of the entity, also one a DTO leaves out of the answer: the order of the
// rows then tells what the answer hides. Matched by URL and name (the
// generator depends on neither starter).
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

const _controller = TypeChecker.typeNamedLiterally(
  'Controller',
  inPackage: 'spring_core_dart',
);
const _mapping = TypeChecker.fromUrl(
  'package:spring_web_dart/src/annotations.dart#Mapping',
);
const _allowed = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/web/web_paging.dart'
  '#AllowedSortProperties',
);
const _sortParameters = [
  TypeChecker.fromUrl(
    'package:spring_boot_starter_data/src/repository/page.dart#Pageable',
  ),
  TypeChecker.fromUrl(
    'package:spring_boot_starter_data/src/repository/sort.dart#Sort',
  ),
];

/// The warning for each handler of the controller [element] with a
/// `Pageable` or `Sort` parameter and no `@AllowedSortProperties` on it.
Iterable<String> openSortWarnings(ClassElement element) sync* {
  if (!_controller.hasAnnotationOf(element)) {
    return;
  }
  final seen = <String>{};
  for (final type in [element.thisType, ...element.allSupertypes]) {
    for (final method in type.element.methods) {
      final name = method.name;
      if (name == null ||
          !seen.add(name) ||
          !_mapping.hasAnnotationOf(method)) {
        continue;
      }
      for (final parameter in method.formalParameters) {
        if (_sortParameters.any(
              (checker) => checker.isExactlyType(parameter.type),
            ) &&
            !_allowed.hasAnnotationOf(parameter)) {
          yield '${element.name}.$name: the parameter ${parameter.name} lets '
              'a client sort by any property of the entity, also one the '
              'answer leaves out, and the order of the rows then shows it. '
              "Name what it may sort by: @AllowedSortProperties(['name']).";
        }
      }
    }
  }
}

/// Logs [openSortWarnings] of [element].
void warnAboutOpenSort(ClassElement element) =>
    openSortWarnings(element).forEach(log.warning);
