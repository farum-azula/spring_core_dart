// spring_boot_starter_cache's part of the module build: what the keys and
// conditions of its annotations reach, and the check that a stream is not
// cached.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';

// The cache annotations, matched by URL (the generator does not depend on
// the cache starter).
const _annotations = 'package:spring_boot_starter_cache/src/annotations.dart';
const _cacheable = TypeChecker.fromUrl('$_annotations#Cacheable');
const _cachePut = TypeChecker.fromUrl('$_annotations#CachePut');
const _cacheEvict = TypeChecker.fromUrl('$_annotations#CacheEvict');
const _caching = TypeChecker.fromUrl('$_annotations#Caching');

/// The part of `spring_boot_starter_cache` in the module build:
///
/// - where the `key`, `condition` and `unless` expressions of
///   `@Cacheable`, `@CachePut` and `@CacheEvict` (and those `@Caching`
///   holds) look: the arguments by `#name` or `args`, the result by
///   `#result`, the bean by `target`; the build describes the classes they
///   reach so their methods can be called;
/// - `@Cacheable` or `@CachePut` on a method returning a `Stream` fails
///   the build: a stream can be listened to only once, so the cached one
///   would fail every later caller.
///
/// It writes nothing of its own.
///
/// ```dart
/// @Cacheable('books', key: '#isbn.value')
/// Future<Book> find(Isbn isbn) => ...
/// // Isbn: described so the key reads `value`.
/// ```
final class CacheGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const CacheGeneration();

  @override
  String get package => 'spring_boot_starter_cache';

  @override
  SpelUse? expressionUse(DartObject annotation, ModuleScan scan) {
    final type = annotation.type;
    if (type == null) {
      return null;
    }
    if (_caching.isExactlyType(type)) {
      return scan.spelUse([
        for (final field in const ['cacheable', 'put', 'evict'])
          ...?annotation.getField(field)?.toListValue(),
      ]);
    }
    if (!_cacheable.isExactlyType(type) &&
        !_cachePut.isExactlyType(type) &&
        !_cacheEvict.isExactlyType(type)) {
      return null;
    }
    var arguments = false;
    var result = false;
    var target = false;
    for (final field in const ['key', 'condition', 'unless']) {
      final text = annotation.getField(field)?.toStringValue();
      if (text == null || text.isEmpty) {
        continue;
      }
      bool mentions(String word) => RegExp('\\b$word\\b').hasMatch(text);
      arguments |= text.contains('#') || mentions('args');
      result |= text.contains('#result');
      target |= mentions('target');
    }
    return (arguments: arguments, result: result, target: target);
  }

  @override
  void checkProxy(ProxyModel proxy) {
    for (final member in proxy.members) {
      if (member.kind != ProxyMemberKind.method ||
          !member.returnType.isDartAsyncStream) {
        continue;
      }
      for (final annotation in member.mergedAnnotations) {
        final type = annotation.type;
        if (type is! InterfaceType) {
          continue;
        }
        final caches =
            _cacheable.isExactlyType(type) ||
            _cachePut.isExactlyType(type) ||
            (_caching.isExactlyType(type) &&
                ['cacheable', 'put'].any(
                  (field) =>
                      annotation.getField(field)?.toListValue()?.isNotEmpty ??
                      false,
                ));
        if (caches) {
          final target = proxy.targetType;
          final element =
              target.lookUpMethod(member.name, target.element.library) ??
              target.element;
          throw InvalidGenerationSource(
            '@${type.element.name} on ${target.element.name}.${member.name} '
            'cannot cache a Stream: a stream can be listened to only once. '
            'Return a Future<List<T>> instead.',
            element: element.baseElement,
          );
        }
      }
    }
  }
}
