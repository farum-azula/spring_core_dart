import 'package:spring_core_dart/src/context/message/abstract_message_source.dart';
import 'package:spring_core_dart/src/context/message/message_source.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Messages from `.properties` bundles, like Spring's
/// `ReloadableResourceBundleMessageSource`.
///
/// For basename `i18n/messages` and locale `ru_RU` the files
/// `i18n/messages_ru_RU.properties`, `i18n/messages_ru.properties` and
/// `i18n/messages.properties` are consulted. Basenames are locations for
/// the [resourceLoader] (`file:`, `classpath:`, plain paths, custom
/// protocols). Lookup goes basename by basename, like Spring: every locale
/// file of the first basename (requested locale, [fallbackLocale], base
/// file) before the second basename, so `messages.properties` wins over
/// `errors_de`. Resources that cannot be read synchronously (such as
/// Flutter assets) must be loaded with [preload] first.
///
/// ```dart
/// @Configuration()
/// class I18nConfig {
///   @Bean()
///   MessageSource messageSource() => ReloadableResourceBundleMessageSource(
///     basenames: ['file:i18n/messages', 'file:i18n/errors'],
///     cacheSeconds: 10,
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
///   source.setCacheSeconds(10);
///   source.setDefaultLocale(Locale.ENGLISH);
///   return source;
/// }
/// ```
///
/// Files are parsed as UTF-8 `.properties`. Reloading ([cacheSeconds])
/// re-reads files that can be read synchronously; a file's last
/// modification time is compared for file system resources, other
/// resources are re-read on every check, and preloaded (async-only)
/// resources are only replaced by another [preload].
class ReloadableResourceBundleMessageSource extends AbstractMessageSource {
  /// Creates a source for [basenames]; [resourceLoader] defaults to a
  /// `DefaultResourceLoader`.
  ReloadableResourceBundleMessageSource({
    List<String> basenames = const [],
    ResourceLoader? resourceLoader,
    int cacheSeconds = -1,
    this.fallbackToSystemLocale = true,
  }) : _basenames = [...basenames],
       cacheMillis = cacheSeconds < 0 ? -1 : cacheSeconds * 1000,
       resourceLoader = resourceLoader ?? DefaultResourceLoader();

  final List<String> _basenames;

  /// Loads the bundle files.
  final ResourceLoader resourceLoader;

  /// How long loaded files are cached, like Spring's `setCacheSeconds`:
  /// `-1` (the default) caches forever; `0` checks the files on every
  /// lookup; a positive value checks them at most every [cacheSeconds]
  /// seconds. A checked file is re-read when it changed (see the class
  /// documentation). Stored as [cacheMillis].
  int get cacheSeconds => cacheMillis < 0 ? -1 : cacheMillis ~/ 1000;

  set cacheSeconds(int seconds) =>
      cacheMillis = seconds < 0 ? -1 : seconds * 1000;

  /// [cacheSeconds] in milliseconds, like Spring's `setCacheMillis`
  /// (Spring Boot's `spring.messages.cache-duration=500ms` sets it).
  int cacheMillis;

  /// Whether a lookup falls back to the system locale
  /// ([Locales.systemLocale]) when the requested locale misses and no
  /// [defaultLocale] is set; `true` by default. Like Spring's
  /// `setFallbackToSystemLocale`: a [defaultLocale] is used either way.
  bool fallbackToSystemLocale;

  // Loaded files by path; also holds preloaded async-only resources.
  final _cache = <String, _Bundle>{};

  /// Bundle basenames in lookup order (earlier wins).
  List<String> get basenames => List.unmodifiable(_basenames);

  /// Appends [basenames] (consulted after the existing ones).
  void addBasenames(List<String> basenames) => _basenames.addAll(basenames);

  @override
  String get fallbackLocale => defaultLocale.isNotEmpty
      ? defaultLocale
      : fallbackToSystemLocale
      ? Locales.systemLocale
      : '';

  /// Reads all bundle files for [locales] (plus their fallbacks and the
  /// base file) asynchronously into the cache.
  ///
  /// ```dart
  /// final source = ReloadableResourceBundleMessageSource(
  ///   basenames: ['asset:assets/i18n/messages'],
  ///   resourceLoader: assetLoader,
  /// );
  /// await source.preload(['en', 'de']);
  /// ```
  Future<void> preload(List<String> locales) async {
    final candidates = {
      for (final locale in [...locales, fallbackLocale]) ...localeChain(locale),
    };
    for (final basename in _basenames) {
      for (final locale in candidates) {
        final path = _path(basename, locale);
        final resource = resourceLoader.getResource(path);
        _cache[path] = _Bundle(
          resource.exists()
              ? PropertiesParser.parse(await resource.readAsString())
              : const {},
          _lastModified(resource),
        );
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

  static DateTime? _lastModified(Resource resource) {
    if (resource is! FileSystemResource) {
      return null;
    }
    try {
      return resource.exists() ? resource.lastModified() : null;
    } on Object {
      return null;
    }
  }

  // Spring's getProperties / refreshProperties.
  Map<String, String> _properties(String path) {
    final Resource resource = resourceLoader.getResource(path);
    final cached = _cache[path];
    if (cached != null) {
      // Async-only content always comes from the preload cache.
      if (cacheMillis < 0 || !resource.supportsSyncRead) {
        return cached.properties;
      }
      final now = DateTime.now();
      if (now.difference(cached.checked) <
          Duration(milliseconds: cacheMillis)) {
        return cached.properties;
      }
      final modified = _lastModified(resource);
      if (modified != null && modified == cached.modified) {
        cached.checked = now;
        return cached.properties;
      }
    }
    final Map<String, String> properties;
    if (!resource.exists()) {
      properties = const {};
    } else if (resource.supportsSyncRead) {
      properties = PropertiesParser.parse(resource.readAsStringSync());
    } else {
      throw StateError(
        '${resource.description} can only be read asynchronously; call '
        'ReloadableResourceBundleMessageSource.preload() first',
      );
    }
    _cache[path] = _Bundle(properties, _lastModified(resource));
    return properties;
  }

  @override
  String toString() =>
      'ReloadableResourceBundleMessageSource: basenames=$_basenames';
}

/// A loaded bundle file: its properties, the file's modification time
/// (when known) and when it was last loaded or checked.
final class _Bundle {
  _Bundle(this.properties, this.modified) : checked = DateTime.now();

  final Map<String, String> properties;
  final DateTime? modified;
  DateTime checked;
}
