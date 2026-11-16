import 'package:spring_core_dart/core.dart'
    show ChronoUnit, ConversionException, DurationStyle, PropertyResolver;

/// The app's `web/_headers` (the headers file of Cloudflare Pages; its
/// `! Cache-Control` lines are Cloudflare's) from Spring Boot's
/// `spring.web.resources.cache.cachecontrol.*`: how long browsers keep the
/// files of a Flutter web build.
///
/// A Flutter web build names its files without a hash (`index.html`,
/// `main.dart.js`, `main.dart.wasm`, `flutter_bootstrap.js`, the asset
/// manifests): a browser that kept them would run an old build, so they
/// are asked again (`no-cache`). The app's own images and fonts under
/// `/assets/` change seldom and may be kept: they get the `Cache-Control`
/// the keys build, as Spring's `CacheControl` builds it for a server's
/// static resources. The assets without a hash that change with every
/// build ([changingAssets]) are asked again. Written by hand, a file
/// either asked for everything again (every open downloaded all the
/// images) or kept an old build.
///
/// The rules go between [start] and [end]; the rest of the file is the
/// app's own and kept as it is. The host applies every rule whose path
/// matches, in order, and `! Cache-Control` takes off what an earlier rule
/// set: the block's rules have the last word over the app's rules before
/// it, and an app's rule after it has the last word over them.
///
/// Spring has no counterpart: a Spring Boot server sends the header itself.
abstract final class WebCacheHeaders {
  /// The keys the header is made from, as Spring Boot names them.
  static const prefix = 'spring.web.resources.cache.cachecontrol';

  /// The headers file, below the app's directory.
  static const path = 'web/_headers';

  /// Where the block starts.
  static const start = '# spring:cache:start';

  /// Where it ends.
  static const end = '# spring:cache:end';

  /// The block's first line after [start], so a reader knows where its
  /// rules come from.
  static const comment =
      '# Generated from $prefix.* on every build: change the configuration, '
      'not these lines.';

  /// The assets of a Flutter web build that have no hash in their names
  /// and change with every build, asked again as the page is: the asset
  /// manifests, the fonts' manifest, the licences, flutter_scene's shader
  /// manifests, the engine's shaders, the icon fonts Flutter cuts to the
  /// icons the app uses and the app's resources read at run time.
  static const changingAssets = [
    '/assets/AssetManifest*',
    '/assets/FontManifest.json',
    '/assets/NOTICES',
    '/assets/*/manifest.json',
    '/assets/shaders/*',
    // Flutter cuts the icon fonts to the icons the app uses, under the same
    // name every build: a new icon would show as a box from a kept one.
    '/assets/fonts/MaterialIcons-Regular.otf',
    '/assets/packages/cupertino_icons/*',
    // The app's resources not embedded in its code (`lib/resources/`, read
    // through `resources:`): Markdown pages, messages, the generated search
    // index. No hash, and they change with the content: a kept one would
    // show last week's page after a deploy.
    '/assets/lib/resources/*',
  ];

