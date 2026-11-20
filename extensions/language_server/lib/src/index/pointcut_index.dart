import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/index/class_index.dart';
import 'package:dart_spring_language_server/src/index/project_files.dart';

/// A `@Pointcut` method of an `@Aspect` class: a named pointcut that other
/// pointcuts use as `name()` or `Aspect.name()`.
///
/// [PointcutIndex.pointcutMethods] finds them. The pointcut check hands
/// them to the runtime's parser, so a reference to an unknown name is
/// reported, and go to definition on a reference jumps to the method.
final class PointcutMethod {
  /// The pointcut [name] of [className], defined by [expression], whose
  /// method name is at [offset] of [path].
  const PointcutMethod(
    this.className,
    this.name,
    this.expression,
    this.path,
    this.offset,
  );

  /// The aspect class that declares it: `AuditAspect` in
  /// `AuditAspect.pricing()`.
  final String className;

  /// The method's name, which is the pointcut's name.
  final String name;

  /// The pointcut expression written in `@Pointcut(...)`.
  final String expression;

  /// The file that declares it.
  final String path;

  /// The offset of the method name in [path], where navigation goes.
  final int offset;
}

/// The named pointcuts of the workspace, read from the current parse of
/// each file when asked.
final class PointcutIndex {
  /// The pointcuts of [files], whose declarations [classes] follows.
  PointcutIndex(this.files, this.classes);

  /// The files of the workspace.
  final ProjectFiles files;

  /// The classes of the workspace; a new generation may change the named
  /// pointcuts.
  final ClassIndex classes;

  ({int generation, Map<String, String> pointcuts}) _named = (
    generation: -1,
    pointcuts: const {},
  );

  /// The expressions of the named pointcuts by name, as the runtime's
  /// parser takes them: `pricing` and `AuditAspect.pricing`. Kept until the
  /// declarations of the workspace change.
  Map<String, String> get namedPointcuts {
    if (_named.generation != classes.generation) {
      final named = <String, String>{};
      for (final method in pointcutMethods) {
        named[method.name] = method.expression;
        named['${method.className}.${method.name}'] = method.expression;
      }
      _named = (generation: classes.generation, pointcuts: named);
    }
    return _named.pointcuts;
  }

  /// The `@Pointcut` methods of the workspace's `@Aspect` classes. Other
  /// pointcuts refer to them by name (`pricing()`, `AuditAspect.pricing()`),
  /// so the pointcut check and navigation need them.
  List<PointcutMethod> get pointcutMethods => [
    for (final file in files.dartFiles)
      for (final info in file.classes)
        if (info.annotationNames.contains('Aspect'))
          for (final member in info.declaration.body.members)
            if (member is MethodDeclaration)
              for (final annotation in member.metadata)
                if (annotationName(annotation) == 'Pointcut')
                  if (stringValue(positionalArgument(annotation))
                      case final expression?)
                    PointcutMethod(
                      info.name,
                      member.name.lexeme,
                      expression,
                      info.path,
                      member.name.offset,
                    ),
  ];
}
