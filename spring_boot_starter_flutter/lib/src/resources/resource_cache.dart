import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/files/file_cache_store.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/properties/flutter_properties.dart';
import 'package:spring_boot_starter_flutter/src/resources/blob_uri.dart';
import 'package:spring_boot_starter_flutter/src/resources/resource_image.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show HttpHeaders;

/// An `http:` or `https:` resource that the app downloads once and keeps
/// in its files ([ResourceCache]): read from the disk from then on, and
/// asked again in the background past its age.
///
/// It is what the `ResourceLoader` gives for such an address (a `Resource`
/// of `@Value`, `getResource`), what `ResourceView` and `ResourceImage`
/// show, and a key `@Cacheable` can make of its content's [version]
/// (`spring.cache.resource-version`).
abstract interface class CachedResource implements VersionedResource {
  /// The media type the server gave (`image/png`), `null` before the
  /// resource was read or when it gave none.
  String? get contentType;

  /// When it was last downloaded or found unchanged, `null` before.
  DateTime? get fetchedAt;

  /// Asks the server now whether it changed, and keeps the new one.
  Future<void> refresh();

  /// Forgets what is kept: the next read downloads it again.
  Future<void> evict();

  /// The kept file on the disk, for a player that wants a file; `null` in
  /// a browser, and before it is kept.
  Future<String?> filePath();

  /// An address a player can play it from: the kept file (`file:`), a
  /// `blob:` of it in a browser, or, while it is still being kept, its own
  /// address (and it is kept in the background for the next time).
  Future<Uri> playableUri();
}

/// The resources downloaded and kept, `spring.flutter.resources.cache.*`.
///
/// Each one is a folder of the store, `spring/resources/<sha256 of the
/// address>/`, with `data` (the bytes) and `meta.json` (the address
/// without its query, so a signed address's token is not written; the
/// digest of the bytes, the media type, when it was fetched, `ETag` and
/// `Last-Modified`). A kept resource is read from the disk; past its age
/// (`max-age`, or its rule's) it is still read from the disk and asked again
/// in the background with `If-None-Match` / `If-Modified-Since`, an
/// unchanged one costing no download. Bytes that do not match their digest
/// are dropped and downloaded again. Past `max-size` the least recently
/// used go first; the folder is the resources' own, nothing else in the
/// store counts towards it.
///
/// Only `https` resources are kept (`http` with
/// `spring.remote.allow-insecure`), at most `max-entry-size` each (50 MB
/// by default). A response with `Cache-Control: no-store` is kept nowhere,
/// one with `private` for the run only, not on the disk.
final class ResourceCache {
  /// The cache in its folder of [store], downloading with [fetcher], by
  /// [properties]; [clock] is the time, for a test's own.
  ResourceCache({
    required this.store,
    required RemoteFetcher fetcher,
    this.properties = const FlutterResourcesCacheProperties(),
    DateTime Function()? clock,
    // ignore: prefer_initializing_formals, named parameters cannot be private
  }) : _fetcher = fetcher,
       _clock = clock ?? DateTime.now,
       _limited = switch (properties.maxSize) {
         final size? => LimitedCacheStore(
           store,
           root: root,
           maxBytes: size.toBytes(),
         ),
         null => null,
       };

  /// The folder of every resource in the store.
  static const String root = 'spring/resources';

  /// Where the resources are kept, in [root].
  final CacheStore store;

  final LimitedCacheStore? _limited;

  CacheStore get _files => _limited ?? store;

  /// The settings.
  final FlutterResourcesCacheProperties properties;

  final RemoteFetcher _fetcher;
  final DateTime Function() _clock;
  final Map<String, Future<_Kept?>> _inFlight = {};
  final Map<String, _Kept> _known = {};

  static const _log = SpringLog('spring_boot_starter_flutter.ResourceCache');

  /// Whether [uri] is kept: an `https` address no rule leaves out, an
  /// `http` one only with `spring.remote.allow-insecure` (an answer that
  /// anyone on the way could have changed is not kept past the network).
  bool keeps(Uri uri) =>
      properties.enabled &&
      (uri.scheme == 'https' ||
          (uri.scheme == 'http' && _fetcher.allowInsecure)) &&
      (_rule(uri)?.enabled ?? true);

  // What the response's Cache-Control lets this cache do (RFC 9111): keep
  // nothing for `no-store`; keep for this run only, not on the disk, for
  // `private` (an answer for one user, which the files of a shared device
  // must not keep).
  static ({bool atAll, bool onDisk}) _storable(HttpHeaders headers) {
    final directives = [
      for (final value in headers.getAll(HttpHeaders.cacheControlHeader))
        for (final part in value.split(','))
          part.split('=').first.trim().toLowerCase(),
    ];
    final noStore = directives.contains('no-store');
    return (
      atAll: !noStore,
      onDisk: !noStore && !directives.contains('private'),
    );
  }

