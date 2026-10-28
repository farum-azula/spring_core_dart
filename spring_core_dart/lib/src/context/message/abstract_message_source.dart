import 'package:spring_core_dart/src/context/message/message_format.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';

/// The base class for message sources: it does the locale fallbacks, the
/// formatting and the parent lookup, so that a subclass only says where
/// the texts are.
///
/// Extend it to read messages from a place this package does not support,
/// such as a database or a map built in code; implement [resolveCode] and
/// everything else is shared. Applications usually take
/// `ReloadableResourceBundleMessageSource` (files) or
/// [StaticMessageSource] (code) instead.
///
/// The lookup of code `c` for locale `ru_RU` tries `ru_RU`, then `ru`,
/// then the [fallbackLocale] and its own fallbacks, then the base (no
/// locale), then [commonMessages], then the parent. Locales with a script
/// follow Java's `ResourceBundle`: `zh_Hant_TW`, `zh_Hant`, `zh_TW`, `zh`.
/// Arguments that are [MessageSourceResolvable]s are resolved by this
/// source before the parent is asked, so a message of the parent can use
/// arguments only the child knows. Messages are formatted with the number
/// symbols of the requested locale.
///
/// ```dart
/// // Messages from a map: locale, then code, then pattern.
/// class MapMessageSource extends AbstractMessageSource {
///   MapMessageSource(this.bundles);
///
///   /// locale → code → pattern
///   final Map<String, Map<String, String>> bundles;
///
///   @override
///   String? resolveCode(String code, String locale) =>
///       bundles[locale]?[code];
/// }
///
/// final source = MapMessageSource({
///   '': {'hi': 'Hello {0}'},
///   'de': {'hi': 'Hallo {0}'},
/// })..useCodeAsDefaultMessage = true;
/// source.getMessage('hi', args: ['Ada'], locale: 'de_AT'); // Hallo Ada
/// ```
///
/// Spring (Java):
/// ```java
/// class MapMessageSource extends AbstractMessageSource {
///   protected MessageFormat resolveCode(String code, Locale locale) {
///     ...
///   }
/// }
/// ```
///
/// Unlike Spring, [resolveCode] returns the raw pattern (not a
/// `MessageFormat`) and the default locale is [defaultLocale] rather than
/// the JVM's `Locale.getDefault()`.
abstract class AbstractMessageSource implements HierarchicalMessageSource {
  /// The source asked for codes this one does not have; `null` for none.
  @override
  MessageSource? parentMessageSource;

  /// Whether an unknown code is returned as the message instead of
  /// throwing a [NoSuchMessageException]; `false` by default. Handy while
  /// translations are incomplete: the screen shows the code.
  bool useCodeAsDefaultMessage = false;

  /// Whether messages without arguments are formatted too, so that their
  /// quotes follow [MessageFormat] rules (`''` becomes `'`); `false` by
  /// default, which returns them as written. When it is `true`, an invalid
  /// pattern throws a `FormatException` instead of being returned as is.
  bool alwaysUseMessageFormat = false;

  /// Messages that are the same in every language, by code; tried after
  /// all locales and before the parent.
  Map<String, String>? commonMessages;

  /// The locale tried after the requested one (Spring's default locale),
  /// for example the language most texts are written in; empty means none
  /// (see [fallbackLocale]).
  String defaultLocale = '';

  /// The locale tried when the requested one has no message (`''` for
  /// none): [defaultLocale] here. `ReloadableResourceBundleMessageSource`
  /// uses the system locale when there is no default locale, as Spring's
  /// `AbstractResourceBasedMessageSource.getDefaultLocale()`.
  String get fallbackLocale => defaultLocale;

  /// The unformatted message for [code] in exactly [locale] (`''` for the
  /// base), or `null`. This is the one method a subclass must write; the
  /// fallbacks to other locales happen around it. [locale] is already
  /// normalized (see `Locales.normalize`).
  String? resolveCode(String code, String locale);

