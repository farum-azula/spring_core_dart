import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';
import 'package:spring_web_dart/spring_web_dart.dart'
    show HttpHeaders, HttpTransport;

/// A theme that comes from a URL: the keys `source`, `source-sha256` and
/// `refresh` of `spring.flutter.theme.themes.<name>`.
///
/// ```yaml
/// spring:
///   flutter:
///     theme:
///       themes:
///         brand:
///           source: github:neon/themes/ocean.yml@v3
///           source-sha256: 3f9a...   # optional: refuse other content
///           refresh: 1h              # optional: look again in the background
/// ```
///
/// Internal to the starter; [ThemeSourceLoader] loads them.
final class ThemeSource {
  /// A source of theme [name] at [uri].
  ThemeSource({
    required this.name,
    required this.address,
    this.sha256,
    this.refresh,
  });

  /// The theme's name: what the app calls it, whatever the file calls its
  /// theme; empty for the source of `spring.flutter.theme` itself, whose
  /// values every theme shares.
  final String name;

  /// Whether this is the shared source (`spring.flutter.theme.source`).
  bool get shared => name.isEmpty;

  /// The source in log lines: `spring.flutter.theme` or `theme <name>`.
  String get label => shared ? 'spring.flutter.theme' : 'theme $name';

  /// The `source`: where to download from, and how it was written.
  final RemoteAddress address;

  /// The `source` as written.
  String get configured => address.written;

  /// The address to download from.
  Uri get uri => address.uri;

  /// The digest the content must have (lowercase hexadecimal), if pinned.
  final String? sha256;

  /// How old the cache may get before it is read again in the background;
  /// `null`: never, the first download is kept for ever.
  final Duration? refresh;

  /// The folder of this source's cache below `spring/themes/`: it belongs
  /// to the source and the pin, so another one downloads again.
  late final String cacheKey = sha256HexOfString(
    '$configured\n${sha256 ?? ''}',
  );

  /// The cache folder, relative to the place `support`.
  String get cacheFolder => '$cacheRoot/$cacheKey';

  /// The folder of all the caches, relative to the place `support`.
  static const cacheRoot = 'spring/themes';

  /// The sources among [properties] (relative to `spring.flutter.theme`,
  /// as `SpringThemes` takes them), by theme name. Throws an
  /// `ArgumentError` naming the property when a value is invalid.
  static List<ThemeSource> read(
    Map<String, String> properties,
    SpringThemes themes,
  ) {
    final byName = <String, Map<String, String>>{};
    const fields = {'source', 'sourcesha256', 'refresh'};
    for (final MapEntry(:key, :value) in properties.entries) {
      final segments = key.split('.');
      if (segments.length == 1 &&
          fields.contains(ThemeValues.canonical(segments[0]))) {
        byName.putIfAbsent('', () => {})[ThemeValues.canonical(segments[0])] =
            value.trim();
        continue;
      }
      if (segments.length != 3 ||
          ThemeValues.canonical(segments[0]) != 'themes') {
        continue;
      }
      final field = ThemeValues.canonical(segments[2]);
      if (fields.contains(field)) {
        final name = themes.nameOf(segments[1]) ?? segments[1];
        byName.putIfAbsent(name, () => {})[field] = value.trim();
      }
    }
    final sources = <ThemeSource>[];
    for (final MapEntry(:key, :value) in byName.entries) {
      final text = value['source'];
      final property = key.isEmpty
          ? 'spring.flutter.theme'
          : 'spring.flutter.theme.themes.$key';
      if (text == null || text.isEmpty) {
        throw ArgumentError.value(
          value.keys.join(', '),
          '$property.source',
          'is needed with source-sha256 and refresh',
        );
      }
      final address = themes.addresses.parse(
        text,
        property: '$property.source',
      );
      final pin = value['sourcesha256']?.toLowerCase();
      if (pin != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
        throw ArgumentError.value(
          pin,
          '$property.source-sha256',
          'must be 64 hexadecimal digits',
        );
      }
      final refreshText = value['refresh'];
      sources.add(
        ThemeSource(
          name: key,
          address: address,
          sha256: pin == null || pin.isEmpty ? null : pin,
          refresh: refreshText == null || refreshText.isEmpty
              ? null
              : ThemeValues.duration(refreshText) ??
                    (throw ArgumentError.value(
                      refreshText,
                      '$property.refresh',
                      'is not a duration like 10s, 1h or 1.5d',
                    )),
        ),
      );
    }
    return sources..sort((a, b) => a.name.compareTo(b.name));
  }
}

