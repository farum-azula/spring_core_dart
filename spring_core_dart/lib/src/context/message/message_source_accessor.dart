import 'package:spring_core_dart/src/context/message/message_source.dart';

/// A wrapper around a [MessageSource] that remembers a locale, so that
/// lookups need not pass it every time.
///
/// Use it where all messages are in one language chosen once, such as a
/// command-line tool or a screen built for the user's language. A lookup
/// can still pass its own locale.
///
/// ```dart
/// // German by default, English on request.
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

  /// The source the lookups go to.
  final MessageSource messageSource;

  /// The locale of lookups that pass none; `null` leaves the choice to
  /// the message source (its fallback locale and base messages).
  final String? defaultLocale;

  /// The text for [code] in [locale], else in [defaultLocale]; otherwise
  /// the same as [MessageSource.getMessage].
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

  /// The text for [resolvable] in [locale], else in [defaultLocale];
  /// otherwise the same as [MessageSource.getMessageFromResolvable].
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  }) => messageSource.getMessageFromResolvable(
    resolvable,
    locale: locale ?? defaultLocale,
  );
}
