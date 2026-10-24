import 'package:spring_boot_dart/src/annotations.dart';
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

const _source = 'package:spring_boot_dart#ValidationAutoConfiguration';

/// Registers a `defaultValidator` ([BeanValidator] on the context's
/// [BeanIntrospector]) when the application declares no [BeanValidator]
/// (Boot's `@ConditionalOnMissingBean(jakarta.validation.Validator.class)`:
/// plain form `Validator` beans don't count), and a
/// `methodValidationPostProcessor` that validates the methods of
/// `@Validated` beans with the unique [BeanValidator] (a new one when there
/// is none or several), like Spring Boot's `ValidationAutoConfiguration`.
/// `@ConfigurationProperties` classes are excluded from method validation
/// (their `@Validated` turns on binding validation instead).
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