  /// The `Cache-Control` value of the app's assets that the keys of
  /// [properties] build, as Spring Boot's `Cachecontrol.toHttpCacheControl`
  /// does: `no-store`, else `no-cache`, else `max-age`, then the other
  /// directives, in the order of Spring's `CacheControl`
  /// (`max-age=2592000, public`). A duration without a unit is seconds, as
  /// Spring Boot reads these keys. `null` when none of them makes a
  /// directive. A value that cannot be read goes to [problem] and counts
  /// as not set.
  static String? cacheControl(
    PropertyResolver properties, {
    required void Function(String message) problem,
  }) {
    bool flag(String key) {
      final name = '$prefix.$key';
      try {
        return properties.getPropertyAs<bool>(name) ?? false;
      } on ConversionException {
        problem('$name is true or false, not ${properties.getProperty(name)}.');
        return false;
      }
    }

    Duration? duration(String key) {
      final name = '$prefix.$key';
      final text = properties.getProperty(name)?.trim();
      if (text == null || text.isEmpty) {
        return null;
      }
      try {
        return DurationStyle.parse(text, unit: ChronoUnit.seconds);
      } on FormatException {
        problem('$name is a duration (30d, 3600, PT1H), not $text.');
        return null;
      }
    }

    // Each read once, so each problem is told once.
    final noStore = flag('no-store');
    final noCache = flag('no-cache');
    final maxAge = duration('max-age');
    final mustRevalidate = flag('must-revalidate');
    final noTransform = flag('no-transform');
    final cachePublic = flag('cache-public');
    final cachePrivate = flag('cache-private');
    final proxyRevalidate = flag('proxy-revalidate');
    final sMaxAge = duration('s-max-age');
    final staleIfError = duration('stale-if-error');
    final staleWhileRevalidate = duration('stale-while-revalidate');
    final directives = [
      // One of the three starts the header, no-store first.
      if (noStore)
        'no-store'
      else if (noCache)
        'no-cache'
      else if (maxAge != null)
        'max-age=${maxAge.inSeconds}',
      if (mustRevalidate) 'must-revalidate',
      if (noTransform) 'no-transform',
      if (cachePublic) 'public',
      if (cachePrivate) 'private',
      if (proxyRevalidate) 'proxy-revalidate',
      if (sMaxAge != null) 's-maxage=${sMaxAge.inSeconds}',
      if (staleIfError != null) 'stale-if-error=${staleIfError.inSeconds}',
      if (staleWhileRevalidate != null)
        'stale-while-revalidate=${staleWhileRevalidate.inSeconds}',
    ];
    return directives.isEmpty ? null : directives.join(', ');
  }

  /// The block for the assets' [cacheControl]: everything `no-cache`, the
  /// assets [cacheControl], the [changingAssets] `no-cache` again.
  static String block(String cacheControl) {
    String rule(String path, String value) =>
        '$path\n  ! Cache-Control\n  Cache-Control: $value\n';
    return [
      '$start\n',
      '$comment\n',
      rule('/*', 'no-cache'),
      rule('/assets/*', cacheControl),
      for (final asset in changingAssets) rule(asset, 'no-cache'),
      end,
    ].join();
  }

  static final _block = RegExp(
    '^${RegExp.escape(start)}\\r?\$[\\s\\S]*?^${RegExp.escape(end)}\\r?\$',
    multiLine: true,
  );

  // The block with the empty line before it and its line break.
  static final _blockLines = RegExp(
    '(?:^\\r?\\n)?${_block.pattern}\\n?',
    multiLine: true,
  );

  /// [headers] (the file's text, `null` when there is none) with the block
  /// of [cacheControl] where it is, or after the app's rules when it has
  /// none; without the block when [cacheControl] is `null`. The rest of the
  /// file is kept as it is. An empty text when the block was all the file
  /// had, so the file need not be there.
  static String apply(String? headers, String? cacheControl) {
    final text = headers ?? '';
    if (cacheControl == null) {
      if (!_block.hasMatch(text)) {
        return text;
      }
      final rest = _without(text);
      return rest.trim().isEmpty ? '' : rest;
    }
    final written = block(cacheControl);
    final match = _block.firstMatch(text);
    if (match != null) {
      return text.substring(0, match.start) +
          written +
          _without(text.substring(match.end));
    }
    if (text.trim().isEmpty) {
      return '$written\n';
    }
    final gap = text.endsWith('\n\n')
        ? ''
        : text.endsWith('\n')
        ? '\n'
        : '\n\n';
    return '$text$gap$written\n';
  }

  // [text] without its blocks; a block at the top takes the empty line
  // after it, any other the one before it.
  static String _without(String text) {
    var result = text;
    for (
      var match = _blockLines.firstMatch(result);
      match != null;
      match = _blockLines.firstMatch(result)
    ) {
      var after = match.end;
      if (match.start == 0 && result.startsWith('\n', after)) {
        after++;
      }
      result = result.substring(0, match.start) + result.substring(after);
    }
    return result;
  }
}
