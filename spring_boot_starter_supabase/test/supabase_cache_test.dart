@Tags(['supabase'])
library;

import 'dart:async';

import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:test/test.dart';

final class _Credentials implements SupabaseCredentials {
  SupabaseCaller who = const SupabaseCaller.anon();

  @override
  String get apiKey => 'k';

  @override
  Future<String> accessToken() async => 't';

  @override
  SupabaseCaller get caller => who;

  @override
  Future<T> asServiceRole<T>(FutureOr<T> Function() body) async => await body();
}

final class _Context implements CacheOperationInvocationContext {
  _Context(this.operation);

  @override
  final CacheOperation operation;

  @override
  Object get target => this;

  @override
  MethodSignature get method => const MethodSignature(
    name: 'find',
    declaringType: 'T',
    targetType: 'T',
  );

  @override
  List<Object?> get args => const [];
}

void main() {
  late _Credentials credentials;
  late SupabaseKeyGenerator generator;
  late InMemoryCacheManager manager;
  late SupabaseCacheResolver resolver;

  const target = Object();
  const method = MethodSignature(
    name: 'find',
    declaringType: 'T',
    targetType: 'T',
  );

  Cache cache(String name) => resolver
      .resolveCaches(
        _Context(CacheableOperation(name: 'T.find', cacheNames: [name])),
      )
      .single;

  setUp(() {
    credentials = _Credentials();
    generator = SupabaseKeyGenerator(credentials);
    manager = InMemoryCacheManager();
    resolver = SupabaseCacheResolver(
      cacheManager: manager,
      credentials: credentials,
      properties: SupabaseCacheProperties()..shared = ['catalog'],
    );
  });

  test('the generated key is who calls plus the arguments', () {
    final anon = generator.generate(target, method, [1, 'a']);
    credentials.who = const SupabaseCaller.user('u1');
    final user = generator.generate(target, method, [1, 'a']);
    final again = generator.generate(target, method, [1, 'a']);
    final other = generator.generate(target, method, [2, 'a']);
    credentials.who = const SupabaseCaller.service();
    final service = generator.generate(target, method, [1, 'a']);
    expect(user, again);
    expect(user.hashCode, again.hashCode);
    expect({anon, user, other, service}, hasLength(4));
  });

  test('one user never reads what was cached for another', () {
    // The caches are asked for at each call, as the interceptor does.
    Cache todos() => cache('todos');
    credentials.who = const SupabaseCaller.user('u1');
    todos().put(generator.generate(target, method, ['list']), 'rows of u1');
    credentials.who = const SupabaseCaller.user('u2');
    expect(todos().get(generator.generate(target, method, ['list'])), isNull);
    credentials.who = const SupabaseCaller.anon();
    expect(todos().get(generator.generate(target, method, ['list'])), isNull);
    credentials.who = const SupabaseCaller.user('u1');
    expect(
      todos().get(generator.generate(target, method, ['list']))?.value,
      'rows of u1',
    );
  });

  test('an answer read as the service role stays with it', () {
    credentials.who = const SupabaseCaller.service();
    cache(
      'todos',
    ).put(generator.generate(target, method, const []), 'every row');
    credentials.who = const SupabaseCaller.user('u1');
    expect(
      cache('todos').get(generator.generate(target, method, const [])),
      isNull,
    );
  });

  test('an explicit key (no generator) is kept apart per caller too', () {
    Cache todos() => cache('todos');
    credentials.who = const SupabaseCaller.user('u1');
    todos().put('list', 'rows of u1');
    expect(todos().putIfAbsent('list', 'x')?.value, 'rows of u1');
    credentials.who = const SupabaseCaller.user('u2');
    expect(todos().get('list'), isNull);
    todos()
      ..put('list', 'rows of u2')
      ..evict('list');
    expect(todos().get('list'), isNull);
    credentials.who = const SupabaseCaller.user('u1');
    expect(todos().get('list')?.value, 'rows of u1');
    expect(todos().evictIfPresent('list'), isTrue);
  });

  test('a call has one caller, from its lookup to what it stores: the '
      'answer of a call during which the login changed is not kept', () {
    // With an explicit key: looked up as u1, who is gone when the rows
    // are there; whose rows they are depends on when the token was read.
    credentials.who = const SupabaseCaller.user('u1');
    final call = cache('todos');
    expect(call.get('list'), isNull);
    credentials.who = const SupabaseCaller.user('u2');
    call.put('list', 'rows of one of them');
    expect(call.putIfAbsent('list', 'rows of one of them'), isNull);
    expect(cache('todos').get('list'), isNull);
    credentials.who = const SupabaseCaller.user('u1');
    expect(cache('todos').get('list'), isNull);

    // With a generated key, which names u1.
    final key = generator.generate(target, method, ['list']);
    final other = cache('todos');
    expect(other.get(key), isNull);
    credentials.who = const SupabaseCaller.anon();
    other.put(key, 'rows of one of them');
    expect(other.putIfAbsent(key, 'rows of one of them'), isNull);
    credentials.who = const SupabaseCaller.user('u1');
    expect(cache('todos').get(key), isNull);

    // The same caller all along: kept, and a later call of theirs
    // evicts it whoever is signed in when it resolved its caches.
    final kept = cache('todos')..put('list', 'rows of u1');
    expect(cache('todos').get('list')?.value, 'rows of u1');
    credentials.who = const SupabaseCaller.user('u2');
    kept.evict('list');
    credentials.who = const SupabaseCaller.user('u1');
    expect(cache('todos').get('list'), isNull);
  });

  test('a key is never scoped twice', () {
    credentials.who = const SupabaseCaller.user('u1');
    final key = generator.generate(target, method, ['list']);
    cache('todos').put(key, 'v');
    expect(manager.getCache('todos')!.get(key)?.value, 'v');
  });

  test('a shared cache has the same entries for everyone', () {
    final catalog = cache('catalog');
    credentials.who = const SupabaseCaller.user('u1');
    catalog
      ..put(generator.generate(target, method, ['page']), 'books')
      ..put('explicit', 'books');
    credentials.who = const SupabaseCaller.anon();
    expect(
      catalog.get(generator.generate(target, method, ['page']))?.value,
      'books',
    );
    expect(catalog.get('explicit')?.value, 'books');
    expect(manager.getCache('catalog')!.get('explicit')?.value, 'books');
  });

  test('clear empties the cache for everyone', () {
    credentials.who = const SupabaseCaller.user('u1');
    cache('todos').put('k', 'v');
    credentials.who = const SupabaseCaller.user('u2');
    cache('todos').clear();
    credentials.who = const SupabaseCaller.user('u1');
    expect(cache('todos').get('k'), isNull);
  });

  test('a cache that does not exist is an error naming it', () {
    final fixed = SupabaseCacheResolver(
      cacheManager: InMemoryCacheManager(cacheNames: const ['todos']),
      credentials: credentials,
      properties: SupabaseCacheProperties(),
    );
    expect(
      () => fixed.resolveCaches(
        _Context(CacheableOperation(name: 'T.find', cacheNames: ['nope'])),
      ),
      throwsStateError,
    );
  });

  test('the configurer gives both as the defaults', () {
    final configurer = SupabaseCachingConfigurer(
      generator: generator,
      resolver: resolver,
    );
    expect(configurer.keyGenerator(), same(generator));
    expect(configurer.cacheResolver(), same(resolver));
    expect(configurer.cacheManager(), isNull);
  });
}
