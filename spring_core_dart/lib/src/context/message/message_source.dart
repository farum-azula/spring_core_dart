import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';

/// A message described by codes rather than text: the codes to look up,
/// the arguments to fill in and a default text.
///
/// It lets code that produces a message (a validator, a service throwing a
/// business error) leave the wording and the translation to the
/// `MessageSource`. Several codes go from specific to general, so that a
/// translation can target one form field or all of them. Validation errors
/// implement it; most applications only pass such objects to
/// [MessageSource.getMessageFromResolvable], or use
/// [DefaultMessageSourceResolvable].
///
/// ```dart
/// // "required.user.email" if translated, else "required", else the
/// // default text.
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
  /// The codes tried in order; the last is the most general.
  List<String> get codes;

  /// The values for the `{0}`, `{1}`, ... placeholders; an argument that is
  /// itself a [MessageSourceResolvable] is translated first.
  List<Object?> get arguments;

  /// The text used when no code is found; `null` makes a missing message
  /// an error.
  String? get defaultMessage;
}

/// Implemented by a [MessageSourceResolvable] whose default message must
/// not go through `MessageFormat`.
///
/// `MessageFormat` treats quotes and braces as syntax, which would mangle
/// a default text such as `can't be blank` or `must match "[A-Z]{2,3}"`.
/// Errors created from validation violations implement it, so their
/// default message is shown as it is unless it contains `{0}`-style
/// placeholders. Application code rarely needs it.
///
/// Spring (Java):
/// `DefaultMessageSourceResolvable.shouldRenderDefaultMessage()`.
abstract interface class DefaultMessageRendering {
  /// Whether the default message is formatted with the arguments through
  /// `MessageFormat`; `false` returns it unchanged.
  bool get shouldRenderDefaultMessage;
}

/// A ready-made [MessageSourceResolvable]: codes, arguments and a default
/// message given as values.
///
/// Use it to pass a message by code to code that translates it later, for
/// example an error a service returns and the UI shows in the user's
/// language, or a translated label as an argument of another message.
///
/// ```dart
/// // The German error text, or "Invalid e-mail" when none is defined.
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
  /// Creates a resolvable that tries [codes] in order, fills in
  /// [arguments] and falls back to [defaultMessage].
  const DefaultMessageSourceResolvable(
    this.codes, {
    this.arguments = const [],
    this.defaultMessage,
  });

  /// Creates a resolvable with a single [code].
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

/// Turns a message code and a locale into a text in that language, with
/// the arguments filled in.
///
/// Use it for every text a user reads that must be translated: labels,
/// e-mails, error messages. The texts live in files such as
/// `messages.properties` and `messages_de.properties`
/// (`greeting=Hello, {0}!`), and code refers to them by code
/// (`greeting`). Inject `MessageSource` into a bean, or call `getMessage`
/// on the context, which is a message source too.
///
/// With Spring Boot, putting `messages*.properties` into `lib/resources/`
/// is enough (`spring.messages.basename` names other files). Without it,
/// declare a bean named `messageSource`, usually a
/// `ReloadableResourceBundleMessageSource`. Locales are strings such as
/// `ru_RU`, `ru-RU` or `ru` (see [Locales]).
///
/// ```dart
/// // Without Spring Boot: the messages come from i18n/messages*.properties.
/// @Configuration()
/// class I18nConfig {
///   @Bean()
///   MessageSource messageSource() =>
///       ReloadableResourceBundleMessageSource(
///         basenames: ['file:i18n/messages'],
///       );
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
/// locale and the base file are consulted.
abstract interface class MessageSource {
  /// The text for [code] in [locale], with [args] filled into its `{0}`,
  /// `{1}`, ... placeholders.
  ///
  /// When the code is not found, [defaultMessage] is formatted with [args]
  /// instead; without one, a [NoSuchMessageException] is thrown. Without a
  /// [locale], only the default locale and the base file are consulted.
  ///
  /// ```dart
  /// // "You have 3 items" in English.
  /// source.getMessage('cart.items', args: [3], locale: 'en');
  /// source.getMessage('missing', defaultMessage: 'Fallback {0}', args: [1]);
  /// ```
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  });

  /// The text for the first code of [resolvable] found in [locale], with
  /// its arguments filled in; else its default message; else a
  /// [NoSuchMessageException]. Use it to show validation errors and other
  /// messages described by codes.
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  });
}

/// A [MessageSource] that asks a parent message source for the codes it
/// does not have.
///
/// A child context's message source gets the parent context's as its
/// parent automatically. Set one yourself to share common texts between
/// several sources.
///
/// ```dart
/// // A feature's messages, with the shared ones as fallback.
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
  /// The source asked when this one has no message for a code; `null` for
  /// none.
  MessageSource? get parentMessageSource;

  /// Sets the source asked when this one has no message for a code.
  set parentMessageSource(MessageSource? parent);
}

/// Thrown when a message code is not found and no default message was
/// given.
///
/// It usually means a translation is missing from a `messages*.properties`
/// file. Spring Boot's `spring.messages.use-code-as-default-message=true`
/// returns the code instead of throwing.
///
/// ```dart
/// try {
///   source.getMessage('unknown');
/// } on NoSuchMessageException catch (e) {
///   log.warning(e.code); // unknown
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
  /// Creates the error for [code] and the requested [locale].
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

