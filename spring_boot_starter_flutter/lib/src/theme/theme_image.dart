import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_config.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_reader.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show HttpTransport;

/// Fails with a [ThemePropertyException] for a key below [path] that is not
/// one of [allowed] (kebab case), naming the valid ones and the closest.
/// Internal to the starter.
void checkThemeKeys(
  ThemeProperties p,
  String path,
  Iterable<String> allowed,
  String what,
) {
  final known = {for (final key in allowed) ThemeValues.canonical(key)};
  for (final key in p.children(path)) {
    if (!known.contains(key)) {
      final shown = allowed.toList();
      throw ThemePropertyException(
        p.propertyName('$path.$key'),
        p['$path.$key'] ?? '',
        'a property of $what: ${shown.join(', ')}'
        '${didYouMean(key, shown)}',
      );
    }
  }
}

/// An image the theme names: an asset, or a file from the network that is
/// cached in the app's files.
///
/// It is the source of the theme's `background.image`, of the screens'
/// backgrounds and of the image tokens (a token that is a map with
/// `source`):
///
/// ```yaml
/// image:
///   source: https://cdn.example.com/neon/background.jpg  # or an asset path
///   refresh: 1d                  # optional: look again in the background
///   source-sha256: 9f2c...       # optional: refuse other content
///   headers: { Authorization: Bearer ${cdn.token} }
///   timeout: 10s
///   fallback: packages/neon_ui/assets/images/neon-background.jpg
///   allow-http: false            # true for an http:// source
/// ```
///
/// The [provider] is what to paint: the asset, or for a network source the
/// cache, else the [fallback], else `null` until the download ends. It
/// changes when a download arrives; listen to [listenable] to follow it.
/// The starter's `ThemeImageLoader` does the downloads, never waiting for
/// them at the start.
///
/// ```dart
/// final image = context.theme.background.image!.image;
/// ValueListenableBuilder(
///   valueListenable: image.listenable,
///   builder: (context, provider, _) => provider == null
///       ? const SizedBox()
///       : Image(image: provider),
/// );
/// ```
final class ThemeImage {
  /// An image from [source]: an asset path, an `https://` URL, or an
  /// `http://` one with [allowHttp]. Throws an `ArgumentError` for an empty
  /// source, another scheme, an `http://` source without [allowHttp] or a
  /// [sha256] that is not 64 hexadecimal digits.
  ThemeImage({
    required String source,
    this.refresh,
    String? sha256,
    this.headers = const {},
    this.timeout = defaultTimeout,
    this.fallback,
    this.allowHttp = false,
  }) : source = source.trim(),
       sha256 = sha256?.toLowerCase() {
    final text = this.source;
    if (text.isEmpty) {
      throw ArgumentError.value(source, 'source', 'is empty');
    }
    final pin = this.sha256;
    if (pin != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
      throw ArgumentError.value(
        sha256,
        'source-sha256',
        'must be 64 hexadecimal digits',
      );
    }
    final scheme = Uri.tryParse(text)?.scheme ?? '';
    if (scheme.isEmpty || RegExp(r'^[a-zA-Z]:').hasMatch(text)) {
      uri = null;
    } else if (scheme == 'https' || (scheme == 'http' && allowHttp)) {
      uri = Uri.parse(text);
      if (uri!.host.isEmpty) {
        throw ArgumentError.value(source, 'source', 'has no host');
      }
    } else if (scheme == 'http') {
      throw ArgumentError.value(
        source,
        'source',
        'is plain http, which is refused: use https, or set allow-http: '
            'true (Android and iOS refuse clear text anyway)',
      );
    } else {
      throw ArgumentError.value(
        source,
        'source',
        'must be an asset path, an https:// URL or (with allow-http) an '
            'http:// URL',
      );
    }
    _provider = ValueNotifier(_initial());
  }

  /// The keys of the image, in kebab case.
  static const keys = [
    'source',
    'refresh',
    'source-sha256',
    'headers',
    'timeout',
    'fallback',
    'allow-http',
  ];

  /// How long a download may take unless `timeout` says otherwise.
  static const defaultTimeout = Duration(seconds: 10);

  /// The asset path or URL as written.
  final String source;

  /// The address to download from; `null` for an asset.
  late final Uri? uri;

  /// How old the cache may get before it is read again in the background;
  /// `null`: never, the first download is kept for ever.
  final Duration? refresh;

  /// The digest the file must have (lowercase hexadecimal), if pinned.
  final String? sha256;

