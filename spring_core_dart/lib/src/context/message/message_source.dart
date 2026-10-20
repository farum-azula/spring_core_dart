/// Something that can be resolved to a message, like Spring's
/// `MessageSourceResolvable`.
///
/// Typical for validation errors: several codes from specific to general,
/// arguments and a default text.
///
/// ```dart
/// class FieldError implements MessageSourceResolvable {
///   FieldError(this.field);
///   final String field;
///
///   @override
///   List<String> get codes => ['required.user.$field', 'required'];
///
///   @override
///   List<Object?> get arguments => [field];
///
///   @override
///   String? get defaultMessage => '$field is required';
/// }
///
/// messageSource.getMessageFromResolvable(FieldError('email'));
/// ```
///
/// Spring (Java):
/// ```java
/// class FieldError implements MessageSourceResolvable {
///   public String[] getCodes() { ... }
///   public Object[] getArguments() { ... }
///   public String getDefaultMessage() { ... }
/// }
/// ```
abstract interface class MessageSourceResolvable {
  /// Codes tried in order; the last is the most general.
  List<String> get codes;

  /// Arguments; resolvable arguments are resolved recursively.
  List<Object?> get arguments;

  /// Used when no code resolves.
  String? get defaultMessage;
}

/// Plain [MessageSourceResolvable], like Spring's
/// `DefaultMessageSourceResolvable`.
///
/// ```dart
/// final message = context.getMessageFromResolvable(
///   const DefaultMessageSourceResolvable(
///     ['error.user.email', 'error.email'],
///     arguments: ['ada@'],
///     defaultMessage: 'Invalid e-mail',
///   ),
///   locale: 'de',
/// );
///
/// // Resolvables can be arguments of other messages:
/// context.getMessage(
///   'field.required',
///   args: [DefaultMessageSourceResolvable.code('label.email')],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// String message = context.getMessage(
///     new DefaultMessageSourceResolvable(
///         new String[] {"error.user.email", "error.email"},
///         new Object[] {"ada@"}, "Invalid e-mail"),
///     Locale.GERMAN);
/// ```
final class DefaultMessageSourceResolvable implements MessageSourceResolvable {
  /// Creates a resolvable trying [codes] in order.
  const DefaultMessageSourceResolvable(
    this.codes, {
    this.arguments = const [],
    this.defaultMessage,
  });

  /// A resolvable with a single code.
  DefaultMessageSourceResolvable.code(
    String code, {
    List<Object?> arguments = const [],
    String? defaultMessage,
  }) : this([code], arguments: arguments, defaultMessage: defaultMessage);

  @override
  final List<String> codes;

  @override
  final List<Object?> arguments;

  @override
  final String? defaultMessage;

  @override
  String toString() =>
      'codes $codes; arguments $arguments; default message [$defaultMessage]';
}

/// Resolves messages, like Spring's `MessageSource`.
///
/// Locales are strings such as `ru_RU`, `ru-RU` or `ru`. Every application
/// context is a message source; declare a bean named `messageSource` to
/// supply the messages.
///
/// ```dart
/// @Configuration()
/// class I18nConfig {
///   @Bean()
///   MessageSource messageSource() =>
///       PropertiesMessageSource(basenames: ['file:i18n/messages']);
/// }
///
/// final context = ApplicationContext.run([appBeans]);
/// context.getMessage('greeting', args: ['Ada'], locale: 'de');
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// MessageSource messageSource() {
///   var source = new ResourceBundleMessageSource();
///   source.setBasenames("i18n/messages");
///   return source;
/// }
///
/// context.getMessage("greeting", new Object[] {"Ada"}, Locale.GERMAN);
/// ```
///
/// Unlike Spring, `locale` is optional: without it only the default
/// locale and the base bundle are consulted.
abstract interface class MessageSource {
  /// The message for [code] formatted with [args]; [defaultMessage] when
  /// not found, otherwise `NoSuchMessageException`.
  ///
  /// ```dart
  /// source.getMessage('cart.items', args: [3], locale: 'en');
  /// source.getMessage('missing', defaultMessage: 'Fallback {0}', args: [1]);
  /// ```
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  });

  /// The message for the first resolvable code of [resolvable], else its
  /// default message, else `NoSuchMessageException`.
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  });
}

/// A [MessageSource] that falls back to a parent, like Spring's
/// `HierarchicalMessageSource`.
///
/// ```dart
/// final common = StaticMessageSource()..addMessage('ok', '', 'OK');
/// final feature = StaticMessageSource()..parentMessageSource = common;
/// feature.getMessage('ok'); // 'OK' from the parent
/// ```
///
/// Spring (Java):
/// ```java
/// var feature = new StaticMessageSource();
/// feature.setParentMessageSource(common);
/// ```
abstract interface class HierarchicalMessageSource implements MessageSource {
  /// The source asked when this one has no message; `null` for none.
  MessageSource? get parentMessageSource;

  /// Sets the fallback source.
  set parentMessageSource(MessageSource? parent);
}

/// No message found and no default given, like Spring's
/// `NoSuchMessageException`.
///
/// ```dart
/// try {
///   source.getMessage('unknown');
/// } on NoSuchMessageException catch (e) {
///   print(e.code); // unknown
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// try {
///   source.getMessage("unknown", null, locale);
/// } catch (NoSuchMessageException e) { ... }
/// ```
final class NoSuchMessageException implements Exception {
  /// Creates the exception for [code] and the requested [locale].
  NoSuchMessageException(this.code, [this.locale]);

  /// The code that was not found.
  final String code;

  /// The requested locale, or `null` when none was given.
  final String? locale;

  @override
  String toString() =>
      "NoSuchMessageException: No message found under code '$code'"
      "${locale == null ? '' : " for locale '$locale'"}.";
}

/// Locale helpers for string locales.
///
/// ```dart
/// Locales.normalize('ru-ru'); // 'ru_RU'
/// Locales.candidates('de_CH'); // ['de_CH', 'de']
/// ```
///
/// Spring (Java) uses `java.util.Locale` objects instead:
/// ```java
/// Locale locale = Locale.forLanguageTag("ru-RU"); // ru_RU
/// ```
abstract final class Locales {
  /// `ru-RU` / `ru_ru` → `ru_RU`; `null`/empty → `''`.
  static String normalize(String? locale) {
    if (locale == null || locale.trim().isEmpty) {
      return '';
    }
    final parts = locale.trim().replaceAll('-', '_').split('_');
    return [
      parts.first.toLowerCase(),
      if (parts.length > 1) parts[1].toUpperCase(),
      ...parts.skip(2),
    ].join('_');
  }

  /// `ru_RU_x` → `[ru_RU_x, ru_RU, ru]`.
  static List<String> candidates(String locale) {
    final normalized = normalize(locale);
    if (normalized.isEmpty) {
      return const [];
    }
    final parts = normalized.split('_');
    return [for (var i = parts.length; i > 0; i--) parts.take(i).join('_')];
  }
}
