import 'package:spring_core_dart/src/context/message/message_source.dart';

/// A [MessageSource] with a default locale, like Spring's
/// `MessageSourceAccessor`: lookups without a locale use [defaultLocale].
///
/// ```dart
/// final messages = MessageSourceAccessor(context, defaultLocale: 'de');
/// messages.getMessage('greeting', args: ['Ada']); // Hallo Ada
/// messages.getMessage('greeting', args: ['Ada'], locale: 'en'); // Hello Ada
/// ```
///
/// Spring (Java):
/// ```java
/// var messages = new MessageSourceAccessor(context, Locale.GERMAN);
/// messages.getMessage("greeting", new Object[] {"Ada"});
/// ```
///
/// Unlike Spring there is no `LocaleContextHolder`: without a
/// [defaultLocale] the message source decides (its base messages and
/// fallback locale).
class MessageSourceAccessor {
  /// Wraps [messageSource]; [defaultLocale] is used when a lookup passes
  /// no locale.
  MessageSourceAccessor(this.messageSource, {this.defaultLocale});

  /// The wrapped source.
  final MessageSource messageSource;

  /// The locale of lookups that pass none, or `null`.
  final String? defaultLocale;

  /// [MessageSource.getMessage] in [locale] (or [defaultLocale]).
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  }) => messageSource.getMessage(
    code,
    args: args,
    defaultMessage: defaultMessage,
    locale: locale ?? defaultLocale,
  );

  /// [MessageSource.getMessageFromResolvable] in [locale] (or
  /// [defaultLocale]).
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  }) => messageSource.getMessageFromResolvable(
    resolvable,
    locale: locale ?? defaultLocale,
  );
}
