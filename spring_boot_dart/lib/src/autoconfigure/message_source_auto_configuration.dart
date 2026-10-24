import 'package:spring_boot_dart/src/binder.dart';
import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// Registers a `messageSource` reading `classpath:<basename>*.properties`
/// when the application has no bean named `messageSource`, like Spring Boot's
/// `MessageSourceAutoConfiguration`.
///
/// Properties: `spring.messages.basename` (comma-separated, default
/// `messages`), `spring.messages.use-code-as-default-message`,
/// `spring.messages.fallback-to-system-locale` (default `true`),
/// `spring.messages.cache-duration` (seconds without a unit, e.g. `10`,
/// or any duration such as `500ms`; cached forever by default) and `spring.messages.default-locale` (not in Spring
/// Boot: the locale tried before the system locale).
///
/// ```properties
/// # lib/resources/application.properties
/// spring.messages.basename=i18n/messages,i18n/errors
/// ```
final messageSourceAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ReloadableResourceBundleMessageSource>(
    name: 'messageSource',
    types: const [
      ReloadableResourceBundleMessageSource,
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
      final source = ReloadableResourceBundleMessageSource(
        basenames: [
          for (final basename in MessagesBundleCondition.basenames(environment))
            'classpath:$basename',
        ],
      );
      bool flag(String name, {required bool orElse}) =>
          environment.getPropertyAs<bool>(name) ?? orElse;
      // Booleans bind case-insensitively, like Boot's binding.
      source
        ..useCodeAsDefaultMessage = flag(
          'spring.messages.use-code-as-default-message',
          orElse: false,
        )
        ..fallbackToSystemLocale = flag(
          'spring.messages.fallback-to-system-locale',
          orElse: true,
        );
      final cacheDuration = environment.getProperty(
        'spring.messages.cache-duration',
      );
      if (cacheDuration != null && cacheDuration.trim().isNotEmpty) {
        // Seconds without a unit (Boot's @DurationUnit(SECONDS)), any
        // unit otherwise: `500ms` caches for half a second.
        final value = cacheDuration.trim();
        final seconds = int.tryParse(value);
        source.cacheMillis = seconds != null
            ? seconds * 1000
            : environment
                  .getPropertyAs<Duration>('spring.messages.cache-duration')!
                  .inMilliseconds;
      }
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

  /// The configured bundle basenames (`spring.messages.basename`), dots
  /// read as slashes (`config.i18n.messages` → `config/i18n/messages`).
  ///
  /// A comma list (`a,b`) or a YAML list (`spring.messages.basename[0]`).
  static List<String> basenames(Environment environment) => [
    for (final name
        in environment is ConfigurableEnvironment
            ? Binder.get(environment)
                  .bind(
                    'spring.messages.basename',
                    const ListType<String>(ClassType<String>()),
                  )
                  .orElse(const ['messages'])
            : (environment.getProperty('spring.messages.basename') ??
                      'messages')
                  .split(','))
      // `config.i18n.messages` is `config/i18n/messages`, like Boot's
      // ResourceBundleCondition.
      if (name.trim().isNotEmpty) name.trim().replaceAll('.', '/'),
  ];

  @override
  bool matches(ConditionContext context) => basenames(context.environment).any(
    (basename) => context.resourceLoader
        .getResource('classpath:$basename.properties')
        .exists(),
  );
}
