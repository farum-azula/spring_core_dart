import 'package:spring_core_dart/src/core/env/platform_environment_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/env/platform_environment_io.dart';

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

/// A [MessageSourceResolvable] that can opt out of formatting its default
/// message, like Spring's `DefaultMessageSourceResolvable
/// .shouldRenderDefaultMessage()`.
///
/// Errors created from Bean Validation violations implement it: their
/// default message (`can't be blank`, `must match "[A-Z]{2,3}"`) is shown
/// as-is unless it contains `{0}`-style placeholders.
abstract interface class DefaultMessageRendering {
  /// Whether the default message is run through `MessageFormat` with the
  /// arguments; `false` returns it unchanged.
  bool get shouldRenderDefaultMessage;
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
/// Locales are `language[_Script][_REGION][_variant]`, the form of
/// resource bundle file names (`messages_zh_Hant_TW.properties`).
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

  /// The locale of the platform, like Java's `Locale.getDefault()`:
  /// `Platform.localeName` normalized (`en_US.UTF-8` → `en_US`; `C` /
  /// `POSIX` and the web give `''`). Assign a locale to override it (like
  /// `Locale.setDefault`), `null` to detect it again.
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

  /// `ru-RU` / `ru_ru` → `ru_RU`; `zh-hant-tw` (or Java's `zh_TW_#Hant`)
  /// → `zh_Hant_TW`; `null`/empty → `''`.
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

  /// The locales a bundle is looked up in, most specific first, like
  /// Java's `ResourceBundle.Control.getCandidateLocales` (without the
  /// root): `ru_RU_x` → `[ru_RU_x, ru_RU, ru]`; `zh_Hant_TW` →
  /// `[zh_Hant_TW, zh_Hant, zh_TW, zh]`.
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
