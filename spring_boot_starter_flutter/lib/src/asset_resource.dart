import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A Flutter asset as a `Resource`: what `asset:` locations resolve to, so
/// assets are injected like Spring's `classpath:` resources.
///
/// ```yaml
/// # pubspec.yaml
/// flutter:
///   assets:
///     - assets/intro.mp4
///     - assets/terms.md
/// ```
///
/// ```dart
/// @Component()
/// class Onboarding {
///   Onboarding(
///     @Value('asset:assets/intro.mp4') this.video,
///     @Value('asset:assets/terms.md') this.terms,
///   );
///   final Resource video;
///   final Resource terms;
///
///   Future<String> termsText() => terms.readAsString();
///   String get videoKey => (video as AssetResource).key; // for VideoPlayerController.asset
/// }
/// ```
///
/// Unlike the files of `lib/resources/`, which the generator embeds into
/// the code (small config files and texts, up to 1 MB each, readable
/// synchronously), assets stay in the app's asset bundle and are loaded
/// when read: images, video, sound, large data. Reading is asynchronous
/// only ([readAsBytes], [readAsString]). [key] is the asset key Flutter's
/// own APIs take (`Image.asset`, `AssetImage`, video and audio players).
///
/// Spring (Java): a `ClassPathResource` from `@Value("classpath:...")`.
final class AssetResource extends AbstractResource {
  /// The asset [key] (`assets/intro.mp4`; a leading `/` is dropped) of
  /// [bundle] (`rootBundle` by default); [manifest], when known, decides
  /// [exists].
  AssetResource(String key, {AssetBundle? bundle, this.manifest})
    : key = key.startsWith('/') ? key.substring(1) : key,
      bundle = bundle ?? rootBundle;

  /// The asset key, as declared under `flutter: assets:` in `pubspec.yaml`
  /// (`packages/<package>/...` for a package's assets).
  final String key;

  /// The bundle the asset is read from.
  final AssetBundle bundle;

  /// The app's asset manifest, when known: makes [exists] exact.
  final AssetManifest? manifest;

  /// Whether the asset is in the app's asset manifest. Exact under
  /// `SpringApplicationWidget`, which loads the manifest before the start;
  /// without a manifest, `true` (reading a missing asset then fails).
  @override
  bool exists() => manifest?.listAssets().contains(key) ?? true;

  @override
  String? get filename => key.split('/').last;

  @override
  String get description => 'asset [$key]';

  @override
  Uri? get uri => Uri(scheme: 'asset', path: key);

  @override
  Future<Uint8List> readAsBytes() async {
    final data = await bundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  @override
  Resource createRelative(String relativePath) {
    final slash = key.lastIndexOf('/');
    final directory = slash < 0 ? '' : key.substring(0, slash + 1);
    return AssetResource(
      '$directory$relativePath',
      bundle: bundle,
      manifest: manifest,
    );
  }
}

/// Resolves `asset:<key>` (also `asset:/<key>`) to an [AssetResource], so
/// `@Value('asset:assets/logo.png') Resource logo` and
/// `context.getResource('asset:...')` reach the app's assets. The starter
/// registers it on every application context.
final class AssetProtocolResolver implements ProtocolResolver {
  /// Resolves assets of [bundle] (`rootBundle` by default).
  AssetProtocolResolver({AssetBundle? bundle, this.manifest})
    : bundle = bundle ?? rootBundle;

  /// The location prefix.
  static const prefix = 'asset:';

  /// The bundle assets are read from.
  final AssetBundle bundle;

  /// The asset manifest, when loaded: makes `exists()` exact.
  final AssetManifest? manifest;

  /// The manifest of `rootBundle`, loaded by `SpringApplicationWidget`
  /// before the application starts (see [loadRootManifest]).
  static AssetManifest? rootManifest;

  /// Loads [rootManifest] (no-op when the app has no asset manifest).
  static Future<void> loadRootManifest() async {
    try {
      rootManifest ??= await AssetManifest.loadFromAssetBundle(rootBundle);
    } on Object {
      // No manifest (e.g. a test without assets): exists() stays optimistic.
    }
  }

  @override
  Resource? resolve(String location, ResourceLoader resourceLoader) =>
      location.startsWith(prefix)
      ? AssetResource(
          location.substring(prefix.length),
          bundle: bundle,
          manifest: manifest,
        )
      : null;
}

/// Adds an [AssetProtocolResolver] to the application context before any
/// bean is created (an `AssetBundle` bean, when there is one, replaces
/// `rootBundle`, e.g. in tests).
final class AssetProtocolResolverRegistrar
    implements BeanFactoryPostProcessor, ApplicationContextAware {
  /// Creates the registrar.
  AssetProtocolResolverRegistrar();

  ApplicationContext? _context;

  @override
  void setApplicationContext(ApplicationContext applicationContext) =>
      _context = applicationContext;

  @override
  void postProcessBeanFactory(ConfigurableListableBeanFactory beanFactory) {
    final context = _context;
    if (context is! ConfigurableApplicationContext) {
      return;
    }
    final bundle = beanFactory.findBean<AssetBundle>();
    context.addProtocolResolver(
      AssetProtocolResolver(
        bundle: bundle,
        manifest: bundle == null ? AssetProtocolResolver.rootManifest : null,
      ),
    );
  }
}
