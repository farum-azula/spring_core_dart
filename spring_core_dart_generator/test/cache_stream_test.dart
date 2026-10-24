// `@Cacheable` / `@CachePut` (spring_boot_starter_cache) on a member that
// returns a Stream fail the build: a stream can be listened to once.
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/bean_scanner.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

// The annotations of the starter, as far as the generator looks at them.
const _cacheAnnotations = '''
class Cacheable {
  const Cacheable(this.value);
  final String value;
}

class CachePut {
  const CachePut(this.value);
  final String value;
}

class CacheEvict {
  const CacheEvict(this.value);
  final String value;
}

class Caching {
  const Caching({
    this.cacheable = const [],
    this.put = const [],
    this.evict = const [],
  });
  final List<Cacheable> cacheable;
  final List<CachePut> put;
  final List<CacheEvict> evict;
}
''';

/// Builds [service] (a library of `pkg`) next to a fake
/// `spring_boot_starter_cache` package.
Future<TestBuilderResult> _build(String service) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    for (final package in isolateConfig.packages)
      if (package.name != 'spring_boot_starter_cache') package,
    Package(
      'spring_boot_starter_cache',
      Uri.parse('file:///spring_boot_starter_cache/'),
      packageUriRoot: Uri.parse('file:///spring_boot_starter_cache/lib/'),
    ),
  ]);
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(proxyMode: ProxyMode.all),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/service.dart':
          '''
import 'dart:async';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_starter_cache/src/annotations.dart';

$service
''',
      'spring_boot_starter_cache|lib/src/annotations.dart': _cacheAnnotations,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
  );
}

void main() {
  test('@Cacheable on a Stream fails the build', () async {
    final result = await _build('''
@Component()
class Events {
  @Cacheable('events')
  Stream<String> events() => Stream.value('a');
}
''');
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains(
        '@Cacheable on Events.events cannot cache a Stream: a stream can be '
        'listened to only once. Return a Future<List<T>> instead.',
      ),
    );
  });

  test('@CachePut and @Caching(cacheable:) on a Stream, also behind an '
      'interface', () async {
    final put = await _build('''
abstract interface class Feed {
  Stream<int> numbers();
}

@Component()
class NumberFeed implements Feed {
  @override
  @CachePut('numbers')
  Stream<int> numbers() => Stream.value(1);
}
''');
    expect(put.succeeded, isFalse);
    expect(put.errors.join('\n'), contains('@CachePut on NumberFeed.numbers'));

    final caching = await _build('''
@Component()
class Events {
  @Caching(cacheable: [Cacheable('events')])
  Stream<String> events() => Stream.value('a');
}
''');
    expect(caching.succeeded, isFalse);
    expect(caching.errors.join('\n'), contains('@Caching on Events.events'));
  });

  test('evicting around a Stream and caching a Future<List> build', () async {
    final result = await _build('''
@Component()
class Events {
  @CacheEvict('events')
  Stream<String> events() => Stream.value('a');

  @Caching(evict: [CacheEvict('events')])
  Stream<String> more() => Stream.value('b');

  @Cacheable('lists')
  Future<List<String>> all() async => ['a'];
}
''');
    expect(result.errors, isEmpty);
    expect(result.succeeded, isTrue);
  });
}
