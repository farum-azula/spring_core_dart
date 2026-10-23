import 'package:spring_core_dart/src/context/message/abstract_message_source.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Messages from `.properties` bundles, like Spring's
/// `ResourceBundleMessageSource` / `ReloadableResourceBundleMessageSource`.
///
/// For basename `i18n/messages` and locale `ru_RU` the files
/// `i18n/messages_ru_RU.properties`, `i18n/messages_ru.properties` and
/// `i18n/messages.properties` are consulted. Basenames are locations for
/// the [resourceLoader] (`file:`, plain paths, custom protocols). Lookup
/// goes basename by basename, like Spring: every locale file of the first
/// basename (requested locale, default locale, base file) before the
/// second basename, so `messages.properties` wins over `errors_de`. Resources that cannot be read synchronously (such as
/// Flutter assets) must be loaded with [preload] first.
///
/// ```dart
/// @Configuration()
/// class I18nConfig {
///   @Bean()
///   MessageSource messageSource() => PropertiesMessageSource(
///     basenames: ['file:i18n/messages', 'file:i18n/errors'],
///   )..defaultLocale = 'en';
/// }
///
/// // i18n/messages_de.properties:  greeting=Hallo {0}
/// context.getMessage('greeting', args: ['Ada'], locale: 'de_AT');
/// ```
///
/// Spring (Java):
/// ```java
/// @Bean
/// MessageSource messageSource() {
///   var source = new ReloadableResourceBundleMessageSource();
///   source.setBasenames("file:i18n/messages", "file:i18n/errors");
///   source.setDefaultLocale(Locale.ENGLISH);
///   return source;
/// }
/// ```
///
/// Files are parsed as UTF-8 `.properties`; there is no time-based
/// reloading (`cacheSeconds`), only [cacheMessages] and [clearCache].
class PropertiesMessageSource extends AbstractMessageSource {
  /// Creates a source for [basenames]; [resourceLoader] defaults to a
  /// `DefaultResourceLoader`.
  PropertiesMessageSource({
    List<String> basenames = const [],
    ResourceLoader? resourceLoader,
    this.cacheMessages = true,
  }) : _basenames = [...basenames],
       resourceLoader = resourceLoader ?? DefaultResourceLoader();

  final List<String> _basenames;

  /// Loads the bundle files.
  final ResourceLoader resourceLoader;

  /// Keep parsed files; turn off to re-read files on every lookup.
  bool cacheMessages;

  // Parsed files by path; also holds preloaded async-only resources.
  final _cache = <String, Map<String, String>>{};

  /// Bundle basenames in lookup order (earlier wins).
  List<String> get basenames => List.unmodifiable(_basenames);

  /// Appends [basenames] (consulted after the existing ones).
  void addBasenames(List<String> basenames) => _basenames.addAll(basenames);

  /// Reads all bundle files for [locales] (plus their fallbacks and the
  /// base file) asynchronously into the cache.
  ///
  /// ```dart
  /// final source = PropertiesMessageSource(
  ///   basenames: ['asset:assets/i18n/messages'],
  ///   resourceLoader: assetLoader,
  /// );
  /// await source.preload(['en', 'de']);
  /// ```
  Future<void> preload(List<String> locales) async {
    final candidates = {
      for (final locale in [...locales, defaultLocale]) ...localeChain(locale),
    };
    for (final basename in _basenames) {
      for (final locale in candidates) {
        final path = _path(basename, locale);
        final resource = resourceLoader.getResource(path);
        _cache[path] = resource.exists()
            ? PropertiesParser.parse(await resource.readAsString())
            : const {};
      }
    }
  }

  /// Forgets all loaded files (including preloaded ones).
  void clearCache() => _cache.clear();

  @override
  String? resolveCode(String code, String locale) =>
      resolveCodeInLocales(code, [locale]);

  // Basename by basename, each with its whole locale chain (Spring's
  // calculateAllFilenames).
  @override
  String? resolveCodeInLocales(String code, List<String> locales) {
    for (final basename in _basenames) {
      for (final locale in locales) {
        final message = _properties(_path(basename, locale))[code];
        if (message != null) {
          return message;
        }
      }
    }
    return null;
  }

  static String _path(String basename, String locale) {
    final normalized = Locales.normalize(locale);
    return '$basename${normalized.isEmpty ? '' : '_$normalized'}.properties';
  }

  Map<String, String> _properties(String path) {
    final Resource resource = resourceLoader.getResource(path);
    final cached = _cache[path];
    // Async-only content always comes from the preload cache.
    if (cached != null && (cacheMessages || !resource.supportsSyncRead)) {
      return cached;
    }
    final Map<String, String> properties;
    if (!resource.exists()) {
      properties = const {};
    } else if (resource.supportsSyncRead) {
      properties = PropertiesParser.parse(resource.readAsStringSync());
    } else {
      throw StateError(
        '${resource.description} can only be read asynchronously; call '
        'PropertiesMessageSource.preload() first',
      );
    }
    if (cacheMessages) {
      _cache[path] = properties;
    }
    return properties;
  }

  @override
  String toString() => 'PropertiesMessageSource: basenames=$_basenames';
}