  /// The unformatted message for [code] in the first of [locales] (most
  /// specific first, ending with `''`) that has one, or `null`.
  ///
  /// Calls [resolveCode] locale by locale; sources with several bundles
  /// override it to search bundle by bundle (see
  /// `ReloadableResourceBundleMessageSource`).
  String? resolveCodeInLocales(String code, List<String> locales) {
    for (final locale in locales) {
      final pattern = resolveCode(code, locale);
      if (pattern != null) {
        return pattern;
      }
    }
    return null;
  }

  @override
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  }) {
    final message = getMessageInternal(code, args, locale);
    if (message != null) {
      return message;
    }
    if (defaultMessage != null) {
      return renderDefaultMessage(defaultMessage, args, locale);
    }
    if (useCodeAsDefaultMessage) {
      return code;
    }
    throw NoSuchMessageException(code, locale);
  }

  @override
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  }) {
    for (final code in resolvable.codes) {
      final message = getMessageInternal(code, resolvable.arguments, locale);
      if (message != null) {
        return message;
      }
    }
    final defaultMessage = resolvable.defaultMessage;
    if (defaultMessage != null) {
      // Like Spring's getDefaultMessage: violation messages without `{0}`
      // placeholders and a code used as default message are not formatted.
      final plain = switch (resolvable) {
        DefaultMessageRendering(shouldRenderDefaultMessage: false) => true,
        _ =>
          resolvable.codes.isNotEmpty &&
              defaultMessage == resolvable.codes.first,
      };
      if (plain) {
        return defaultMessage;
      }
      return renderDefaultMessage(defaultMessage, resolvable.arguments, locale);
    }
    if (useCodeAsDefaultMessage && resolvable.codes.isNotEmpty) {
      return resolvable.codes.first;
    }
    throw NoSuchMessageException(
      resolvable.codes.isEmpty ? '' : resolvable.codes.last,
      locale,
    );
  }

  /// The formatted message for [code] from this source, its common
  /// messages or its parent; `null` when none has it. Unlike
  /// [getMessage], it neither throws nor uses a default message.
  String? getMessageInternal(String code, List<Object?> args, String? locale) {
    // Arguments are resolved once with this source (also for the parent,
    // like Spring); the locale chain, common messages and finally the
    // parent are tried in that order.
    final resolvedArgs = resolveArguments(args, locale);
    final pattern = resolveCodeInLocales(code, localeChain(locale));
    if (pattern != null) {
      return formatMessage(pattern, resolvedArgs, locale);
    }
    final common = commonMessages?[code];
    if (common != null) {
      return formatMessage(common, resolvedArgs, locale);
    }
    final parent = parentMessageSource;
    // An abstract parent is asked without exceptions or default handling,
    // so its own useCodeAsDefaultMessage does not short-circuit the lookup.
    if (parent is AbstractMessageSource) {
      return parent.getMessageInternal(code, resolvedArgs, locale);
    }
    if (parent != null) {
      try {
        return parent.getMessage(code, args: resolvedArgs, locale: locale);
      } on NoSuchMessageException {
        return null;
      }
    }
    return null;
  }

  /// The locales tried for [locale]: its candidates, then those of
  /// [fallbackLocale], ending with `''` (the base).
  List<String> localeChain(String? locale) {
    final chain = <String>[...Locales.candidates(locale ?? '')];
    for (final candidate in Locales.candidates(fallbackLocale)) {
      if (!chain.contains(candidate)) {
        chain.add(candidate);
      }
    }
    return chain..add('');
  }

  /// Replaces each [MessageSourceResolvable] in [args] by its message in
  /// [locale]; other arguments stay as they are.
  List<Object?> resolveArguments(List<Object?> args, String? locale) => [
    for (final arg in args)
      if (arg is MessageSourceResolvable)
        getMessageFromResolvable(arg, locale: locale)
      else
        arg,
  ];

  /// Fills [args] into [pattern] with [MessageFormat]; without arguments
  /// (and with [alwaysUseMessageFormat] off) returns [pattern] as it is,
  /// like Spring.
  ///
  /// A pattern that is not a valid `MessageFormat` (for example a message
  /// containing a regular expression such as `[A-Z]{2,3}`) is returned
  /// unchanged unless [alwaysUseMessageFormat] is on — Spring's behaviour.
  ///
  /// Numbers use the symbols of [locale] (else of [defaultLocale]).
  String formatMessage(String pattern, List<Object?> args, [String? locale]) {
    if (args.isEmpty && !alwaysUseMessageFormat) {
      return pattern;
    }
    try {
      return MessageFormat.format(
        pattern,
        args,
        locale: locale ?? defaultLocale,
      );
    } on FormatException {
      if (alwaysUseMessageFormat) {
        rethrow;
      }
      return pattern;
    }
  }

  /// Formats a default message with [args], resolving resolvable
  /// arguments first.
  String renderDefaultMessage(
    String defaultMessage,
    List<Object?> args,
    String? locale,
  ) => formatMessage(defaultMessage, resolveArguments(args, locale), locale);
}

