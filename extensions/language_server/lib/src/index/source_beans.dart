import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/data_model.dart';

/// The beans a Dart file declares in its source: the classes with a
/// stereotype annotation and their `@Bean` methods, and the Spring Data
/// repositories, which the data starter makes beans without an
/// annotation.
final class SourceBeans {
  /// Beans found with [data], which tells a repository's entity.
  SourceBeans(this.data);

  /// The data layer: a class whose entity it knows is a repository.
  final DataModel data;

  /// The beans of [file], in the order of the source; [stereotypes] are
  /// the annotations that make a class a bean.
  List<BeanInfo> of(DartFile file, Set<String> stereotypes) {
    final result = <BeanInfo>[];
    for (final info in file.classes) {
      final stereotype = info.annotations
          .where((a) => stereotypes.contains(annotationName(a)))
          .firstOrNull;
      if (stereotype == null) {
        // A Spring Data repository (`implements DataRepository<Book, int>`)
        // is a bean the data starter makes; it carries no annotation.
        if (data.entityOf(info.declaration, file.path) != null) {
          result.add(_repository(file, info));
        }
        continue;
      }
      result
        ..add(_component(file, info, stereotype))
        ..addAll(_beanMethods(file, info));
    }
    return result;
  }

  BeanInfo _repository(DartFile file, ClassInfo info) => BeanInfo(
    name: defaultBeanName(info.name),
    typeName: info.name,
    kind: BeanKind.component,
    path: file.path,
    declaringClass: info.name,
    qualifiers: qualifiersOf(info.annotations),
    primary: info.annotationNames.contains('Primary'),
    profiles: profilesOf(info.annotations),
    backsOff: backsOff(info.annotations),
  );

  BeanInfo _component(DartFile file, ClassInfo info, Annotation stereotype) {
    final explicit = unnamedStereotypes.contains(annotationName(stereotype))
        ? stringValue(namedArgument(stereotype, 'name'))
        : stringValue(positionalArgument(stereotype));
    final name = explicit ?? defaultBeanName(info.name);
    return BeanInfo(
      name: name,
      typeName: info.name,
      kind: BeanKind.component,
      path: file.path,
      declaringClass: info.name,
      qualifiers: qualifiersOf(info.annotations),
      primary: info.annotationNames.contains('Primary'),
      profiles: profilesOf(info.annotations),
      contextGetter: _contextGetter(info.annotations, name),
      backsOff: backsOff(info.annotations),
    );
  }

  Iterable<BeanInfo> _beanMethods(DartFile file, ClassInfo info) sync* {
    for (final member in info.declaration.body.members) {
      if (member is! MethodDeclaration) {
        continue;
      }
      final bean = member.metadata
          .where((a) => annotationName(a) == 'Bean')
          .firstOrNull;
      final returned = typeName(member.returnType);
      if (bean == null || returned == null) {
        continue;
      }
      final name =
          stringValue(namedArgument(bean, 'name')) ?? member.name.lexeme;
      yield BeanInfo(
        name: name,
        typeName: returned,
        kind: BeanKind.beanMethod,
        path: file.path,
        declaringClass: info.name,
        method: member.name.lexeme,
        aliases: stringList(namedArgument(bean, 'aliases')).toSet(),
        qualifiers: qualifiersOf(member.metadata),
        primary: member.metadata.any((a) => annotationName(a) == 'Primary'),
        profiles: profilesOf(member.metadata),
        backsOff: backsOff(member.metadata),
        owner: info.name,
        contextGetter: _contextGetter(member.metadata, name),
      );
    }
  }

  // The `BuildContext` getter `@BuildContextAccess` generates: its `name:`,
  // else the bean name.
  static String? _contextGetter(List<Annotation> annotations, String bean) {
    for (final annotation in annotations) {
      if (annotationName(annotation) == 'BuildContextAccess') {
        return stringValue(namedArgument(annotation, 'name')) ?? bean;
      }
    }
    return null;
  }

  /// The values of the `@Qualifier('...')` among [annotations].
  static Set<String> qualifiersOf(List<Annotation> annotations) => {
    for (final annotation in annotations)
      if (annotationName(annotation) == 'Qualifier')
        ?stringValue(positionalArgument(annotation)),
  };

  /// Whether [annotations] make a bean give way to another of its type:
  /// `@Fallback` or `@ConditionalOnMissingBean`.
  static bool backsOff(List<Annotation> annotations) => annotations.any(
    (a) => const {
      'Fallback',
      'ConditionalOnMissingBean',
    }.contains(annotationName(a)),
  );

  /// The profile expressions of the `@Profile(...)` among [annotations].
  static List<String> profilesOf(List<Annotation> annotations) => [
    for (final annotation in annotations)
      if (annotationName(annotation) == 'Profile')
        ...stringList(positionalArgument(annotation)),
  ];
}