  /// The request headers (`Authorization`), with `${...}` placeholders
  /// already resolved by the Environment.
  final Map<String, String> headers;

  /// The longest a download may take.
  final Duration timeout;

  /// The asset shown while the network image is not there.
  final String? fallback;

  /// Whether an `http://` source is allowed.
  final bool allowHttp;

  /// Whether the image comes from the network.
  bool get isNetwork => uri != null;

  /// The folder of this image's cache below `spring/images/`: it belongs
  /// to the source and the pin, so another one downloads again.
  late final String cacheKey = sha256HexOfString('$source\n${sha256 ?? ''}');

  /// The folder of all the caches, relative to the files' `support` place.
  static const cacheRoot = 'spring/images';

  /// The cache folder of this image.
  String get cacheFolder => '$cacheRoot/$cacheKey';

  late final ValueNotifier<ImageProvider?> _provider;

  ImageProvider? _initial() => isNetwork
      ? (fallback == null ? null : AssetImage(fallback!))
      : AssetImage(source);

  /// What to paint now; `null` while a network image has neither a cache
  /// nor a fallback.
  ImageProvider? get provider => _provider.value;

  /// Notifies when [provider] changes: the download arrived or was
  /// refreshed.
  ValueListenable<ImageProvider?> get listenable => _provider;

  /// Reads the image under [path] (`background.image`) of [p]. Throws a
  /// [ThemePropertyException] for a missing source, a refused `http://`
  /// one, a wrong pin, duration or header. [extra] are other keys allowed
  /// under [path], checked by the caller.
  factory ThemeImage.parse(
    ThemeProperties p,
    String path, {
    Iterable<String> extra = const [],
  }) {
    checkThemeKeys(p, path, [...keys, ...extra], 'an image');
    final source = p['$path.source'];
    if (source == null) {
      throw ThemePropertyException(
        p.propertyName('$path.source'),
        '',
        'an asset path or an https:// URL (every image needs a source)',
      );
    }
    Duration? duration(String key) => p.read(
      '$path.$key',
      ThemeValues.duration,
      'a duration like 10s, 1h or 1.5d',
    );
    final headers = <String, String>{};
    for (final name in p.children('$path.headers')) {
      headers[name] = p['$path.headers.$name'] ?? '';
    }
    final allowHttp =
        p.read(
          '$path.allowhttp',
          ThemeValues.boolean,
          'true or false',
        ) ??
        false;
    try {
      return ThemeImage(
        source: source,
        refresh: duration('refresh'),
        sha256: p['$path.sourcesha256'],
        headers: headers,
        timeout: duration('timeout') ?? defaultTimeout,
        fallback: p['$path.fallback'],
        allowHttp: allowHttp,
      );
    } on ArgumentError catch (error) {
      final key = error.name == 'source-sha256' ? 'sourcesha256' : 'source';
      throw ThemePropertyException(
        p.propertyName('$path.$key'),
        '${error.invalidValue}',
        '${error.message}',
      );
    }
  }

  @override
  String toString() => 'ThemeImage($source)';
}

