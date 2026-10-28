import 'package:spring_boot_dart/src/configuration_properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// A plain-language explanation of why the application failed to start,
/// with what to do about it.
///
/// A start that fails deep in bean creation produces a long chain of
/// wrapped exceptions. Instead of the stack trace, `SpringApplication`
/// prints an `APPLICATION FAILED TO START` report built from one of these:
/// a [description] of the problem and an [action] to fix it. The built-in
/// analysis covers missing and ambiguous beans, dependency cycles,
/// unresolved placeholders, duplicate bean names, missing config files and
/// invalid properties. A [FailureAnalyzer] returns one for errors of your
/// own.
///
/// Spring (Java): `FailureAnalysis`, with the same three parts.
final class FailureAnalysis {
  /// An analysis that explains [cause] with [description] and suggests
  /// [action].
  const FailureAnalysis(this.description, this.action, this.cause);

  /// What went wrong, in terms of the application (the bean, property or
  /// file involved). It may span several lines.
  final String description;

  /// What the developer should do to fix it.
  final String action;

  /// The error that was analyzed.
  final Object cause;

  /// The whole report as it is printed when the start fails, with the
  /// [description] and [action] filled in:
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

/// Explains a startup error that `spring_boot_dart` does not know, as an
/// `APPLICATION FAILED TO START` report instead of a stack trace.
///
/// A library that fails the start in a predictable way (a port already
/// in use, a database that cannot be reached, a missing licence key) can
/// tell the developer what happened and how to fix it. Declare the
/// analyzer as a bean (a starter puts it in its auto-configuration), or
/// pass it to `SpringApplication(failureAnalyzers: ...)`. When the start
/// fails, the analyzers passed to the constructor are asked first, then
/// the beans sorted by `@Order`, then the built-in analysis; the first
/// non-null answer is reported. Analyzer beans are only found when the
/// context got far enough to create them.
///
/// [analyze] receives the error as it was thrown. An error raised while a
/// bean is created is often wrapped in a `BeanCreationException`, so walk
/// the `cause` chain when needed.
///
/// ```dart
/// // The web server could not bind its port.
/// class PortInUseFailureAnalyzer implements FailureAnalyzer {
///   @override
///   FailureAnalysis? analyze(Object failure) => failure is PortInUseException
///       ? FailureAnalysis(
///           'Port ${failure.port} is already in use.',
///           'Stop the other process or set server.port.',
///           failure,
///         )
///       : null;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class PortInUseFailureAnalyzer
///     extends AbstractFailureAnalyzer<PortInUseException> {
///   @Override
///   protected FailureAnalysis analyze(Throwable root, PortInUseException ex) {
///     return new FailureAnalysis("Port " + ex.getPort() + " is in use.",
///         "Stop the other process or set server.port.", ex);
///   }
/// }
/// ```
abstract interface class FailureAnalyzer {
  /// An explanation of [failure], or `null` when this analyzer does not
  /// recognise it and the next one should be asked.
  FailureAnalysis? analyze(Object failure);
}

/// Explains a startup error: the [FailureAnalysis] that `SpringApplication`
/// prints when the start fails, or `null` when nothing recognises [error].
///
/// [analyzers] are asked first, in the given order, and the first analysis
/// wins. Then the built-in analysis looks at [error] and the causes it
/// wraps (through `BeansException.cause`), starting with the innermost:
/// the real problem is usually the deepest one. Call it yourself to test
/// an analyzer, or to report a failure the same way in a tool.
///
/// ```dart
/// final analysis = analyzeFailure(
///   error,
///   analyzers: [PortInUseFailureAnalyzer()],
/// );
/// print(analysis?.report ?? 'Application run failed: $error');
/// ```
///
/// Spring (Java): what Spring Boot's `FailureAnalyzers` does.
FailureAnalysis? analyzeFailure(
  Object error, {
  Iterable<FailureAnalyzer> analyzers = const [],
}) {
  for (final analyzer in analyzers) {
    final analysis = analyzer.analyze(error);
    if (analysis != null) {
      return analysis;
    }
  }
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
          // A string that cannot be split without changing it.
          // ignore: lines_longer_than_80_chars
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
    'Break the cycle: mark one injection point @Lazy() or inject an '
        'ObjectProvider<T> on one side, or move the shared logic into a third '
        'bean.',
    error,
  ),
  PlaceholderResolutionException(:final placeholder) => FailureAnalysis(
    "Could not resolve placeholder '$placeholder'${_creationPath(chain)}.",
    "Define '$placeholder' in lib/resources/application.properties, on the "
        'command line (--$placeholder=...) or as an environment variable, or '
        'give '
        r'it a default: ${'
        '$placeholder:default}.',
    error,
  ),
  // Boot's BeanDefinitionOverrideFailureAnalyzer.
  BeanDefinitionOverrideException(:final name, :final source) =>
    FailureAnalysis(
      "The bean '$name'${source == null ? '' : ', defined in $source,'} "
          'could not be registered. A bean with that name has already been '
          'defined and overriding is disabled.',
      'Consider renaming one of the beans or enabling overriding by setting '
          'spring.main.allow-bean-definition-overriding=true',
      error,
    ),
  // Boot's ConfigDataNotFoundFailureAnalyzer.
  ConfigDataResourceNotFoundException(:final location, :final description) =>
    FailureAnalysis(
      "Config data resource '$description' via location '$location' does "
          'not exist',
      "Check that the value '$location' is correct, or prefix it with "
          "'optional:'",
      error,
    ),
  ConfigDataLocationNotFoundException(:final location) => FailureAnalysis(
    "Config data location '$location' does not exist",
    "Check that the value '$location' is correct, or prefix it with "
        "'optional:'",
    error,
  ),
  // Boot's InvalidConfigurationPropertyNameFailureAnalyzer.
  InvalidConfigurationPropertyNameException(
    :final name,
    :final invalidCharacters,
  ) =>
    FailureAnalysis(
      "Configuration property name '$name' is not valid:\n\n"
          '    Invalid characters: ${invalidCharacters.join(', ')}\n'
          "    Reason: Canonical names should be kebab-case ('-' separated), "
          'lowercase alpha-numeric characters and must start with a letter',
      "Modify '$name' so that it conforms to the canonical names "
          'requirements.',
      error,
    ),
  ConfigurationPropertiesBindException(:final prefix, :final errors) =>
    FailureAnalysis(
      "Binding to target properties under '$prefix' failed:\n\n"
          '${errors.map((e) => '  - $e').join('\n')}',
      "Update the application's configuration "
          '(lib/resources/application.properties, command line or '
          'environment).',
      error,
    ),
  _ => null,
};
