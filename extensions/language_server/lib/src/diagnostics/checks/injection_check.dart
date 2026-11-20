import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/diagnostics/bean_ambiguity.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem_check.dart';
import 'package:dart_spring_language_server/src/index/file_facts.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/symbols/injection_points.dart';

/// Types the container itself provides to an injection point.
const _frameworkTypes = {
  'ApplicationContext',
  'ConfigurableApplicationContext',
  'BeanFactory',
  'ListableBeanFactory',
  'ConfigurableListableBeanFactory',
  'Environment',
  'ConfigurableEnvironment',
  'ApplicationEventPublisher',
  'ResourceLoader',
  'MessageSource',
  'ApplicationArguments',
};

/// Annotations on a class that do not make it a bean in a dependency.
const _plainAnnotations = {
  'immutable',
  'sealed',
  'deprecated',
  'visibleForTesting',
  'Immutable',
  'JsonSerializable',
};

/// Constructor, `@Bean` and `@Autowired` parameters of beans: no bean of
/// the type is an error, several without `@Primary` or `@Qualifier` a
/// warning. All profiles are considered, since the active ones are only
/// known at run time; the message says so and shows each bean's profile.
///
/// Only plain types of the project are checked: the framework provides
/// its own types, and an annotation of a dependency (a repository, a
/// client) makes a bean the editor cannot see in the source.
final class InjectionCheck implements ProblemCheck {
  /// The check over [model].
  InjectionCheck(this.model) : _points = InjectionPoints(model.classes);

  /// What the workspace knows.
  final ProjectModel model;

  final InjectionPoints _points;

  @override
  void check(DartFileFacts facts, List<Problem> problems) {
    final file = facts.file;
    final view = model.metadataFor(file.path);
    for (final parameter in facts.parameters) {
      final type = _checkedType(parameter);
      if (type == null) {
        continue;
      }
      final name = type.name.lexeme;
      final qualifier = InjectionPoints.qualifierOf(parameter.metadata);
      final candidates = model.beans.beansOfType(
        name,
        qualifier: qualifier,
        from: file.path,
      );
      final token = parameter.name;
      final range = token != null
          ? model.locations.rangeOf(file, token.offset, token.end)
          : model.locations.rangeOf(file, type.offset, type.end);
      if (candidates.isEmpty) {
        problems.add(
          Problem(
            range,
            'No bean of type $name'
            "${qualifier == null ? '' : " with qualifier '$qualifier'"} "
            '(${_considered(file.path)})'
            "${view.complete ? '' : '; dependencies without Spring metadata '
                      'may provide it'}",
            error: view.complete,
          ),
        );
      } else if (_isAmbiguous(parameter, qualifier, candidates)) {
        problems.add(
          Problem(
            range,
            'Several beans of type $name and none is @Primary: '
            '${competingBeans(candidates).map(_withProfiles).join(', ')}. '
            'Mark one @Primary or add @Qualifier (${_considered(file.path)})',
          ),
        );
      }
    }
  }

  // The type of [parameter] when it is an injection point to check.
  NamedType? _checkedType(FormalParameter parameter) {
    if (parameter.defaultClause != null ||
        !_points.isInjectedParameter(parameter) ||
        InjectionPoints.hasAnnotation(parameter.metadata, 'Value')) {
      return null;
    }
    final type = switch (parameter) {
      final FieldFormalParameter field => InjectionPoints.fieldType(field),
      _ => parameter.type is NamedType ? parameter.type! as NamedType : null,
    };
    if (type == null || type.question != null) {
      return null;
    }
    final name = type.name.lexeme;
    final classes = model.classes;
    if (beanContainers.contains(name) ||
        _frameworkTypes.contains(name) ||
        !classes.contains(name) ||
        classes
            .classesNamed(name)
            .any(
              (info) => info.annotationNames.any(
                (annotation) => !_plainAnnotations.contains(annotation),
              ),
            )) {
      return null;
    }
    return type;
  }

  static bool _isAmbiguous(
    FormalParameter parameter,
    String? qualifier,
    List<BeanInfo> candidates,
  ) =>
      competingBeans(candidates).length > 1 &&
      qualifier == null &&
      !candidates.any((bean) => bean.primary) &&
      !candidates.any(
        (bean) => bean.matches(
          parameter.name?.lexeme.replaceFirst(RegExp('^_+'), '') ?? '',
        ),
      );

  String _considered(String path) {
    final profiles = model.properties.knownProfiles(path).toList()..sort();
    return profiles.isEmpty
        ? 'all profiles considered'
        : 'all profiles considered: ${profiles.join(', ')}';
  }

  static String _withProfiles(BeanInfo bean) => bean.profiles.isEmpty
      ? bean.name
      : '${bean.name} (profile ${bean.profiles.join(', ')})';
}