/// Downloads and caches the network images of the themes and keeps their
/// [ThemeImage.provider] current.
///
/// How an image goes, in `ApplicationRunner.run` (the start never waits for
/// the network):
///
/// - a cache of this image (and pin) is the provider at once; with
///   `refresh` and an old cache, the file is read again in the background,
///   with `If-None-Match` / `If-Modified-Since`, and the new one is swapped
///   in as soon as it arrives; without `refresh` there is no request, ever;
/// - without a cache the provider is the `fallback` (or `null`) and the
///   file is downloaded in the background, once;
/// - offline, a timeout, a bad digest or a too big file keep what is shown,
///   with a warning; a cached file that is not the pinned one is dropped.
///
/// The cache is `spring/images/<sha256 of source and pin>/image` and
/// `meta.json` in the files' `support` place (IndexedDB on the web, where
/// a failed download logs a CORS hint). Folders of images no longer
/// configured are removed at start.
///
/// Internal to the starter.
final class ThemeImageLoader implements ApplicationRunner {
  /// Loads the images of [themes], caching through [files]. [transport] is
  /// the HTTP client (the platform's by default, closed by [dispose]);
  /// [maxBytes] limits a download; [clock] is for tests.
  ThemeImageLoader({
    required this.themes,
    required this.files,
    HttpTransport? transport,
    this.maxBytes = defaultMaxBytes,
    DateTime Function()? clock,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _transport = transport,
       _clock = clock ?? DateTime.now;

  /// The size an image may have: 20 MiB.
  static const defaultMaxBytes = 20 * 1024 * 1024;

  static const _log = SpringLog('spring_boot_starter_flutter.ThemeImage');

  /// The themes whose images are loaded.
  final SpringThemes themes;

  /// Where the cache is.
  final FileTemplate files;

  /// The most bytes an image may have.
  final int maxBytes;

  final HttpTransport? _transport;
  final DateTime Function() _clock;
  final _fetchers = <Duration, RemoteFetcher>{};
  final _entries = <String, _Entry>{};
  bool _disposed = false;
  bool _listening = false;

  RemoteFetcher _fetcher(Duration timeout) => _fetchers.putIfAbsent(
    timeout,
    () => RemoteFetcher(
      transport: _transport,
      timeout: timeout,
      maxBytes: maxBytes,
    ),
  );

  /// Completes when no download is running; for tests.
  Future<void> get idle async {
    while (_entries.values.any((e) => e.inFlight != null)) {
      await Future.wait([
        for (final e in _entries.values)
          if (e.inFlight != null) e.inFlight!,
      ]);
    }
  }

  @override
  Future<void> run(ApplicationArguments args) async {
    if (!_listening) {
      _listening = true;
      themes.addListener(_onThemes);
    }
    final fresh = _attachAll();
    await removeStaleCaches();
    // Only the caches are waited for; the downloads go on in the background.
    await Future.wait([for (final entry in fresh) _start(entry)]);
  }

  // New or reloaded themes: their images get the providers, new ones start.
  void _onThemes() {
    for (final entry in _attachAll()) {
      unawaited(_start(entry));
    }
  }

  // Gives every image of every theme the entry's provider; returns the
  // entries that are new.
  List<_Entry> _attachAll() {
    final fresh = <_Entry>[];
    final seen = <String>{};
    for (final entry in _entries.values) {
      entry.attached.clear();
    }
    for (final name in themes.names) {
      for (final image in themes.data(name).images) {
        if (!image.isNetwork) {
          continue;
        }
        seen.add(image.cacheKey);
        var entry = _entries[image.cacheKey];
        if (entry == null) {
          entry = _entries[image.cacheKey] = _Entry(image);
          fresh.add(entry);
        }
        entry.attached.add(image);
        final current = entry.current;
        if (current != null && image.provider != current) {
          image._provider.value = current;
        }
      }
    }
    for (final key in _entries.keys.toList()) {
      if (!seen.contains(key)) {
        _entries.remove(key)?.remove();
      }
    }
    return fresh;
  }

  /// Removes the cache folders of images that are no longer configured.
  Future<void> removeStaleCaches() async {
    try {
      final stale = <String>{};
      for (final path in await files.list('${ThemeImage.cacheRoot}/')) {
        final key = path.split('/').elementAtOrNull(2);
        if (key != null && !_entries.containsKey(key)) {
          stale.add(key);
        }
      }
      for (final key in stale) {
        await files.delete('${ThemeImage.cacheRoot}/$key');
        _log.debug(() => 'removed the cache of an image no longer used');
      }
    } on Object catch (error) {
      _log.debug(() => 'the image caches could not be cleaned: $error');
    }
  }

  Future<void> _start(_Entry entry) async {
    try {
      final cached = await _readCache(entry.image);
      if (cached != null) {
        _show(entry, cached.bytes);
        if (entry.image.refresh != null) {
          _schedule(entry, cached.meta.fetchedAt);
        }
        return;
      }
    } on Object catch (error) {
      _log.warning(() => 'image ${entry.image.source}: $error');
    }
    // The first download: in the background, the start goes on.
    unawaited(_refresh(entry));
  }

  void _show(_Entry entry, Uint8List bytes) {
    if (entry.removed) {
      return;
    }
    final provider = MemoryImage(bytes);
    entry.current = provider;
    for (final image in entry.attached) {
      image._provider.value = provider;
    }
  }

  void _schedule(_Entry entry, DateTime fetchedAt) {
    final refresh = entry.image.refresh;
    // A download that ends after its entry went away must not start a
    // timer again.
    if (refresh == null || _disposed || entry.removed) {
      return;
    }
    final wait = fetchedAt.add(refresh).difference(_clock());
    entry.timer?.cancel();
    if (wait <= Duration.zero) {
      unawaited(_refresh(entry));
    } else {
      entry.timer = Timer(wait, () => unawaited(_refresh(entry)));
    }
  }

  Future<void> _refresh(_Entry entry) => entry.inFlight ??= () async {
    final image = entry.image;
    try {
      await _download(entry);
    } on Object catch (error) {
      _log.warning(
        () =>
            'image ${image.source} could not be loaded ($error); what is '
            'shown stays${kIsWeb ? '. On the web the server must allow '
                      'this origin with CORS headers '
                      '(Access-Control-Allow-Origin)' : ''}',
      );
      final refresh = image.refresh;
      if (refresh != null && !_disposed) {
        // Try again later; sooner than a long interval.
        _schedule(
          entry,
          _clock()
              .subtract(refresh)
              .add(
                Duration(
                  milliseconds: refresh.inMilliseconds < 5 * 60 * 1000
                      ? refresh.inMilliseconds
                      : 5 * 60 * 1000,
                ),
              ),
        );
      }
    }
  }().whenComplete(() => entry.inFlight = null);

  Future<void> _download(_Entry entry) async {
    final image = entry.image;
    final cached = await _readCache(image);
    final meta = cached?.meta;
    final response = await _fetcher(image.timeout)
        .get(
          image.uri!,
          {...image.headers, ...?meta?.conditionalHeaders},
          accept: 'image/*',
          allowHttp: image.allowHttp,
        )
        .timeout(image.timeout);
    final now = _clock();
    if (response == null) {
      // 304: the cache is current.
      if (meta == null) {
        throw StateError('the server answered 304 to a request without cache');
      }
      await _writeMeta(image, meta.copyWith(fetchedAt: now));
      _schedule(entry, now);
      return;
    }
    final digest = sha256Hex(response.bytes);
    if (image.sha256 != null && image.sha256 != digest) {
      throw StateError(
        'the content has sha256 $digest, not the source-sha256 that is '
        'configured; refused',
      );
    }
    if (response.bytes.isEmpty) {
      throw StateError('the answer is empty');
    }
    await files.write('${image.cacheFolder}/image', response.bytes);
    await _writeMeta(
      image,
      RemoteMeta(
        source: image.source,
        sha256: digest,
        fetchedAt: now,
        etag: response.headers['ETag'],
        lastModified: response.headers['Last-Modified'],
      ),
    );
    _log.info(() => 'image ${image.source} loaded');
    if (cached == null || cached.meta.sha256 != digest) {
      _show(entry, response.bytes);
    }
    _schedule(entry, now);
  }

  Future<({Uint8List bytes, RemoteMeta meta})?> _readCache(
    ThemeImage image,
  ) async {
    try {
      final bytes = await files.read<Uint8List>('${image.cacheFolder}/image');
      final metaText = await files.read<String>(
        '${image.cacheFolder}/meta.json',
      );
      if (bytes == null || metaText == null) {
        return null;
      }
      final meta = RemoteMeta.fromJson(jsonDecode(metaText));
      final digest = sha256Hex(bytes);
      if (meta.source != image.source || meta.sha256 != digest) {
        return null;
      }
      if (image.sha256 != null && image.sha256 != digest) {
        _log.warning(
          () =>
              'image ${image.source}: the cached file does not match '
              'source-sha256; dropped',
        );
        await files.delete(image.cacheFolder);
        return null;
      }
      return (bytes: bytes, meta: meta);
    } on Object catch (error) {
      _log.debug(() => 'image ${image.source}: no usable cache ($error)');
      return null;
    }
  }

  Future<void> _writeMeta(ThemeImage image, RemoteMeta meta) =>
      files.write('${image.cacheFolder}/meta.json', jsonEncode(meta.toJson()));

  /// Stops the timers and closes the HTTP clients the loader made.
  void dispose() {
    _disposed = true;
    if (_listening) {
      themes.removeListener(_onThemes);
      _listening = false;
    }
    for (final entry in _entries.values) {
      entry.remove();
    }
    for (final fetcher in _fetchers.values) {
      fetcher.close();
    }
    _fetchers.clear();
  }
}

final class _Entry {
  _Entry(this.image);

  final ThemeImage image;
  final attached = <ThemeImage>{};
  ImageProvider? current;
  Timer? timer;
  Future<void>? inFlight;

  // Set when the image is no longer configured or the loader is disposed:
  // nothing is shown or scheduled for it any more.
  bool removed = false;

  void remove() {
    removed = true;
    timer?.cancel();
    timer = null;
  }
}
