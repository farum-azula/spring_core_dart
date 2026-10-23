import 'package:spring_core_dart/src/context/message/message_format.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';

/// Shared logic of message sources, like Spring's `AbstractMessageSource`.
///
/// Lookup for code `c` and locale `ru_RU`: `ru_RU` → `ru` → [defaultLocale]
/// chain → base (no locale) → [commonMessages] → parent. Locales with a
/// script follow Java's `ResourceBundle`: `zh_Hant_TW` → `zh_Hant` →
/// `zh_TW` → `zh`. Arguments that are [MessageSourceResolvable]s are
/// resolved by this source before the parent is asked (so a message of
/// the parent can use arguments only the child knows), and messages are
/// formatted with the number symbols of the requested locale.
///
/// Subclasses only implement [resolveCode]; formatting, fallbacks and
/// argument resolution are shared.
///
/// ```dart
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
  /// The fallback source; see [HierarchicalMessageSource].
  @override
  MessageSource? parentMessageSource;

  /// Return the code itself instead of throwing when nothing is found.
  bool useCodeAsDefaultMessage = false;

  /// Apply [MessageFormat] rules (quotes) even without arguments.
  bool alwaysUseMessageFormat = false;

  /// Locale-independent messages used after all locales.
  Map<String, String>? commonMessages;

  /// Locale tried after the requested one (like Spring's default locale);
  /// empty means none.
  String defaultLocale = '';

  /// Whether [defaultLocale] is tried when the requested locale misses.
  bool fallbackToDefaultLocale = true;

  /// The raw message for [code] in exactly [locale] (`''` = base), or
  /// `null`. [locale] is already normalized (see `Locales.normalize`).
  String? resolveCode(String code, String locale);

  /// The raw message for [code] in the first of [locales] (most specific
  /// first, ending with `''`) that has one, or `null`.
  ///
  /// Calls [resolveCode] locale by locale; sources with several bundles
  /// override it to search bundle by bundle (see
  /// `PropertiesMessageSource`).
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

  /// The formatted message, or `null` when no source has [code].
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

  /// Locales tried for [locale], most specific first, ending with `''`.
  List<String> localeChain(String? locale) {
    final chain = <String>[...Locales.candidates(locale ?? '')];
    if (fallbackToDefaultLocale) {
      for (final candidate in Locales.candidates(defaultLocale)) {
        if (!chain.contains(candidate)) {
          chain.add(candidate);
        }
      }
    }
    return chain..add('');
  }

  /// Resolves [MessageSourceResolvable] arguments to strings.
  List<Object?> resolveArguments(List<Object?> args, String? locale) => [
    for (final arg in args)
      arg is MessageSourceResolvable
          ? getMessageFromResolvable(arg, locale: locale)
          : arg,
  ];

  /// Applies [MessageFormat] unless there are no arguments (and
  /// [alwaysUseMessageFormat] is off), like Spring.
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

  /// Formats a default message with [args].
  String renderDefaultMessage(
    String defaultMessage,
    List<Object?> args,
    String? locale,
  ) => formatMessage(defaultMessage, resolveArguments(args, locale), locale);
}

/// Messages registered in code, like Spring's `StaticMessageSource`.
///
/// Handy for tests and small apps.
///
/// ```dart
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

  /// Adds [message] for [code] in [locale] (`''` = base).
  void addMessage(String code, String locale, String message) =>
      _messages[_key(code, locale)] = message;

  /// Adds every entry of [messages] for [locale].
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

/// An empty message source that delegates to its parent, like Spring's
/// `DelegatingMessageSource`; the context's default.
///
/// The context registers one as `messageSource` when no such bean exists,
/// so a child context transparently uses its parent's messages.
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
  /// Creates a source that forwards every lookup to [parent] (if any).
  DelegatingMessageSource([MessageSource? parent]) {
    parentMessageSource = parent;
  }

  @override
  String? resolveCode(String code, String locale) => null;
}
