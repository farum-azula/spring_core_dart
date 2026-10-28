import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#ValidationAutoConfiguration';

/// The beans that make validation work without setup: a `Validator` for
/// the constraint annotations, and method validation of `@Validated()`
/// beans.
///
/// Every application gets them through `springBootAutoConfiguration`:
///
/// - `defaultValidator`, a [BeanValidator] that checks constraint
///   annotations such as `@NotBlank()`, using the context's
///   [BeanIntrospector]. Inject `Validator` to validate objects by hand.
///   It is left out when the application declares its own [BeanValidator];
///   a bean that only implements the plain `Validator` interface does not
///   replace it (as in Spring Boot, where only a
///   `jakarta.validation.Validator` does).
/// - `methodValidationPostProcessor`, which checks the parameters and
///   return values of the methods of `@Validated()` beans with the single
///   [BeanValidator] bean, or a new one when there is none or several.
///   `@ConfigurationProperties` classes are left out: there `@Validated()`
///   means validation after binding instead. It is left out when the
///   application declares its own `MethodValidationPostProcessor`.
///
/// Switch both off with
/// `spring.autoconfigure.exclude=ValidationAutoConfiguration`.
///
/// Spring (Java): `ValidationAutoConfiguration`.
final validationAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<BeanValidator>(
    name: 'defaultValidator',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'defaultValidator',
    types: const [BeanValidator, SmartValidator, Validator],
    source: _source,
    // Method-level conditions (Boot's @Bean @ConditionalOnMissingBean),
    // so not a ConditionGroup shared by both beans.
    conditions: const [ConditionalOnMissingBean(BeanValidator)],
    create: (r) =>
        BeanValidator(introspector: r.dependency<BeanIntrospector>()),
  ),
  BeanDefinition<MethodValidationPostProcessor>(
    name: 'methodValidationPostProcessor',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'methodValidationPostProcessor',
    types: const [
      MethodValidationPostProcessor,
      PointcutAdvisor,
      Advisor,
      Ordered,
    ],
    source: _source,
    conditions: const [ConditionalOnMissingBean(MethodValidationPostProcessor)],
    create: (r) => MethodValidationPostProcessor(
      r.provider<BeanValidator>(name: 'validator').getIfUnique() ??
          BeanValidator(introspector: r.dependency<BeanIntrospector>()),
      [_isConfigurationProperties],
    ),
  ),
];

bool _isConfigurationProperties(List<Object> classAnnotations) =>
    classAnnotations.any((a) => a is ConfigurationProperties);