  /// How long a kept [uri] is used as it is.
  Duration maxAgeOf(Uri uri) => _rule(uri)?.maxAge ?? properties.maxAge;

  ResourceCacheLocation? _rule(Uri uri) {
    final address = '$uri';
    for (final rule in properties.locations) {
      if (_matches(rule.pattern, address)) {
        return rule;
      }
    }
    return null;
  }

  // `**` any characters, `*` any but `/`.
  static bool _matches(String pattern, String address) {
    final regex = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final char = pattern[i];
      if (char == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          regex.write('.*');
          i++;
        } else {
          regex.write('[^/]*');
        }
      } else {
        regex.write(RegExp.escape(char));
      }
    }
    regex.write(r'$');
    return RegExp(regex.toString()).hasMatch(address);
  }

  /// The resource of [uri], read through this cache.
  CachedResource resource(Uri uri) => _CachedUrlResource(this, uri);

  String _folder(Uri uri) => '$root/${sha256HexOfString('$uri')}';

  /// Closes the HTTP client it made and writes what it knows of its
  /// limit.
  Future<void> close() async {
    _fetcher.close();
    await _limited?.flush();
  }

  /// Forgets [uri].
  Future<void> evict(Uri uri) async {
    _known.remove('$uri');
    await _files.delete(_folder(uri));
  }

  /// Forgets every resource.
  Future<void> clear() async {
    _known.clear();
    await _files.delete(root);
  }

  /// The bytes the resources take now.
  Future<int> size() async {
    var total = 0;
    for (final path in await _files.list(root)) {
      total += await _files.size(path) ?? 0;
    }
    return total;
  }

  // The kept resource of [uri]: from the store, downloaded when there is
  // none (or [refresh]), asked again in the background past its age.
  Future<_Kept> _get(Uri uri, {bool refresh = false}) async {
    final address = '$uri';
    if (!refresh) {
      final kept = _known[address] ?? await _read(uri);
      if (kept != null) {
        _known[address] = kept;
        if (_clock().difference(kept.meta.fetchedAt) > maxAgeOf(uri)) {
          unawaited(
            _download(uri, kept).then<void>(
              (_) {},
              onError: (Object error) =>
                  _log.debug(() => '$uri not asked again: $error'),
            ),
          );
        }
        return kept;
      }
    }
    final kept = await _download(uri, refresh ? _known[address] : null);
    return kept ?? (throw StateError('$uri: nothing downloaded'));
  }

  Future<_Kept?> _read(Uri uri) async {
    final folder = _folder(uri);
    final metaBytes = await _files.read('$folder/meta.json');
    if (metaBytes == null) {
      return null;
    }
    final _Meta meta;
    try {
      meta = _Meta.fromJson(jsonDecode(utf8.decode(metaBytes)));
    } on Object {
      await _files.delete(folder);
      return null;
    }
    final bytes = await _files.read('$folder/data');
    if (bytes == null || sha256Hex(bytes) != meta.sha256) {
      await _files.delete(folder);
      return null;
    }
    return _Kept(bytes, meta);
  }

  // Downloads [uri] (one download at a time per address), asking with the
  // validators of [kept]: a 304 renews it.
  Future<_Kept?> _download(Uri uri, _Kept? kept) {
    final address = '$uri';
    return _inFlight[address] ??= () async {
      try {
        final response = await _fetcher.get(
          uri,
          kept?.meta.conditionalHeaders ?? const {},
          accept: '*/*',
        );
        final now = _clock();
        if (response == null) {
          if (kept == null) {
            return null;
          }
          final renewed = _Kept(kept.bytes, kept.meta.renewed(now));
          await _files.write(
            '${_folder(uri)}/meta.json',
            utf8.encode(jsonEncode(renewed.meta.toJson())),
          );
          return _known[address] = renewed;
        }
        final storable = _storable(response.headers);
        final meta = _Meta(
          // Without its query and user: a signed address's token is not written.
          source: '${uri.origin}${uri.path}',
          sha256: sha256Hex(response.bytes),
          fetchedAt: now,
          contentType: response.headers[HttpHeaders.contentTypeHeader],
          etag: response.headers['ETag'],
          lastModified: response.headers['Last-Modified'],
          size: response.bytes.length,
        );
        final fresh = _Kept(response.bytes, meta);
        if (!storable.onDisk) {
          // What an earlier answer left there is not kept past this one.
          await _files.delete(_folder(uri));
        }
        if (!storable.atAll) {
          _known.remove(address);
          return fresh;
        }
        if (keeps(uri) && storable.onDisk) {
          final folder = _folder(uri);
          await _files.write('$folder/data', response.bytes);
          await _files.write(
            '$folder/meta.json',
            utf8.encode(jsonEncode(meta.toJson())),
          );
        }
        return _known[address] = fresh;
      } finally {
        unawaited(_inFlight.remove(address));
      }
    }();
  }

  Future<String?> _filePath(Uri uri) async {
    final files = store;
    if (files is! FileCacheStore || await _read(uri) == null) {
      return null;
    }
    return files.filePath('${_folder(uri)}/data');
  }
}