/// The theme properties found in a downloaded file, for the theme [name].
///
/// Internal to the starter.
final class ThemeSourceContent {
  ThemeSourceContent._(this.properties, this.ignored);

  /// The properties, as `themes.<name>.<key>`.
  final Map<String, String> properties;

  /// The keys of the file that are not the theme's and were dropped.
  final List<String> ignored;

  /// Reads the YAML [text] of a theme file.
  ///
  /// The file is written like the theme part of `application.yml`: under
  /// `spring.flutter.theme` (the keys of one theme, or `themes.<any
  /// name>.*` of one), or with those keys at the top. Only the theme's
  /// look is taken, and put under [name], whatever the file calls it; every
  /// other key (another `spring.*` setting, `active`, `extends`, `source`, `refresh`)
  /// is [ignored]: a remote file never changes the application's other
  /// settings, picks the theme shown or points to more downloads.
  /// Throws a `FormatException` for text that is no YAML.
  factory ThemeSourceContent.parse(String text, String name) {
    final flat = <String, String>{};
    try {
      for (final source in YamlPropertySourceLoader().load('theme', text)) {
        if (source is! EnumerablePropertySource<Object>) {
          continue;
        }
        for (final key in source.propertyNames) {
          flat[key.replaceAllMapped(
                RegExp(r'\[(\d+)\]'),
                (m) => '.${m[1]}',
              )] =
              '${source.getProperty(
                key,
              )}';
        }
      }
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('not a YAML theme file: $error');
    }
    final withRoot = flat.keys.any(
      (key) => key == 'spring' || key.startsWith('spring.'),
    );
    final shared = <String, String>{};
    final named = <String, Map<String, String>>{};
    final ignored = <String>[];
    const prefix = '${SpringThemes.prefix}.';
    for (final MapEntry(:key, :value) in flat.entries) {
      final String relative;
      if (key.startsWith(prefix)) {
        relative = key.substring(prefix.length);
      } else if (withRoot) {
        ignored.add(key);
        continue;
      } else {
        relative = key;
      }
      final segments = relative.split('.');
      Map<String, String> into = shared;
      var path = segments;
      if (ThemeValues.canonical(segments.first) == 'themes') {
        if (segments.length < 3) {
          ignored.add(key);
          continue;
        }
        into = named.putIfAbsent(segments[1], () => {});
        path = segments.skip(2).toList();
      }
      final head = ThemeValues.canonical(path.first);
      if (path.length == 1 &&
          const {
            'active',
            'extends',
            'systemlight',
            'systemdark',
            'source',
            'sourcesha256',
            'refresh',
          }.contains(head)) {
        ignored.add(key);
        continue;
      }
      into[path.join('.')] = value;
    }
    final canonicalName = ThemeValues.canonical(name);
    final chosen = named.keys.where(
      (n) => ThemeValues.canonical(n) == canonicalName,
    );
    final theme = chosen.isNotEmpty
        ? named[chosen.first]!
        : named.length == 1
        ? named.values.first
        : (named.keys.toList()..sort()).map((n) => named[n]!).firstOrNull;
    final own = {...shared, ...?theme};
    return ThemeSourceContent._({
      for (final MapEntry(:key, :value) in own.entries)
        name.isEmpty ? key : 'themes.$name.$key': value,
    }, ignored);
  }
}

