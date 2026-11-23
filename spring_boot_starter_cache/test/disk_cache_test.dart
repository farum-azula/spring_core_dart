// spring.cache.type: disk: entries in a CacheStore that outlive a restart
// (the Flutter starter's on the app's files, a folder elsewhere), read back
// as what was put; an AsyncCache, for methods that return a Future.
import 'dart:convert';
import 'dart:io';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:test/test.dart';

import 'books.dart';

final class Hero {
  Hero(this.name, this.level);

  factory Hero.fromJson(Object? json) {
    final map = json! as Map<String, Object?>;
    return Hero(map['name']! as String, map['level']! as int);
  }

  final String name;
  final int level;

  Map<String, Object?> toJson() => {'name': name, 'level': level};

  @override
  bool operator ==(Object other) =>
      other is Hero && other.name == name && other.level == level;

  @override
  int get hashCode => Object.hash(name, level);
}

final class _Resources implements ResourceLoader {
  @override
  Resource getResource(String location) => UrlResource(Uri.parse(location));
}

void main() {
  final introspector = Introspector()
    ..register(
      Introspection<Hero>(
        fromJson: Hero.fromJson,
        toJson: (hero) => hero.toJson(),
        className: 'Hero',
      ),
    );
  final mapper = ObjectMapper(introspector: introspector);
  late InMemoryCacheStore store;
  var now = DateTime.utc(2026, 11, 16, 12);

  DiskCacheManager manager({
    Duration? timeToLive,
    Map<String, Duration?> timeToLives = const {},
    String? version,
    int? maxSize,
    Iterable<String>? cacheNames,
  }) => DiskCacheManager(
    store: store,
    mapper: mapper,
    introspector: introspector,
    resources: _Resources(),
    timeToLive: timeToLive,
    timeToLives: timeToLives,
    version: version,
    maxSize: maxSize,
    cacheNames: cacheNames,
    clock: () => now,
  );

  DiskCache cache(DiskCacheManager manager, [String name = 'heroes']) =>
      manager.getCache(name)! as DiskCache;

  setUp(() {
    store = InMemoryCacheStore();
    now = DateTime.utc(2026, 11, 16, 12);
  });

  test('what is put comes back as what it was, after a restart too', () async {
    final first = cache(manager());
    final values = <Object, Object?>{
      'name': 'Lina',
      'level': 25,
      'kda': 3.5,
      'won': true,
      'none': null,
      'hero': Hero('Lina', 25),
      'team': [Hero('Lina', 25), Hero('Doom', 21)],
      'tags': {'carry', 'mid'},
      'by role': {'mid': Hero('Lina', 25)},
      'levels': [25, 21],
      'portrait': UrlResource(Uri.parse('https://cdn.example.com/lina.png')),
    };
    for (final MapEntry(:key, :value) in values.entries) {
      first.put(key, value);
    }
    await first.flush();
    // Another run: nothing in memory, all from the store.
    final second = cache(manager());
    for (final MapEntry(:key, :value) in values.entries) {
      final hit = await second.retrieve(key);
      expect(hit, isNotNull, reason: '$key');
      expect(hit!.value, value, reason: '$key');
      expect(hit.value.runtimeType, value.runtimeType, reason: '$key');
    }
    final team = (await second.retrieve('team'))!.value;
    expect(team, isA<List<Hero>>());
    expect(await second.retrieve('missing'), isNull);
  });

  test('an entry lives its time, by the wall clock', () async {
    final first = cache(
      manager(
        timeToLive: const Duration(hours: 1),
        timeToLives: {'short': const Duration(minutes: 1)},
      ),
    );
    final short = cache(
      manager(
        timeToLive: const Duration(hours: 1),
        timeToLives: {'short': const Duration(minutes: 1)},
      ),
      'short',
    );
    first.put('a', 'kept');
    short.put('a', 'gone soon');
    await first.flush();
    await short.flush();
    now = now.add(const Duration(minutes: 30));
    final later = manager(
      timeToLive: const Duration(hours: 1),
      timeToLives: {'short': const Duration(minutes: 1)},
    );
    expect((await cache(later).retrieve('a'))?.value, 'kept');
    expect(await cache(later, 'short').retrieve('a'), isNull);
    now = now.add(const Duration(hours: 1));
    expect(
      await cache(manager(timeToLive: const Duration(hours: 1))).retrieve('a'),
      isNull,
    );
  });

  test('an entry of another version is not read', () async {
    final first = cache(manager(version: '1.0.0'))..put('a', 'old');
    await first.flush();
    expect(
      (await cache(manager(version: '1.0.0')).retrieve('a'))?.value,
      'old',
    );
    expect(await cache(manager(version: '1.1.0')).retrieve('a'), isNull);
  });

  test('a value it cannot keep is not kept: the method runs again', () async {
    final first = cache(manager())
      ..put('stream', Object())
      ..put('empty', <Hero>[])
      ..put('mixed', ['a', 1]);
    await first.flush();
    expect(await store.list(DiskCacheManager.root), isEmpty);
  });

  test('evict, clear', () async {
    final first = cache(manager())
      ..put('a', 'one')
      ..put('b', 'two')
      ..evict('a');
    expect(first.get('a'), isNull);
    await first.flush();
    expect(await cache(manager()).retrieve('a'), isNull);
    expect((await cache(manager()).retrieve('b'))?.value, 'two');
    first.clear();
    await first.flush();
    expect(await cache(manager()).retrieve('b'), isNull);
  });

  test(
    'a key that is not the one written is a miss, whatever the hash',
    () async {
      final first = cache(manager())..put('a', 'one');
      await first.flush();
      final path = (await store.list(first.folder)).single;
      final entry = jsonDecode(
        utf8.decode((await store.read(path))!),
      ) as Map<String, Object?>;
      entry['key'] = 'another';
      await store.write(path, utf8.encode(jsonEncode(entry)));
      expect(await cache(manager()).retrieve('a'), isNull);
    },
  );

  test('past its limit, the oldest written go first', () async {
    final limited = cache(manager(maxSize: 600));
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 1));
      limited.put('key $i', 'value number $i');
    }
    await limited.flush();
    var total = 0;
    for (final path in await store.list(limited.folder)) {
      total += (await store.size(path))!;
    }
    expect(total, lessThanOrEqualTo(600));
    final fresh = cache(manager());
    expect((await fresh.retrieve('key 9'))?.value, 'value number 9');
    expect(await fresh.retrieve('key 0'), isNull);
  });

  test('fixed names: another cache is none', () {
    final fixed = manager(cacheNames: ['heroes']);
    expect(fixed.getCache('heroes'), isNotNull);
    expect(fixed.getCache('items'), isNull);
    expect(fixed.cacheNames, ['heroes']);
  });

  test('keys: the same text in every run, told apart by kind', () {
    String key(Object? k) => canonicalCacheKey(k, mapper, introspector);
    expect(key('1'), isNot(key(1)));
    expect(key(1), isNot(key(1.0)));
    expect(key(Hero('Lina', 25)), key(Hero('Lina', 25)));
    expect(key(SimpleKey(['a', 1])), '["k",["a",["i","1"]]]');
    expect(
      key(UrlResource(Uri.parse('https://x.test/a.png'))),
      '["r","https://x.test/a.png"]',
    );
    expect(cacheFileHash('a'), 'af63dc4c8601ec8c', reason: 'FNV-1a, 64 bits');
    expect(cacheFileHash(''), 'cbf29ce484222325');
  });

  test('a folder on the disk keeps the entries', () async {
    final folder = Directory.systemTemp.createTempSync('spring_cache_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final disk = DirectoryCacheStore(folder.path);
    await disk.write('spring/caches/a/1.json', utf8.encode('one'));
    await disk.write('spring/caches/a/2.json', utf8.encode('two'));
    expect(utf8.decode((await disk.read('spring/caches/a/1.json'))!), 'one');
    expect(await disk.size('spring/caches/a/2.json'), 3);
    expect(
      (await disk.list('spring/caches'))..sort(),
      ['spring/caches/a/1.json', 'spring/caches/a/2.json'],
    );
    await disk.delete('spring/caches/a/1.json');
    expect(await disk.read('spring/caches/a/1.json'), isNull);
    await disk.delete('spring/caches');
    expect(await disk.list('spring/caches'), isEmpty);
    await disk.delete('nothing/here');
  });

  group('the interceptor', () {
    test('a method that returns a Future waits for the store; a restart '
        'keeps its results', () async {
      final interceptor = CacheInterceptor(cacheManager: manager());
      final proxy = booksProxyFactory.createProxy(Books(), [
        DefaultPointcutAdvisor(
          const CacheAnnotationPointcut(),
          interceptor,
        ),
      ]) as Books;
      expect(await proxy.fetch('1'), 'fetched 1');
      expect(await proxy.fetch('1'), 'fetched 1');
      expect(proxy.count('fetch'), 1);
      await cache(manager(), 'async').flush();
      await (interceptor.cacheManager.getCache('async')! as DiskCache).flush();

      final restarted = Books();
      final again = booksProxyFactory.createProxy(restarted, [
        DefaultPointcutAdvisor(
          const CacheAnnotationPointcut(),
          CacheInterceptor(cacheManager: manager()),
        ),
      ]) as Books;
      expect(await again.fetch('1'), 'fetched 1');
      expect(restarted.count('fetch'), 0, reason: 'read from the store');
    });

    test('a method that does not return a Future on it: a start-up error', () {
      final interceptor = CacheInterceptor(cacheManager: manager());
      final find = booksSignatures.firstWhere((s) => s.name == 'find');
      expect(
        () => interceptor.cacheOperations(find),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('not a Future'), contains("'books'")),
          ),
        ),
      );
    });
  });
}
