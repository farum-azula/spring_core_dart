import 'package:spring_core_dart/spring_core_dart.dart';

/// Registers the bean only when property [name] has [havingValue] (any
/// value other than `false` when [havingValue] is `null`), like Spring
/// Boot's `@ConditionalOnProperty`.
///
/// ```dart
/// @Service()
/// @ConditionalOnProperty('feature.search', matchIfMissing: true)
/// class SearchService {}
/// ```
///
/// Spring (Java):
/// ```java
/// @ConditionalOnProperty(name = "feature.search", matchIfMissing = true)
/// ```
class ConditionalOnProperty implements Condition {
  /// Checks property [name].
  const ConditionalOnProperty(
    this.name, {
    this.havingValue,
    this.matchIfMissing = false,
  });

  /// The property to check.
  final String name;

  /// Expected value (case-insensitive); `null` accepts anything but `false`.
  final String? havingValue;

  /// Whether a missing property matches.
  final bool matchIfMissing;

  @override
  bool matches(ConditionContext context) {
    final value = context.environment.getProperty(name);
    if (value == null) {
      return matchIfMissing;
    }
    final expected = havingValue;
    return expected == null
        ? value.toLowerCase() != 'false'
        : value.toLowerCase() == expected.toLowerCase();
  }
}

/// Registers the bean only when a bean of [type] is already registered,
/// like Spring Boot's `@ConditionalOnBean`.
///
/// Conditions see the definitions registered before them: put them on
/// auto-configuration (registered after the application's beans). Like
/// Boot 3.4+, beans with `autowireCandidate: false` or
/// `defaultCandidate: false` do not count (for [ConditionalOnMissingBean]
/// either); beans of parent contexts do.
///
/// ```dart
/// @Bean()
/// @ConditionalOnBean(DataSource)
/// Migrations migrations(DataSource source) => Migrations(source);
/// ```
///
/// Spring (Java): `@ConditionalOnBean(DataSource.class)`.
class ConditionalOnBean implements Condition {
  /// Requires a bean of [type].
  const ConditionalOnBean(this.type);

  /// The required bean type.
  final Type type;

  @override
  bool matches(ConditionContext context) =>
      context.beanFactory.containsBeanOfType(type);
}

/// Registers the bean only when no bean of [type] is registered yet, like
/// Spring Boot's `@ConditionalOnMissingBean`: the default a library
/// provides backs off when the application declares its own bean.
///
/// ```dart
/// @AutoConfiguration()
/// class HttpAutoConfiguration {
///   @Bean()
///   @ConditionalOnMissingBean(HttpClientSettings)
///   HttpClientSettings httpSettings() => HttpClientSettings();
/// }
/// ```
///
/// Spring (Java): `@ConditionalOnMissingBean` (the type is inferred from the
/// `@Bean` method there; here it is given explicitly).
class ConditionalOnMissingBean implements Condition {
  /// Requires that no bean of [type] exists.
  const ConditionalOnMissingBean(Type this.type) : name = null;

  /// Requires that no bean named [name] exists (Spring's
  /// `@ConditionalOnMissingBean(name = "...")`).
  const ConditionalOnMissingBean.named(String this.name) : type = null;

  /// The bean type that must be missing.
  final Type? type;

  /// The bean name that must be missing.
  final String? name;

  @override
  bool matches(ConditionContext context) => name != null
      ? !context.beanFactory.containsBean(name!)
      : !context.beanFactory.containsBeanOfType(type!);
}