/// Loads the themes that come from a URL (`themes.<name>.source`), caches
/// them in the app's files and keeps them up to date.
///
/// How a source goes, in `ApplicationRunner.run` (so the first frame has
/// the theme):
///
/// - a cache of this source (and pin) is applied at once; with `refresh`
///   and an old cache, the file is read again in the background, with
///   `If-None-Match` / `If-Modified-Since`, and the new theme is shown as
///   soon as it arrives; without `refresh` there is no request, ever;
/// - without a cache the file is downloaded now, for [timeout] at most;
///   offline, a timeout, a bad digest, a too big or invalid file leave the
///   theme the app's own files describe, and the next start tries again.
///
/// The cache is `spring/themes/<sha256 of source and pin>/theme.yml` and
/// `meta.json` in the files' `support` place, so another `source` or
/// `source-sha256` downloads again and folders of sources no longer
/// configured are removed at start. Only `https` is followed, unless
/// `spring.remote.allow-insecure` allows `http`.
///
/// Internal to the starter.
final class ThemeSourceLoader implements ApplicationRunner {
  /// Loads [sources] into [themes], caching through [files]. [transport]
  /// is the HTTP client (the platform's by default, closed by [dispose]);
  /// [maxBytes] and [timeout] limit a download; [clock] is for tests.
  ThemeSourceLoader({
    required this.themes,
    required this.files,
    required this.sources,
    HttpTransport? transport,
    this.maxBytes = defaultMaxBytes,
    this.timeout = defaultTimeout,
    bool allowInsecure = false,
    DateTime Function()? clock,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _fetcher = RemoteFetcher(
         transport: transport,
         timeout: timeout,
         maxBytes: maxBytes,
         allowInsecure: allowInsecure,
       ),
       _clock = clock ?? DateTime.now;

  /// The sources of [environment]'s `spring.flutter.theme.themes.*`.
  /// The sources of [environment]'s `spring.flutter.theme` (its own
  /// `source` and those of `themes.*`). Every address of the themes, the
  /// sources' and the images', is checked first by the
  /// [RemoteAddressPolicy] of [environment]: an insecure one stops the
  /// start ([InsecureConnectionException]) unless
  /// `spring.remote.allow-insecure` allows it.
  factory ThemeSourceLoader.fromEnvironment(
    ConfigurableEnvironment environment, {
    required SpringThemes themes,
    required FileTemplate files,
    HttpTransport? transport,
  }) {
    final sources = ThemeSource.read(
      Binder.get(environment)
          .bind(
            SpringThemes.prefix,
            const MapType(ClassType<String>(), ClassType<String>()),
          )
          .orElse(const <String, String>{})
          .cast<String, String>(),
      themes,
    );
    final policy = RemoteAddressPolicy.of(environment)
      ..check([
        for (final source in sources) source.address,
        ...themes.downloads,
      ]);
    return ThemeSourceLoader(
      themes: themes,
      files: files,
      transport: transport,
      sources: sources,
      allowInsecure: policy.allowInsecure,
    );
  }

  /// The size a theme file may have: 1 MiB.
  static const defaultMaxBytes = 1024 * 1024;

  /// How long a download may take: 10 seconds.
  static const defaultTimeout = Duration(seconds: 10);

  static const _log = SpringLog('spring_boot_starter_flutter.ThemeSource');

  /// The themes the files are applied to.
  final SpringThemes themes;

  /// Where the cache is.
  final FileTemplate files;

  /// The sources to load.
  final List<ThemeSource> sources;

  /// The most bytes a file may have.
  final int maxBytes;

  /// The longest a download may take.
  final Duration timeout;

  final DateTime Function() _clock;
  final RemoteFetcher _fetcher;
  bool _disposed = false;
  final _timers = <String, Timer>{};
  final _inFlight = <String, Future<void>>{};

  /// Completes when no download is running; for tests and for code that
  /// waits for a refresh.
  Future<void> get idle async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.values.toList());
    }
  }

  @override
  Future<void> run(ApplicationArguments args) async {
    if (sources.isEmpty) {
      // Nothing to wait for: only what an earlier configuration left.
      unawaited(removeStaleCaches());
      return;
    }
    await removeStaleCaches();
    await Future.wait([for (final source in sources) _start(source)]);
  }

  /// Removes the cache folders of sources that are no longer configured
  /// (or whose `source` or `source-sha256` changed).
  Future<void> removeStaleCaches() async {
    try {
      final wanted = {for (final source in sources) source.cacheKey};
      final stale = <String>{};
      for (final path in await files.list('${ThemeSource.cacheRoot}/')) {
        final key = path.split('/').elementAtOrNull(2);
        if (key != null && !wanted.contains(key)) {
          stale.add(key);
        }
      }
      for (final key in stale) {
        await files.delete('${ThemeSource.cacheRoot}/$key');
        _log.debug(() => 'removed the cache of a theme source no longer used');
      }
    } on Object catch (error) {
      _log.debug(() => 'the theme caches could not be cleaned: $error');
    }
  }

  Future<void> _start(ThemeSource source) async {
    try {
      final cached = await _readCache(source);
      if (cached != null) {
        if (_apply(source, cached.text)) {
          _afterLoad(source, cached.meta.fetchedAt);
          return;
        }
        // Unusable: gone, so that no 304 answers for it.
        await files.delete(source.cacheFolder);
      }
      await _refresh(source);
    } on Object catch (error) {
      _log.warning(() => '${source.label}: $error');
    }
  }

  // Looks again when the cache is older than `refresh`: now, in the
  // background, or when it will be.
  void _afterLoad(ThemeSource source, DateTime fetchedAt) {
    final refresh = source.refresh;
    if (refresh == null || _disposed) {
      return;
    }
    final wait = fetchedAt.add(refresh).difference(_clock());
    _timers.remove(source.name)?.cancel();
    if (wait <= Duration.zero) {
      unawaited(_refresh(source));
    } else {
      _timers[source.name] = Timer(wait, () => unawaited(_refresh(source)));
    }
  }

  Future<void> _refresh(ThemeSource source) => _inFlight[source.name] ??=
      () async {
        try {
          await _download(source);
        } on Object catch (error) {
          _log.warning(
            () =>
                '${source.label}: ${source.configured} could not be '
                'loaded ($error); the theme in use stays',
          );
          final refresh = source.refresh;
          if (refresh != null && !_disposed) {
            // Try again later; sooner than a long interval.
            _afterLoad(
              source,
              _clock()
                  .subtract(refresh)
                  .add(
                    Duration(
                      milliseconds: min(refresh.inMilliseconds, 5 * 60 * 1000),
                    ),
                  ),
            );
          }
        }
      }().whenComplete(() {
        // Not an arrow: remove returns this very future, which would wait
        // for itself.
        _inFlight.remove(source.name);
      });

  Future<void> _download(ThemeSource source) async {
    final cached = await _readCache(source);
    final meta = cached?.meta;
    final response = await _fetcher
        .get(
          source.uri,
          meta?.conditionalHeaders ?? const {},
          accept: 'application/yaml, text/yaml, text/plain',
        )
        .timeout(timeout);
    final now = _clock();
    if (response == null) {
      // 304: the cache is current.
      if (meta == null) {
        throw StateError('the server answered 304 to a request without cache');
      }
      await _writeMeta(source, meta.copyWith(fetchedAt: now));
      _afterLoad(source, now);
      return;
    }
    final digest = sha256Hex(response.bytes);
    if (source.sha256 != null && source.sha256 != digest) {
      throw StateError(
        'the content has sha256 $digest, not the source-sha256 that is '
        'configured; refused',
      );
    }
    final String text;
    try {
      text = utf8.decode(response.bytes);
    } on FormatException {
      throw const FormatException('the file is not UTF-8 text');
    }
    if (!_apply(source, text, throwing: true)) {
      return;
    }
    await files.write('${source.cacheFolder}/theme.yml', text);
    await _writeMeta(
      source,
      RemoteMeta(
        source: source.configured,
        sha256: digest,
        fetchedAt: now,
        etag: response.headers[HttpHeaders.etagHeader],
        lastModified: response.headers[HttpHeaders.lastModifiedHeader],
      ),
    );
    _log.info(() => '${source.label} loaded from ${source.configured}');
    _afterLoad(source, now);
  }

  // Shows the theme in [text] as [source]'s; false when it cannot (and
  // nothing changed).
  bool _apply(ThemeSource source, String text, {bool throwing = false}) {
    try {
      final content = ThemeSourceContent.parse(text, source.name);
      if (content.ignored.isNotEmpty) {
        _log.warning(
          () =>
              '${source.label}: ${source.configured} has keys that are '
              'not a theme\'s, ignored: ${content.ignored.join(', ')}',
        );
      }
      themes.applySource(source.name, content.properties);
      return true;
    } on Object catch (error) {
      if (throwing) {
        rethrow;
      }
      _log.warning(
        () => '${source.label}: the cached file is invalid ($error)',
      );
      return false;
    }
  }

  Future<({String text, RemoteMeta meta})?> _readCache(
    ThemeSource source,
  ) async {
    try {
      final text = await files.read<String>('${source.cacheFolder}/theme.yml');
      final metaText = await files.read<String>(
        '${source.cacheFolder}/meta.json',
      );
      if (text == null || metaText == null) {
        return null;
      }
      final meta = RemoteMeta.fromJson(jsonDecode(metaText));
      if (meta.source != source.configured ||
          meta.sha256 != sha256HexOfString(text) ||
          (source.sha256 != null && meta.sha256 != source.sha256)) {
        return null;
      }
      return (text: text, meta: meta);
    } on Object catch (error) {
      _log.debug(() => '${source.label}: no usable cache ($error)');
      return null;
    }
  }

  Future<void> _writeMeta(ThemeSource source, RemoteMeta meta) =>
      files.write('${source.cacheFolder}/meta.json', jsonEncode(meta.toJson()));

  /// Stops the timers and closes the HTTP client if the loader made it.
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _fetcher.close();
  }
}