/// A message source whose messages are added in code rather than read
/// from files.
///
/// Use it in tests, or in a small program with a handful of texts. Declare
/// it as the `messageSource` bean, or pass it where a [MessageSource] is
/// expected.
///
/// ```dart
/// // A base text and a Russian one; ru_RU falls back to ru.
/// final messages = StaticMessageSource()
///   ..addMessage('greeting', '', 'Hello {0}')
///   ..addMessages({'greeting': 'Привет {0}'}, 'ru');
/// messages.getMessage('greeting', args: ['Ada'], locale: 'ru_RU');
/// // Привет Ada
/// ```
///
/// Spring (Java):
/// ```java
/// var messages = new StaticMessageSource();
/// messages.addMessage("greeting", Locale.ROOT, "Hello {0}");
/// messages.addMessage("greeting", Locale.of("ru"), "Привет {0}");
/// ```
class StaticMessageSource extends AbstractMessageSource {
  final _messages = <String, String>{};

  /// Adds [message] for [code] in [locale] (`''` for the base, used when
  /// no locale matches); a second call for the same code and locale
  /// replaces it.
  void addMessage(String code, String locale, String message) =>
      _messages[_key(code, locale)] = message;

  /// Adds every entry of [messages] (code to message) for [locale].
  void addMessages(Map<String, String> messages, String locale) {
    for (final MapEntry(:key, :value) in messages.entries) {
      addMessage(key, locale, value);
    }
  }

  @override
  String? resolveCode(String code, String locale) =>
      _messages[_key(code, locale)];

  // NUL cannot appear in codes, so `code + NUL + locale` is unambiguous.
  static String _key(String code, String locale) =>
      '$code\u0000${Locales.normalize(locale)}';

  @override
  String toString() => 'StaticMessageSource: $_messages';
}

/// A message source with no messages of its own: it asks its parent, or
/// fails when there is none.
///
/// The context registers one as `messageSource` when the application
/// declares no such bean, so that a child context uses its parent's
/// messages and a context without messages still answers (with a default
/// message or a [NoSuchMessageException]). Applications do not create it.
///
/// ```dart
/// final source = DelegatingMessageSource(parentContext);
/// source.getMessage('app.title'); // resolved by the parent
/// ```
///
/// Spring (Java):
/// ```java
/// var source = new DelegatingMessageSource();
/// source.setParentMessageSource(parentContext);
/// ```
class DelegatingMessageSource extends AbstractMessageSource {
  /// Creates a source that forwards every lookup to [parent], if any.
  DelegatingMessageSource([MessageSource? parent]) {
    parentMessageSource = parent;
  }

  @override
  String? resolveCode(String code, String locale) => null;
}
