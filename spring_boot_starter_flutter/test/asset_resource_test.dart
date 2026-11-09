import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// Assets in memory.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(utf8.encode(text));
  }
}

class _Manifest implements AssetManifest {
  _Manifest(this.assets);

  final List<String> assets;

  @override
  List<String> listAssets() => assets;

  @override
  List<AssetMetadata>? getAssetVariants(String key) => null;
}

class Terms {
  Terms(this.text);
  final Resource text;
}

void main() {
  test(
    '@Value(asset:...) injects an AssetResource of the AssetBundle bean',
    () async {
      final context = await SpringApplication(
        [
          BeanModule('test', [
            BeanDefinition<AssetBundle>(
              name: 'assetBundle',
              types: const [AssetBundle],
              create: (_) => _Bundle({'assets/terms.md': '# Terms'}),
            ),
            BeanDefinition<Terms>(
              name: 'terms',
              types: const [Terms],
              create: (r) => Terms(r.value<Resource>('asset:assets/terms.md')),
            ),
          ]),
        ],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);

      final resource = context.getBean<Terms>().text;
      expect(resource, isA<AssetResource>());
      expect((resource as AssetResource).key, 'assets/terms.md');
      expect(await resource.readAsString(), '# Terms');
      expect(
        context.getResource('asset:/assets/terms.md').description,
        'asset [assets/terms.md]',
      );
    },
  );

  group('AssetResource', () {
    test('key, filename, uri, description', () {
      final resource = AssetResource('/assets/video/intro.mp4');
      expect(resource.key, 'assets/video/intro.mp4');
      expect(resource.filename, 'intro.mp4');
      expect(resource.uri, Uri.parse('asset:assets/video/intro.mp4'));
      expect(resource.description, 'asset [assets/video/intro.mp4]');
      expect(resource.supportsSyncRead, isFalse);
      expect(resource.readAsBytesSync, throwsUnsupportedError);
    });

    test('exists() follows the manifest; optimistic without one', () {
      final manifest = _Manifest(['assets/logo.png']);
      expect(
        AssetResource('assets/logo.png', manifest: manifest).exists(),
        isTrue,
      );
      expect(
        AssetResource('assets/nope.png', manifest: manifest).exists(),
        isFalse,
      );
      expect(AssetResource('assets/nope.png').exists(), isTrue);
    });

    test('createRelative stays in the directory and the bundle', () async {
      final bundle = _Bundle({'assets/i18n/de.json': '{}'});
      final relative = AssetResource(
        'assets/i18n/en.json',
        bundle: bundle,
      ).createRelative('de.json');
      expect((relative as AssetResource).key, 'assets/i18n/de.json');
      expect(await relative.readAsString(), '{}');
    });

    test('reading a missing asset fails', () {
      expect(
        AssetResource('assets/missing.txt', bundle: _Bundle({})).readAsBytes(),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  test('other locations are not resolved', () {
    final resolver = AssetProtocolResolver(bundle: _Bundle({}));
    expect(
      resolver.resolve('resources:a.txt', DefaultResourceLoader()),
      isNull,
    );
  });

  test('a root of assets: resources: and asset: patterns find them', () async {
    final bundle = _Bundle({
      'lib/resources/content/docs/a.md': '# A',
      'lib/resources/content/docs/deep/b.md': '# B',
      'assets/notes/c.md': '# C',
    });
    final manifest = _Manifest(bundle.files.keys.toList());
    final removeResources = Resources.addRoot(
      AssetResourceRoot(manifest, prefix: 'lib/resources/', bundle: bundle),
    );
    final removeAssets = Resources.addProtocolRoot(
      'asset:',
      AssetResourceRoot(manifest, bundle: bundle),
    );
    addTearDown(() {
      removeResources();
      removeAssets();
    });
    final loader = DefaultResourceLoader();
    final a = loader.getResource('resources:content/docs/a.md');
    expect(a, isA<AssetResource>());
    expect((a as AssetResource).pathWithinContext, 'content/docs/a.md');
    expect(await a.readAsString(), '# A');
    expect(
      loader.getResource('resources:content/docs/none.md').exists(),
      isFalse,
    );
    final patterns = PathMatchingResourcePatternResolver(
      resourceLoader: loader,
    );
    expect(
      [
        for (final r in patterns.getResources('resources:content/**/*.md'))
          (r as ContextResource).pathWithinContext,
      ],
      ['content/docs/a.md', 'content/docs/deep/b.md'],
    );
    expect(
      [
        for (final r in patterns.getResources('asset:assets/**/*.md'))
          (r as AssetResource).key,
      ],
      ['assets/notes/c.md'],
    );
  });
}