/// Helpers for locales written as strings, such as `de_CH`.
///
/// This package passes locales as strings in the form
/// `language[_Script][_REGION][_variant]`, the form of message file names
/// (`messages_zh_Hant_TW.properties`). These helpers bring other spellings
/// to that form, list the files a message is looked up in, and hold the
/// platform's default locale. Applications mostly use [systemLocale] to
/// fix the default locale, for example in tests.
///
/// ```dart
/// Locales.normalize('ru-ru'); // 'ru_RU'
/// Locales.normalize('zh-hant-tw'); // 'zh_Hant_TW'
/// Locales.candidates('de_CH'); // ['de_CH', 'de']
/// Locales.candidates('zh_Hant_TW'); // ['zh_Hant_TW', 'zh_Hant', 'zh_TW', 'zh']
/// ```
///
/// Spring (Java) uses `java.util.Locale` objects instead:
/// ```java
/// Locale locale = Locale.forLanguageTag("zh-Hant-TW"); // zh_TW_#Hant
/// ResourceBundle.Control.getControl(FORMAT_DEFAULT)
///     .getCandidateLocales("messages", locale);
/// ```
abstract final class Locales {
  static String? _systemLocale;

  /// The default locale of the machine, used when a message is not found
  /// in the requested locale.
  ///
  /// It is `Platform.localeName` normalized (`en_US.UTF-8` becomes
  /// `en_US`; `C`, `POSIX` and the web give `''`), as Java's
  /// `Locale.getDefault()`. Assign a locale to override it, for example to
  /// make tests independent of the machine (Java's `Locale.setDefault`);
  /// assign `null` to detect it again.
  ///
  /// ```dart
  /// Locales.systemLocale = 'de_DE';
  /// ```
  static String get systemLocale =>
      _systemLocale ??= _platformLocale(platformLocaleName());

  static set systemLocale(String? locale) =>
      _systemLocale = locale == null ? null : _platformLocale(locale);

  static String _platformLocale(String name) {
    // POSIX form: language_REGION.codeset@modifier.
    final plain = name.split(RegExp('[.@]')).first;
    return plain == 'C' || plain == 'POSIX' ? '' : normalize(plain);
  }

  /// Brings [locale] to the form used in file names: `ru-RU` and `ru_ru`
  /// become `ru_RU`, `zh-hant-tw` (or Java's `zh_TW_#Hant`) becomes
  /// `zh_Hant_TW`, and `null` or an empty string gives `''`.
  static String normalize(String? locale) {
    final parsed = _parse(locale);
    if (parsed == null) {
      return '';
    }
    final (:language, :script, :region, :variants) = parsed;
    return [
      language,
      ?script,
      if (region != null || variants.isNotEmpty) region ?? '',
      ...variants,
    ].join('_');
  }

  /// The locales whose files are searched for a message of [locale], most
  /// specific first: `ru_RU_x` gives `[ru_RU_x, ru_RU, ru]`, `zh_Hant_TW`
  /// gives `[zh_Hant_TW, zh_Hant, zh_TW, zh]`. The base file (no locale)
  /// is not included. Java's `ResourceBundle.Control.getCandidateLocales`.
  static List<String> candidates(String locale) {
    final parsed = _parse(locale);
    if (parsed == null) {
      return const [];
    }
    final (:language, :script, :region, :variants) = parsed;
    // language_[script_]region_variants..., dropping variants from the end,
    // then the region, then the script.
    List<String> chain(String? script) => [
      for (var i = variants.length; i > 0; i--)
        [language, ?script, region ?? '', ...variants.take(i)].join('_'),
      if (region != null) [language, ?script, region].join('_'),
      [language, ?script].join('_'),
    ];
    return {...chain(script), if (script != null) ...chain(null)}.toList();
  }

  static ({
    String language,
    String? script,
    String? region,
    List<String> variants,
  })?
  _parse(String? locale) {
    if (locale == null || locale.trim().isEmpty) {
      return null;
    }
    final parts = locale.trim().replaceAll('-', '_').split('_');
    // Java's toString puts the script last, after `#`: `zh_TW_#Hant`.
    String? script;
    final hashed = parts.indexWhere((p) => p.startsWith('#'));
    if (hashed > 0) {
      script = _titleCase(parts.removeAt(hashed).substring(1));
    }
    var i = 1;
    if (script == null &&
        i < parts.length &&
        RegExp(r'^[A-Za-z]{4}$').hasMatch(parts[i])) {
      script = _titleCase(parts[i]);
      i++;
    }
    String? region;
    if (i < parts.length) {
      region = parts[i].isEmpty ? null : parts[i].toUpperCase();
      i++;
    }
    return (
      language: parts.first.toLowerCase(),
      script: script,
      region: region,
      variants: parts.skip(i).toList(),
    );
  }

  static String _titleCase(String text) => text.isEmpty
      ? text
      : text[0].toUpperCase() + text.substring(1).toLowerCase();
}
