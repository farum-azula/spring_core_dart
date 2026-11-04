import 'dart:convert';

import 'package:spring_boot_dart/src/conditions.dart';
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:spring_boot_dart/src/properties/properties.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

/// The `messageSource` bean that serves translated texts from
/// `lib/resources/messages*.properties`, set up from `spring.messages.*`.
///
/// An application that puts `messages.properties`,
/// `messages_de.properties`, ... into `lib/resources/` can resolve texts by
/// code and locale (`messageSource.getMessage('cart.empty', locale: 'de')`)
/// and gets translated validation messages, with no bean to declare. The
/// bean is registered only when the bundle exists
/// ([MessagesBundleCondition]) and this context (not a parent) has no
/// bean named `messageSource`, so declaring your own replaces it.
///
/// Properties:
///
/// - `spring.messages.basename`: the bundles, comma-separated or a YAML
///   list, dots read as slashes; default `messages`.
/// - `spring.messages.encoding`: default `UTF-8`; an unknown encoding
///   fails the start.
/// - `spring.messages.use-code-as-default-message`: return the code
///   instead of failing for an unknown message; default `false`.
/// - `spring.messages.always-use-message-format`: format messages without
///   arguments too (so `''` becomes `'`); default `false`.
/// - `spring.messages.common-messages`: property files with messages for
///   every locale, comma-separated; a later file wins.
/// - `spring.messages.fallback-to-system-locale`: default `true`.
/// - `spring.messages.cache-duration`: how long loaded files are kept, in
///   seconds without a unit (`10`) or any duration (`500ms`); kept forever
///   by default.
/// - `spring.messages.default-locale`: the locale tried before the system
///   locale. Not in Spring Boot.
///
/// ```properties
/// # lib/resources/application.properties
/// spring.messages.basename=i18n/messages,i18n/errors
/// ```
///
/// Spring (Java): `MessageSourceAutoConfiguration`, with the same
/// properties.
final messageSourceAutoConfiguration = <BeanDefinition<Object>>[
  BeanDefinition<ReloadableResourceBundleMessageSource>(
    name: 'messageSource',
    // A @Bean method: its bean conditions are decided when it is read.
    factoryMethodName: 'messageSource',
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
          ConditionalOnMissingBean.named(
            'messageSource',
            search: SearchStrategy.current,
          ),
          MessagesBundleCondition(),
        ],
      ),
    ],
    create: (r) {
      final properties = r.dependency<MessagesProperties>();
      final source = ReloadableResourceBundleMessageSource(
        basenames: [
          for (final basename in _basenames(properties.basename))
            'resources:$basename',
        ],
      );
      final encoding = properties.encoding;
      if (encoding != null && encoding.trim().isNotEmpty) {
        source.defaultEncoding =
            Encoding.getByName(encoding.trim()) ??
            (throw ArgumentError.value(
              encoding,
              'spring.messages.encoding',
              'Unsupported encoding',
            ));
      }
      final common = properties.commonMessages ?? const [];
      if (common.isNotEmpty) {
        final loader = r.dependency<ResourceLoader>();
        source.commonMessages = {
          for (final location in common)
            ...PropertiesLoaderUtils.loadPropertiesSync(
              loader.getResource(location.trim()),
              encoding: source.defaultEncoding,
            ),
        };
      }
      source
        ..useCodeAsDefaultMessage = properties.useCodeAsDefaultMessage
        ..alwaysUseMessageFormat = properties.alwaysUseMessageFormat
        ..fallbackToSystemLocale = properties.fallbackToSystemLocale;
      if (properties.cacheDuration case final cacheDuration?) {
        source.cacheMillis = cacheDuration.inMilliseconds;
      }
      if (properties.defaultLocale case final locale?) {
        source.defaultLocale = locale;
      }
      return source;
    },
  ),
];

/// A condition that matches when the message bundle exists, that is when
/// `resources:<basename>.properties` exists for one of the configured
/// basenames.
///
/// It keeps the auto-configured `messageSource` out of applications that
/// have no messages file. A starter that ships its own message-based bean
/// can reuse it:
///
/// ```dart
/// @Bean()
/// @MessagesBundleCondition()
/// ErrorTexts errorTexts(MessageSource messages) => ErrorTexts(messages);
/// ```
///
/// Spring (Java): Spring Boot's `ResourceBundleCondition`, internal to
/// `MessageSourceAutoConfiguration`.
class MessagesBundleCondition implements Condition {
  /// The condition; it reads `spring.messages.basename` when evaluated.
  const MessagesBundleCondition();

  /// The bundle basenames of [environment]'s `spring.messages.basename`,
  /// as paths below `lib/resources/`; `['messages']` when it is not set.
  ///
  /// The property is a comma list (`a,b`) or a YAML list
  /// (`spring.messages.basename[0]`). Dots are read as slashes, so
  /// `config.i18n.messages` is `config/i18n/messages`.
  static List<String> basenames(Environment environment) => _basenames(
    bindBootProperties(environment, MessagesProperties()).basename,
  );

  @override
  bool matches(ConditionContext context) => basenames(context.environment).any(
    (basename) => context.resourceLoader
        .getResource('resources:$basename.properties')
        .exists(),
  );
}

// `config.i18n.messages` is `config/i18n/messages`, like Boot's
// ResourceBundleCondition.
List<String> _basenames(List<String> names) => [
  for (final name in names)
    if (name.trim().isNotEmpty) name.trim().replaceAll('.', '/'),
];
