import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Registers a `messageSource` reading `classpath:<basename>*.properties`
/// when the application has no bean named `messageSource`, like Spring Boot's
/// `MessageSourceAutoConfiguration`.
///
/// Properties: `spring.messages.basename` (comma-separated, default
/// `messages`), `spring.messages.use-code-as-default-message`,
/// `spring.messages.fallback-to-system-locale` (here: to
/// `spring.messages.default-locale`).
///
/// ```properties
/// # lib/resources/application.properties
/// spring.messages.basename=i18n/messages,i18n/errors
/// ```
final messageSourceAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<PropertiesMessageSource>(
    name: 'messageSource',
    types: const [
      PropertiesMessageSource,
      MessageSource,
      HierarchicalMessageSource,
    ],
    source: 'package:spring_boot_dart#MessageSourceAutoConfiguration',
    conditions: const [
      ConditionGroup(
        'package:spring_boot_dart#MessageSourceAutoConfiguration',
        [
          ConditionalOnMissingBean.named('messageSource'),
          MessagesBundleCondition(),
        ],
      ),
    ],
    create: (r) {
      final environment = r.dependency<Environment>();
      final source = PropertiesMessageSource(
        basenames: [
          for (final basename in MessagesBundleCondition.basenames(environment))
            'classpath:$basename',
        ],
      );
      source.useCodeAsDefaultMessage =
          environment.getProperty(
            'spring.messages.use-code-as-default-message',
          ) ==
          'true';
      final locale = environment.getProperty('spring.messages.default-locale');
      if (locale != null) {
        source.defaultLocale = locale;
      }
      return source;
    },
  ),
];

/// Matches when a `classpath:<basename>.properties` bundle exists (Spring
/// Boot's `ResourceBundleCondition`).
class MessagesBundleCondition implements Condition {
  /// Creates the condition.
  const MessagesBundleCondition();

  /// The configured bundle basenames (`spring.messages.basename`).
  static List<String> basenames(Environment environment) => [
    for (final name
        in (environment.getProperty('spring.messages.basename') ?? 'messages')
            .split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  @override
  bool matches(ConditionContext context) => basenames(context.environment).any(
    (basename) => context.resourceLoader
        .getResource('classpath:$basename.properties')
        .exists(),
  );
}
