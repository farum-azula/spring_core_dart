import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// A readable explanation of why the application failed to start, like
/// Spring Boot's `FailureAnalysis`.
final class FailureAnalysis {
  /// Creates an analysis.
  const FailureAnalysis(this.description, this.action, this.cause);

  /// What went wrong.
  final String description;

  /// How to fix it.
  final String action;

  /// The underlying error.
  final Object cause;

  /// The report printed at startup:
  ///
  /// ```text
  /// ***************************
  /// APPLICATION FAILED TO START
  /// ***************************
  ///
  /// Description:
  /// ...
  ///
  /// Action:
  /// ...
  /// ```
  String get report =>
      '\n***************************\n'
      'APPLICATION FAILED TO START\n'
      '***************************\n\n'
      'Description:\n\n$description\n\n'
      'Action:\n\n$action\n';
}

/// Turns startup errors into [FailureAnalysis] reports, like Spring Boot's
/// `FailureAnalyzers`; returns `null` for errors it does not recognise.
FailureAnalysis? analyzeFailure(Object error) {
  // The most specific cause wins (creation errors wrap the real problem).
  final chain = <Object>[error];
  for (var cause = _causeOf(error); cause != null; cause = _causeOf(cause)) {
    chain.add(cause);
  }
  for (final cause in chain.reversed) {
    final analysis = _analyze(cause, chain);
    if (analysis != null) {
      return analysis;
    }
  }
  return null;
}

Object? _causeOf(Object error) => switch (error) {
  BeansException(:final cause) => cause,
  _ => null,
};

String _creationPath(List<Object> chain) {
  final beans = [
    for (final error in chain)
      if (error is BeanCreationException) error.beanName,
  ];
  return beans.isEmpty ? '' : ' (while creating ${beans.join(' → ')})';
}

FailureAnalysis? _analyze(Object error, List<Object> chain) => switch (error) {
  NoUniqueBeanDefinitionException(
    :final type,
    :final candidates,
    :final requiredBy,
  ) =>
    FailureAnalysis(
      '${requiredBy == null ? 'A component' : "Bean '$requiredBy'"} required a '
          'single bean of type $type, but ${candidates.length} were found:\n'
          '${candidates.map((c) => '  - $c').join('\n')}',
      'Mark one of the beans @Primary, update the injection point to accept '
          'a List<$type>, or use @Qualifier to pick one.',
      error,
    ),
  NoSuchBeanDefinitionException(
    :final type,
    :final beanName,
    :final requiredBy,
  ) =>
    FailureAnalysis(
      '${requiredBy == null ? 'A component' : "Bean '$requiredBy'"} required '
          '${type != null ? 'a bean of type $type' : "a bean named '$beanName'"} '
          'that could not be found${_creationPath(chain)}.',
      'Declare a bean of that type (a @Component class or a @Bean method), '
          'check its @Profile / conditions, or make the injection point '
          'nullable.',
      error,
    ),
  BeanCurrentlyInCreationException(:final cycle) => FailureAnalysis(
    'The dependencies of some of the beans form a cycle:\n\n'
        '${cycle.join(' → ')}',
    'Break the cycle: inject an ObjectProvider<T> on one side, or move the '
        'shared logic into a third bean.',
    error,
  ),
  PlaceholderResolutionException(:final placeholder) => FailureAnalysis(
    "Could not resolve placeholder '$placeholder'${_creationPath(chain)}.",
    "Define '$placeholder' in config/application.properties, on the command "
        'line (--$placeholder=...) or as an environment variable, or give '
        r'it a default: ${'
        '$placeholder:default}.',
    error,
  ),
  ConfigurationPropertiesBindException(:final prefix, :final errors) =>
    FailureAnalysis(
      "Binding to target properties under '$prefix' failed:\n\n"
          '${errors.map((e) => '  - $e').join('\n')}',
      "Update the application's configuration "
          '(config/application.properties, command line or environment).',
      error,
    ),
  _ => null,
};
