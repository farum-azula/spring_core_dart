// The resources downloaded and kept (spring.flutter.resources.cache): read
// from the app's files once kept, across starts too, asked again in the
// background past their age; their limit over their own folder
// (spring.flutter.resources.cache.max-size); ResourceImage and ResourceView.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/remote_cache.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner;

// A 1x1 PNG.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

// A server of one file, its ETag the version of its content.
class _Server implements HttpTransport {
  _Server(this.body);

  List<int> body;
  String type = 'image/png';
  var version = 1;
  final requests = <HttpRequest>[];

  @override
  Future<HttpResponse> send(HttpRequest request) =>
      throw UnimplementedError('only stream is used');

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    final etag = '"v$version"';
    if (request.headers['If-None-Match'] == etag) {
      return StreamedHttpResponse(
        304,
        headers: HttpHeaders({'ETag': etag}),
        body: const Stream.empty(),
        request: request,
      );
    }
    return StreamedHttpResponse(
      200,
      headers: HttpHeaders({'ETag': etag, 'Content-Type': type}),
      body: Stream.value(Uint8List.fromList(body)),
      request: request,
    );
  }

  @override
  void close() {}
}

void main() {
  final uri = Uri.parse('https://cdn.test/heroes/lina.png');
  late InMemoryCacheStore store;
  late _Server server;
  var now = DateTime.utc(2026, 11, 16, 12);

  ResourceCache cache({
    FlutterResourcesCacheProperties properties =
        const FlutterResourcesCacheProperties(),
  }) => ResourceCache(
    store: store,
    properties: properties,
    clock: () => now,
    fetcher: RemoteFetcher(
      transport: server,
      timeout: const Duration(seconds: 5),
      maxBytes: 1 << 20,
    ),
  );

  setUp(() {
    store = InMemoryCacheStore();
    server = _Server(_png);
    now = DateTime.utc(2026, 11, 16, 12);
  });

  group('ResourceCache', () {
    test('downloaded once, then read from the store, across starts', () async {
      final resource = cache().resource(uri);
      expect(resource.version, isNull, reason: 'not read yet');
      expect(await resource.readAsBytes(), _png);
      expect(resource.contentType, 'image/png');
      expect(resource.version, isNotNull);
      expect(server.requests, hasLength(1));
      // Another start: nothing in memory, all from the store.
      final again = cache().resource(uri);
      expect(await again.readAsBytes(), _png);
      expect(again.version, resource.version);
      expect(server.requests, hasLength(1), reason: 'no network');
    });

    test('past its age: read as kept, asked again in the background', () async {
      await cache().resource(uri).readAsBytes();
      now = now.add(const Duration(days: 8));
      final later = cache();
      final resource = later.resource(uri);
      expect(await resource.readAsBytes(), _png, reason: 'at once, as kept');
      await pumpEventQueue();
      expect(server.requests, hasLength(2));
      expect(server.requests.last.headers['If-None-Match'], '"v1"');
      expect(resource.fetchedAt, now, reason: 'a 304 renews it');
    });

    test('a changed file replaces the kept one when asked again', () async {
      final resource = cache().resource(uri);
      await resource.readAsBytes();
      final before = resource.version;
      server
        ..body = utf8.encode('another picture')
        ..version = 2;
      await resource.refresh();
      expect(await resource.readAsBytes(), utf8.encode('another picture'));
      expect(resource.version, isNot(before));
      expect(
        await cache().resource(uri).readAsBytes(),
        utf8.encode('another picture'),
      );
    });

    test('bytes that do not match their digest are downloaded again', () async {
      await cache().resource(uri).readAsBytes();
      final data = (await store.list(ResourceCache.root)).firstWhere(
        (path) => path.endsWith('/data'),
      );
      await store.write(data, utf8.encode('broken'));
      expect(await cache().resource(uri).readAsBytes(), _png);
      expect(server.requests, hasLength(2));
    });

    test('rules by address: not kept, or an age of their own', () async {
      final ruled = cache(
        properties: const FlutterResourcesCacheProperties(
          locations: [
            ResourceCacheLocation(
              pattern: 'https://api.test/**',
              enabled: false,
            ),
            ResourceCacheLocation(
              pattern: 'https://cdn.test/heroes/*',
              maxAge: Duration(days: 30),
            ),
          ],
        ),
      );
      expect(ruled.keeps(Uri.parse('https://api.test/v1/match/1')), isFalse);
      expect(ruled.keeps(uri), isTrue);
      expect(ruled.maxAgeOf(uri), const Duration(days: 30));
      expect(
        ruled.maxAgeOf(Uri.parse('https://cdn.test/items/blink.png')),
        const Duration(days: 7),
      );
      expect(ruled.keeps(Uri.parse('asset:assets/a.png')), isFalse);
      expect(
        cache(
          properties: const FlutterResourcesCacheProperties(enabled: false),
        ).keeps(uri),
        isFalse,
      );
    });

    test('evict, clear, size', () async {
      final kept = cache();
      final resource = kept.resource(uri);
      await resource.readAsBytes();
      expect(await kept.size(), greaterThan(_png.length));
      await resource.evict();
      expect(await store.list(ResourceCache.root), isEmpty);
      await resource.readAsBytes();
      await kept.clear();
      expect(await kept.size(), 0);
    });

    test('past max-size the least recently used go; what another cache '
        'keeps in the store does not count', () async {
      final axe = Uri.parse('https://cdn.test/heroes/axe1.png');
      await cache().resource(uri).readAsBytes();
      final one = await cache().size();
      await store.delete(ResourceCache.root);
      const profiles = 'spring/caches/profiles/p.json';
      await store.write(profiles, List.filled(one * 4, 1));
      final limited = cache(
        properties: FlutterResourcesCacheProperties(
          maxSize: DataSize.ofBytes(one * 3 ~/ 2),
        ),
      );
      await limited.resource(uri).readAsBytes();
      await limited.resource(axe).readAsBytes();
      await limited.close();
      expect(await store.read(profiles), hasLength(one * 4));
      server.requests.clear();
      await cache().resource(axe).readAsBytes();
      expect(server.requests, isEmpty, reason: 'the last one is kept');
      await cache().resource(uri).readAsBytes();
      expect(server.requests, hasLength(1), reason: 'the first one went');
    });

    test('a player gets the network address the first time, the kept file '
        'after', () async {
      final kept = cache();
      final clip = kept.resource(Uri.parse('https://cdn.test/clip.mp4'));
      expect(await clip.playableUri(), Uri.parse('https://cdn.test/clip.mp4'));
      await pumpEventQueue();
      expect(server.requests, hasLength(1), reason: 'kept in the background');
      // An InMemoryCacheStore has no files: the address stays.
      expect(await clip.filePath(), isNull);
    });
  });

  group('LimitedCacheStore', () {
    test('past its limit the least recently used go first', () async {
      var clock = DateTime.utc(2026);
      final limited = LimitedCacheStore(
        store,
        root: 'spring/r',
        maxBytes: 30,
        clock: () => clock = clock.add(const Duration(seconds: 1)),
      );
      await limited.write('spring/r/a', List.filled(10, 1));
      await limited.write('spring/r/b', List.filled(10, 2));
      await limited.write('spring/r/c', List.filled(10, 3));
      await limited.read('spring/r/a'); // used again: b is the oldest now
      await limited.write('spring/r/d', List.filled(10, 4));
      expect(await store.read('spring/r/b'), isNull);
      expect(await store.read('spring/r/a'), isNotNull);
      expect(await limited.used, 30);
    });

    test('what is outside its folder is neither counted nor dropped', () async {
      await store.write('spring/caches/x', List.filled(100, 1));
      final limited = LimitedCacheStore(store, root: 'spring/r', maxBytes: 30);
      await limited.write('spring/caches/y', List.filled(100, 2));
      await limited.write('spring/r/a', List.filled(20, 3));
      expect(await limited.used, 20);
      expect(await store.read('spring/caches/x'), isNotNull);
      expect(await limited.read('spring/caches/y'), hasLength(100));
    });

    test('what it knows is kept in the store for the next start', () async {
      final limited = LimitedCacheStore(
        store,
        root: 'spring/r',
        maxBytes: 100,
      );
      await limited.write('spring/r/a', List.filled(40, 1));
      await limited.write('spring/r/b', List.filled(40, 2));
      await limited.flush();
      expect(await store.read(limited.indexPath), isNotNull);
      final next = LimitedCacheStore(store, root: 'spring/r', maxBytes: 100);
      expect(await next.used, 80);
      await next.write('spring/r/c', List.filled(40, 3));
      expect(await next.used, lessThanOrEqualTo(100));
      expect(await next.list('spring/r'), isNot(contains(next.indexPath)));
    });

    test('without an index, what is there is measured once', () async {
      await store.write('spring/r/old', List.filled(70, 1));
      await store.write('spring/other', List.filled(70, 1));
      final limited = LimitedCacheStore(
        store,
        root: 'spring/r',
        maxBytes: 100,
      );
      expect(await limited.used, 70);
      await limited.write('spring/r/new', List.filled(50, 2));
      expect(await store.read('spring/r/old'), isNull);
      expect(await store.read('spring/other'), isNotNull);
    });
  });

  group('the beans', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withBean<FileStore>(InMemoryFileStore.new);

    test('an https resource of the ResourceLoader is kept', () {
      runner.run((context) {
        expect(context.startupFailure, isNull);
        expect(context.getBean<CacheStore>(), isA<FileCacheStore>());
        expect(
          context.context.getResource('https://cdn.test/a.png'),
          isA<CachedResource>(),
        );
        expect(ResourceImage.application, same(context.context));
      });
    });

    test('the limit is the resources\' own, the store stays the place; off, '
        'an https resource is a plain one', () {
      runner
          .withPropertyValues([
            'spring.flutter.resources.cache.max-size=10MB',
            'spring.flutter.resources.cache.enabled=false',
          ])
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context.getBean<CacheStore>(), isA<FileCacheStore>());
            expect(
              context.getBean<ResourceCache>().properties.maxSize?.toBytes(),
              10 * 1024 * 1024,
            );
            expect(
              context.context.getResource('https://cdn.test/a.png'),
              isNot(isA<CachedResource>()),
            );
          });
    });
  });

  group('ResourceImage and ResourceView', () {
    final loader = _Loader({
      'https://cdn.test/a.png': ByteArrayResource(_png, description: 'a.png'),
      'https://cdn.test/notes.pdf': ByteArrayResource(
        utf8.encode('%PDF'),
        description: 'notes.pdf',
      ),
    });

    setUp(() => ResourceImage.application = loader);
    tearDown(() => ResourceImage.application = null);

    test('one image per location and scale', () {
      expect(
        const ResourceImage('https://cdn.test/a.png'),
        const ResourceImage('https://cdn.test/a.png'),
      );
      expect(
        const ResourceImage('https://cdn.test/a.png'),
        isNot(const ResourceImage('https://cdn.test/a.png', scale: 2)),
      );
    });

    testWidgets('the placeholder, then the image, faded in', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceView(
            'https://cdn.test/a.png',
            width: 20,
            height: 20,
            placeholder: Text('loading'),
            semanticLabel: 'Lina',
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('loading'), findsNothing);
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        'Lina',
      );
    });

    testWidgets('a type no renderer shows: the error', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ResourceView(
            'https://cdn.test/notes.pdf',
            error: (context, error) => Text('cannot: $error'),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.textContaining('application/pdf'), findsOneWidget);
    });

    test('media types by extension', () {
      expect(ResourceView.mediaTypeOf('lina.PNG'), 'image/png');
      expect(ResourceView.mediaTypeOf('clip.mp4'), 'video/mp4');
      expect(ResourceView.mediaTypeOf('noext'), isNull);
    });
  });
}

final class _Loader implements ResourceLoader {
  _Loader(this.resources);

  final Map<String, Resource> resources;

  @override
  Resource getResource(String location) =>
      resources[location] ?? (throw StateError('no $location'));
}
