// The disk cache against Spring's cache contract: an entry expires within
// the run too, a key is matched by what it is (never by a toString two
// keys share), two classes of one name are not confused, a cache name is
// one folder, a put does not read the whole cache, the folder is private.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_starter_cache/spring_auto_configuration.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_cache/src/directory_cache_store_stub.dart'
    as browser;
import 'package:test/test.dart';

import 'books.dart';

final class Point {
  Point(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

final class ShopBook {
  ShopBook(this.title);

  final String title;
}

final class LibraryBook {
  LibraryBook(this.title);

  final String title;
}

Introspection<T> _book<T extends Object>(
  T Function(String) create,
  String Function(T) title, {
  String? library,
}) => Introspection<T>(
  className: 'Book',
  library: library,
  properties: [
    IntrospectedProperty<T>(
      'title',
      typeInfo: const ClassType<String>(),
      get: title,
    ),
  ],
  constructor: IntrospectedConstructor<T>(
    parameters: const [
      IntrospectedParameter(
        'title',
        type: ClassType<String>(),
        isRequired: true,
      ),
    ],
    create: (positional, named) => create(positional.single! as String),
  ),
);

// Counts the reads, and makes the second one slow.
final class _CountingStore implements CacheStore {
  final inner = InMemoryCacheStore();
  int reads = 0;
  Duration secondRead = Duration.zero;

  @override
  Future<Uint8List?> read(String path) async {
    final read = ++reads;
    final bytes = await inner.read(path);
    if (read == 2) {
      await Future<void>.delayed(secondRead);
    }
    return bytes;
  }

  @override
  Future<void> write(String path, List<int> bytes) => inner.write(path, bytes);

  @override
  Future<void> delete(String path) => inner.delete(path);

  @override
  Future<List<String>> list(String path) => inner.list(path);

  @override
  Future<int?> size(String path) => inner.size(path);
}

class _Bad {
  Future<String> both(String a) async => 'x';
}

class _BadProxy extends _Bad {
  _BadProxy(this._target, this._invoker);

  final _Bad _target;
  final ProxyInvoker _invoker;

  @override
  Future<String> both(String a) => _invoker.invokeAsync<String>(
    proxy: this,
    target: _target,
    methodIndex: 0,
    arguments: [a],
    original: (args) => _target.both(args[0]! as String),
  );
}

final _badFactory = AopProxyFactory(
  signatures: const [
    MethodSignature(
      name: 'both',
      declaringType: '_Bad',
      targetType: '_Bad',
      declaringTypes: ['_Bad'],
      returnType: 'Future',
      parameterTypes: ['String'],
      parameterNames: ['a'],
      annotations: [Cacheable('c', key: '#a', keyGenerator: 'g')],
      annotationTypes: ['Cacheable'],
      targetTypes: ['_Bad'],
    ),
  ],
  create: (target, invoker) => _BadProxy(target as _Bad, invoker),
);

void main() {
  final introspector = Introspector();
  final mapper = ObjectMapper(introspector: introspector);
  late InMemoryCacheStore store;
  var now = DateTime.utc(2026, 3, 4);

  DiskCacheManager manager({
    Duration? timeToLive,
    int? maxSize,
    CacheStore? on,
    Introspector? classes,
  }) => DiskCacheManager(
    store: on ?? store,
    mapper: classes == null ? mapper : ObjectMapper(introspector: classes),
    introspector: classes ?? introspector,
    timeToLive: timeToLive,
    maxSize: maxSize,
    clock: () => now,
  );

  DiskCache cache(DiskCacheManager manager, [String name = 'c']) =>
      manager.getCache(name)! as DiskCache;

  setUp(() {
    store = InMemoryCacheStore();
    now = DateTime.utc(2026, 3, 4);
  });

  test('an entry expires within the run too (CD-1)', () async {
    final c = cache(manager(timeToLive: const Duration(minutes: 1)))
      ..put('a', 'v');
    await c.flush();
    expect(c.get('a')?.value, 'v');
    now = now.add(const Duration(minutes: 5));
    expect(c.get('a'), isNull);
    expect(await c.retrieve('a'), isNull);
  });

  test('an expired entry is deleted when found (CD-11)', () async {
    final c = cache(manager(timeToLive: const Duration(seconds: 1)));
    for (var i = 0; i < 5; i++) {
      c.put('k$i', 'v');
    }
    await c.flush();
    now = now.add(const Duration(days: 1));
    final later = cache(manager(timeToLive: const Duration(seconds: 1)));
    for (var i = 0; i < 5; i++) {
      expect(await later.retrieve('k$i'), isNull);
    }
    await later.flush();
    expect(await store.list(later.folder), isEmpty);
  });

  test('invalidate is true only for entries this run knew of (CD-11)', () {
    expect(cache(manager(), 'empty').invalidate(), isFalse);
    final c = cache(manager())..put('a', 'v');
    expect(c.invalidate(), isTrue);
  });

  test(
    'a key without a stable form is not kept: no other key gets its value '
    '(CD-2)',
    () async {
      final c = cache(manager())..put(Point(1, 2), 'one-two');
      await c.flush();
      expect(await store.list(c.folder), isEmpty);
      expect(await cache(manager()).retrieve(Point(3, 4)), isNull);
      expect(await c.retrieve(Point(3, 4)), isNull);
      c.put((1, 2), 'record');
      await c.flush();
      expect(await store.list(c.folder), isEmpty);
    },
  );

  test('string parts of a key are not mixed up (CD-2)', () async {
    final c = cache(manager())..put(SimpleKey(['a', 'b']), 'AB');
    await c.flush();
    expect(await cache(manager()).retrieve(SimpleKey(['a,s:b'])), isNull);
    expect(
      (await cache(manager()).retrieve(SimpleKey(['a', 'b'])))?.value,
      'AB',
    );
    String key(Object? k) => canonicalCacheKey(k, mapper, introspector);
    expect(key(SimpleKey(['a', 'b'])), isNot(key(SimpleKey(['a,s:b']))));
    expect(key(['a', 'b']), isNot(key(['a"', 'b'])));
    expect(key({'a': 1, 'b': 2}), key({'b': 2, 'a': 1}));
    expect(key(_Tint.red), isNot(key(_Mood.red)));
  });

  test('two classes of one name are told apart by their library (INT-1)', () {
    final classes = Introspector()
      ..register(
        _book<ShopBook>(
          ShopBook.new,
          (b) => b.title,
          library: 'package:shop/book.dart',
        ),
      )
      ..register(
        _book<LibraryBook>(
          LibraryBook.new,
          (b) => b.title,
          library: 'package:library/book.dart',
        ),
      );
    expect(
      classes.byQualifiedName('package:library/book.dart#Book')?.type,
      LibraryBook,
    );
    expect(
      classes.byQualifiedName('package:shop/book.dart#Book')?.type,
      ShopBook,
    );
  });

  test('two classes of one name come back as what was put (INT-1)', () async {
    final classes = Introspector()
      ..register(
        _book<ShopBook>(
          ShopBook.new,
          (b) => b.title,
          library: 'package:shop/book.dart',
        ),
      )
      ..register(
        _book<LibraryBook>(
          LibraryBook.new,
          (b) => b.title,
          library: 'package:library/book.dart',
        ),
      );
    final c = cache(manager(classes: classes))
      ..put('k', LibraryBook('Dune'))
      ..put(ShopBook('X'), 'shop');
    await c.flush();
    final again = cache(manager(classes: classes));
    expect((await again.retrieve('k'))?.value, isA<LibraryBook>());
    expect(await again.retrieve(LibraryBook('X')), isNull);
    expect((await again.retrieve(ShopBook('X')))?.value, 'shop');
  });

  test(
    'two classes of one name without their library are not kept (INT-1)',
    () async {
      final classes = Introspector()
        ..register(_book<ShopBook>(ShopBook.new, (b) => b.title))
        ..register(_book<LibraryBook>(LibraryBook.new, (b) => b.title));
      expect(classes.byQualifiedName('Book'), isNull);
      final c = cache(manager(classes: classes))
        ..put('k', LibraryBook('Dune'))
        ..put(ShopBook('X'), 'shop');
      await c.flush();
      expect(await store.list(c.folder), isEmpty);
    },
  );

  test('a cache name is one folder (CD-10)', () async {
    final m = manager();
    final admins = cache(m, 'users/admins')..put('root', 'R');
    await admins.flush();
    final users = cache(m, 'users')..clear();
    await users.flush();
    expect(
      (await cache(manager(), 'users/admins').retrieve('root'))?.value,
      'R',
    );
    expect(cache(m, '..').folder, isNot(contains('/../')));
    expect(cache(m, '..').folder, endsWith('/%2E%2E'));
  });

  test('with max-size, a put does not read the whole cache (CD-7)', () async {
    final counting = _CountingStore();
    final c = cache(manager(maxSize: 1 << 30, on: counting));
    for (var i = 0; i < 50; i++) {
      c.put('key $i', 'value $i');
    }
    await c.flush();
    expect(counting.reads, lessThanOrEqualTo(1));
    final limited = cache(manager(maxSize: 600, on: counting), 'small');
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 1));
      limited.put('key $i', 'value number $i');
    }
    await limited.flush();
    var total = 0;
    for (final path in await counting.list(limited.folder)) {
      total += (await counting.size(path))!;
    }
    expect(total, lessThanOrEqualTo(600));
    expect(
      (await cache(manager(on: counting), 'small').retrieve('key 9'))?.value,
      'value number 9',
    );
  });

  test(
    'sync: true on a disk cache runs the method once for concurrent callers '
    '(CD-3)',
    () async {
      final counting = _CountingStore()
        ..secondRead = const Duration(milliseconds: 50);
      final books = Books();
      final proxy = booksProxyFactory.createProxy(books, [
        DefaultPointcutAdvisor(
          const CacheAnnotationPointcut(),
          CacheInterceptor(cacheManager: manager(on: counting)),
        ),
      ]) as Books;
      final first = proxy.fetchShared('1');
      final second = proxy.fetchShared('1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      books.pending['1']!.complete('first');
      expect(await first, 'first');
      expect(await second, 'first');
      expect(books.count('fetchShared'), 1);
    },
  );

  test('the folder store: private, no symbolic link (CA-1)', () async {
    final parent = Directory.systemTemp.createTempSync('spring_cache_audit_');
    addTearDown(() => parent.deleteSync(recursive: true));
    final folder = '${parent.path}/cache';
    final disk = DirectoryCacheStore(folder);
    await disk.write('spring/caches/a/1.json', [1]);
    if (!Platform.isWindows) {
      expect(Directory(folder).statSync().mode & 0x1FF, 0x1C0);
    }
    final link = Link('${parent.path}/linked')..createSync(folder);
    expect(link.existsSync(), isTrue);
    await expectLater(
      DirectoryCacheStore(link.path).write('x.json', [1]),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      await DirectoryCacheStore(link.path).read('spring/caches/a/1.json'),
      isNull,
    );
  });

  test(
    'disk without a store where there are no folders fails at once (CD-6)',
    () {
      expect(
        () => browser.DirectoryCacheStore('.spring/cache'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'spring.main.startup-checks.enabled=false at run time leaves the check '
    'out (GEN-4)',
    () {
      final context =
          SpringApplication(
            [],
            autoConfigurations: [
              springBootAutoConfiguration,
              springBootStarterCacheAutoConfiguration,
              springBootStarterCacheStartupChecksAutoConfiguration,
            ],
          ).run(
            ['--spring.main.startup-checks.enabled=false'],
            properties: {
              'spring.main.banner-mode': 'off',
              'logging.level.root': 'warn',
            },
          );
      addTearDown(context.close);
      expect(context.containsBean('cacheOperationValidator'), isFalse);
      expect(context.containsBean('cacheInterceptor'), isTrue);
    },
  );
  test(
    'an invalid annotation fails a Future method through its Future, '
    'without the start-up check (CD-4)',
    () async {
      final bad = _badFactory.createProxy(_Bad(), [
        DefaultPointcutAdvisor(
          const CacheAnnotationPointcut(),
          CacheInterceptor(cacheManager: InMemoryCacheManager()),
        ),
      ]) as _Bad;
      late Future<String> call;
      expect(() => call = bad.both('x'), returnsNormally);
      await expectLater(call, throwsStateError);
    },
  );

  test(
    'a null goes past a layer that keeps no null, to the others (CD-9)',
    () async {
      final disk = manager();
      final layered = LayeredCacheManager([
        InMemoryCacheManager(allowNullValues: false),
        disk,
      ]);
      final c = layered.getCache('n')! as LayeredCache..put('k', null);
      await cache(disk, 'n').flush();
      expect(await cache(manager(), 'n').retrieve('k'), isNotNull);
      final again =
          LayeredCacheManager([
                InMemoryCacheManager(allowNullValues: false),
                manager(),
              ]).getCache('n')!
              as LayeredCache;
      final hit = await again.retrieve('k');
      expect(hit, isNotNull);
      expect(hit!.value, isNull);
      expect(c.layers.first.get('k'), isNull);
    },
  );
}

enum _Tint { red }

enum _Mood { red }