final class _Kept {
  _Kept(this.bytes, this.meta);

  final Uint8List bytes;
  final _Meta meta;
}

final class _Meta {
  const _Meta({
    required this.source,
    required this.sha256,
    required this.fetchedAt,
    required this.size,
    this.contentType,
    this.etag,
    this.lastModified,
  });

  factory _Meta.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return _Meta(
      source: map['source']! as String,
      sha256: map['sha256']! as String,
      fetchedAt: DateTime.parse(map['fetchedAt']! as String),
      size: (map['size'] as int?) ?? 0,
      contentType: map['contentType'] as String?,
      etag: map['etag'] as String?,
      lastModified: map['lastModified'] as String?,
    );
  }

  final String source;
  final String sha256;
  final DateTime fetchedAt;
  final int size;
  final String? contentType;
  final String? etag;
  final String? lastModified;

  _Meta renewed(DateTime at) => _Meta(
    source: source,
    sha256: sha256,
    fetchedAt: at,
    size: size,
    contentType: contentType,
    etag: etag,
    lastModified: lastModified,
  );

  Map<String, String> get conditionalHeaders => {
    HttpHeaders.ifNoneMatchHeader: ?etag,
    HttpHeaders.ifModifiedSinceHeader: ?lastModified,
  };

  Map<String, Object?> toJson() => {
    'source': source,
    'sha256': sha256,
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'size': size,
    'contentType': ?contentType,
    'etag': ?etag,
    'lastModified': ?lastModified,
  };
}

final class _CachedUrlResource extends AbstractResource
    implements CachedResource {
  _CachedUrlResource(this._cache, this.uri);

  final ResourceCache _cache;

  @override
  final Uri uri;

  _Kept? get _kept => _cache._known['$uri'];

  @override
  String get description => 'URL [$uri]';

  @override
  String? get filename =>
      uri.pathSegments.isEmpty ? null : uri.pathSegments.last;

  @override
  String? get version => _kept?.meta.sha256;

  @override
  String? get contentType => _kept?.meta.contentType;

  @override
  DateTime? get fetchedAt => _kept?.meta.fetchedAt;

  // Like a UrlResource: whether the server has it is known when it is read.
  @override
  bool exists() => true;

  @override
  Future<Uint8List> readAsBytes() async => (await _cache._get(uri)).bytes;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  @override
  Future<void> refresh() async {
    await _cache._get(uri, refresh: true);
  }

  @override
  Future<void> evict() => _cache.evict(uri);

  @override
  Future<String?> filePath() => _cache._filePath(uri);

  @override
  Future<Uri> playableUri() async {
    if (await filePath() case final path?) {
      return Uri.file(path);
    }
    final kept = _kept ?? await _cache._read(uri);
    if (kept != null) {
      return blobUri(kept.bytes, kept.meta.contentType) ?? uri;
    }
    // Played from the network this time, kept for the next.
    unawaited(
      _cache._get(uri).then<void>((_) {}, onError: (Object _) {}),
    );
    return uri;
  }

  @override
  Resource createRelative(String relativePath) =>
      _cache.resource(uri.resolve(relativePath));
}

/// Has the application's `ResourceLoader` give an `http:` or `https:`
/// address the [ResourceCache] keeps as a [CachedResource] (a `Resource` of
/// `@Value`, `getResource`, a `ResourceView`), and the running application
/// read [ResourceImage]s. The starter registers it.
final class CachedResourceRegistrar
    implements BeanFactoryPostProcessor, ApplicationContextAware {
  /// The registrar.
  CachedResourceRegistrar();

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
    ResourceCache? cache;
    context.addProtocolResolver(
      FunctionProtocolResolver((location, loader) {
        if (!location.startsWith('https:') && !location.startsWith('http:')) {
          return null;
        }
        final uri = Uri.tryParse(location);
        final found = cache ??= beanFactory.findBean<ResourceCache>();
        return uri == null || found == null || !found.keeps(uri)
            ? null
            : found.resource(uri);
      }),
    );
    ResourceImage.application = context;
  }
}
