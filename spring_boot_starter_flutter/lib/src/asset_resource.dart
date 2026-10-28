import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A Flutter asset (an image, a video, a data file of the app bundle)
/// seen as a `Resource`.
///
/// It lets beans receive assets the way they receive any other file:
/// `@Value('asset:assets/terms.md') Resource terms` injects an
/// `AssetResource`, and `context.getResource('asset:...')` returns one.
/// So a bean that reads a file does not care whether it comes from the
/// asset bundle or from `lib/resources/`. You rarely create one yourself.
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
/// // The onboarding screen shows the terms and plays the intro video.
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
///
///   // Flutter's players take the asset key.
///   String get videoKey => (video as AssetResource).key;
/// }
/// ```
///
/// Unlike the files of `lib/resources/`, which the generator embeds into
/// the code (small config files and texts, up to 1 MB each, readable
/// synchronously), assets stay in the app's asset bundle and are loaded
/// when read: images, video, sound, large data. Reading is asynchronous
/// only ([readAsBytes], [readAsString]). [key] is the asset key Flutter's
/// own APIs take (`Image.asset`, `AssetImage`, video and audio players).
/// The generator checks every `@Value('asset:...')` against
/// `flutter: assets:` in `pubspec.yaml` and fails the build when the asset
/// is not declared.
///
/// Spring (Java): a `ClassPathResource` from `@Value("classpath:...")`.
final class AssetResource extends AbstractResource {
  /// The asset [key] (`assets/intro.mp4`; a leading `/` is dropped) of
  /// [bundle] (`rootBundle` by default). [manifest], when given, makes
  /// [exists] exact.
  AssetResource(String key, {AssetBundle? bundle, this.manifest})
    : key = key.startsWith('/') ? key.substring(1) : key,
      bundle = bundle ?? rootBundle;

  /// The asset key, as declared under `flutter: assets:` in `pubspec.yaml`
  /// (`packages/<package>/...` for a package's assets).
  final String key;

  /// The bundle the asset is read from: `rootBundle`, or another one in
  /// tests.
  final AssetBundle bundle;

  /// The app's list of assets, when known; [exists] looks the key up in
  /// it.
  final AssetManifest? manifest;

  /// Whether the asset is in the app's asset manifest. It is exact under
  /// `SpringApplicationWidget`, which loads the manifest before the start.
  /// Without a manifest it returns `true`, and reading a missing asset then
  /// fails.
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

/// Turns `asset:<key>` locations (also `asset:/<key>`) into
/// [AssetResource]s, so `@Value('asset:assets/logo.png') Resource logo`
/// and `context.getResource('asset:...')` reach the app's assets.
///
/// The starter registers one on every application context; applications
/// do not create it.
final class AssetProtocolResolver implements ProtocolResolver {
  /// A resolver for the assets of [bundle] (`rootBundle` by default), with
  /// [manifest] to make `exists()` exact.
  AssetProtocolResolver({AssetBundle? bundle, this.manifest})
    : bundle = bundle ?? rootBundle;

  /// The prefix of the locations this resolver handles, `asset:`.
  static const prefix = 'asset:';

  /// The bundle the assets are read from.
  final AssetBundle bundle;

  /// The asset manifest given to the resources, when known; it makes
  /// `exists()` exact.
  final AssetManifest? manifest;

  /// The manifest of `rootBundle`, once [loadRootManifest] loaded it;
  /// `SpringApplicationWidget` does so before the application starts.
  static AssetManifest? rootManifest;

  /// Loads [rootManifest] once. Does nothing when it is already loaded,
  /// and leaves it `null` when the app has no asset manifest (a test
  /// without assets).
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
/// bean is created, so beans can already receive `asset:` resources.
///
/// An `AssetBundle` bean, when there is one (in tests, for example),
/// replaces `rootBundle`. The starter registers it; applications do not
/// use it.
final class AssetProtocolResolverRegistrar
    implements BeanFactoryPostProcessor, ApplicationContextAware {
  /// The registrar; it has no settings.
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
