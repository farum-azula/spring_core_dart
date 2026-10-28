import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/annotations.dart';

/// One cache annotation of a method, as the framework applies it: the
/// settings of the annotation with the class's `@CacheConfig` defaults
/// filled in.
///
/// The framework reads the annotations once per method and turns each into
/// an operation ([CacheableOperation], [CachePutOperation],
/// [CacheEvictOperation]). Applications meet it only in a `CacheResolver`,
/// which reads `context.operation` to decide which caches to use.
///
/// ```dart
/// // The resolver derives tenant caches from the names the operation has.
/// final class TenantCacheResolver implements CacheResolver {
///   @override
///   Iterable<Cache> resolveCaches(CacheOperationInvocationContext context) =>
///       [
///         for (final name in context.operation.cacheNames)
///           manager.cache('$tenant.$name'),
///       ];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// Collection<String> names = context.getOperation().getCacheNames();
/// ```
sealed class CacheOperation {
  CacheOperation._({
    required this.name,
    required List<String> cacheNames,
    this.key,
    this.keyGenerator,
    this.cacheManager,
    this.cacheResolver,
    this.condition,
  }) : cacheNames = List.unmodifiable(cacheNames);

  /// The annotated method, written `Class.member` (`Books.find`).
  final String name;

  /// The cache names of the annotation, or of `@CacheConfig` when it named
  /// none; may be empty when a `CacheResolver` picks the caches.
  final List<String> cacheNames;

  /// The SpEL expression computing the key; `null` when the key generator
  /// computes it.
  final String? key;

  /// Name of the `KeyGenerator` bean; `null` for the default one.
  final String? keyGenerator;

  /// Name of the `CacheManager` bean; `null` for the default one.
  final String? cacheManager;

  /// Name of the `CacheResolver` bean; `null` for the default one.
  final String? cacheResolver;

  /// SpEL deciding whether the operation applies to a call; `null` means
  /// always.
  final String? condition;

  /// The annotation's name without `@`: `Cacheable`, `CachePut` or
  /// `CacheEvict`.
  String get annotation;

  /// The operation in words, such as `@Cacheable on Books.find`, as error
  /// messages name it.
  String get description => '@$annotation on $name';

  @override
  String toString() =>
      '$description caches=$cacheNames'
      '${key == null ? '' : " key='$key'"}'
      '${keyGenerator == null ? '' : " keyGenerator='$keyGenerator'"}'
      '${cacheManager == null ? '' : " cacheManager='$cacheManager'"}'
      '${cacheResolver == null ? '' : " cacheResolver='$cacheResolver'"}'
      '${condition == null ? '' : " condition='$condition'"}';
}

/// The operation of a `@Cacheable` annotation: look the key up, and on a
/// miss run the method and store the result.
///
/// Spring (Java): `CacheableOperation`.
final class CacheableOperation extends CacheOperation {
  /// The operation of the method [name] (`Class.member`); the framework
  /// builds it from the annotation.
  CacheableOperation({
    required super.name,
    required super.cacheNames,
    super.key,
    super.keyGenerator,
    super.cacheManager,
    super.cacheResolver,
    super.condition,
    this.unless,
    this.sync = false,
  }) : super._();

  /// SpEL with the result as `#result`: when it is `true`, the result is
  /// not stored.
  final String? unless;

  /// Whether calls of a `Future` method with the same key that overlap in
  /// time share one call of the method.
  final bool sync;

  @override
  String get annotation => 'Cacheable';
}

/// The operation of a `@CachePut` annotation: always run the method and
/// store the result.
///
/// Spring (Java): `CachePutOperation`.
final class CachePutOperation extends CacheOperation {
  /// The operation of the method [name] (`Class.member`).
  CachePutOperation({
    required super.name,
    required super.cacheNames,
    super.key,
    super.keyGenerator,
    super.cacheManager,
    super.cacheResolver,
    super.condition,
    this.unless,
  }) : super._();

  /// SpEL with the result as `#result`: when it is `true`, nothing is
  /// stored.
  final String? unless;

  @override
  String get annotation => 'CachePut';
}

/// The operation of a `@CacheEvict` annotation: remove one entry, or all
/// of them, before or after the method runs.
///
/// Spring (Java): `CacheEvictOperation`.
final class CacheEvictOperation extends CacheOperation {
  /// The operation of the method [name] (`Class.member`).
  CacheEvictOperation({
    required super.name,
    required super.cacheNames,
    super.key,
    super.keyGenerator,
    super.cacheManager,
    super.cacheResolver,
    super.condition,
    this.cacheWide = false,
    this.beforeInvocation = false,
  }) : super._();

  /// Whether every entry of the caches is removed instead of one key: the
  /// annotation's `allEntries` (Spring's `isCacheWide()`).
  final bool cacheWide;

  /// Whether the entries are removed before the method runs, so even a
  /// call that throws removes them. When `false`, they are removed after
  /// the method returned normally.
  final bool beforeInvocation;

  @override
  String get annotation => 'CacheEvict';
}

/// Turns the cache annotations of a method into [CacheOperation]s, and
/// rejects wrong ones.
///
/// The `CacheInterceptor` uses it to learn what to do around a call:
/// which annotations apply (the method's own, else the overridden
/// method's, else those on the class), with the class's `@CacheConfig`
/// defaults filled in. It fails with a `StateError` naming the method,
/// as Spring's `SpringCacheAnnotationParser` does, for:
///
/// - `key` together with `keyGenerator`, `cacheManager` together with
///   `cacheResolver`;
/// - `sync: true` with other operations, several caches or `unless`;
/// - `@Cacheable` / `@CachePut` on a method returning a `Stream` (a stream
///   can be listened to only once; return a `Future<List<T>>` instead).
///
/// The result is computed once per method. Applications do not use it;
/// it is useful in a test that checks how annotations are read.
///
/// ```dart
/// // A test checks the operations the annotations of `Books.find` give.
/// final operations = AnnotationCacheOperationSource()
///     .getCacheOperations(signature); // [CacheableOperation(...)]
/// ```
///
/// Spring (Java):
/// ```java
/// Collection<CacheOperation> operations = new AnnotationCacheOperationSource()
///     .getCacheOperations(method, targetClass);
/// ```
final class AnnotationCacheOperationSource {
  /// A source with an empty per-method memory.
  AnnotationCacheOperationSource();

  final _operations = Map<MethodSignature, List<CacheOperation>>.identity();

  /// Whether [annotation] is a `@Cacheable`, `@CachePut`, `@CacheEvict`
  /// or `@Caching`.
  static bool isCacheAnnotation(Object annotation) =>
      annotation is Cacheable ||
      annotation is CachePut ||
      annotation is CacheEvict ||
      annotation is Caching;

  /// The cache annotations that apply to the member [signature], looked
  /// for in this order, the first place that has any winning:
  ///
  /// 1. the member itself (and its interface declarations);
  /// 2. the superclass or mixin method it overrides
  ///    ([MethodSignature.mergedAnnotations], the nearest first);
  /// 3. the class that declares the method's body, then its superclasses
  ///    (an annotation type found on a nearer class hides the same type
  ///    further up). This step applies only to methods: not to getters,
  ///    setters, `toString`, `==`, `hashCode` or `noSuchMethod`.
  ///
  /// The order is Spring's `AbstractFallbackCacheOperationSource`.
  static List<Object> cacheAnnotationsOf(MethodSignature signature) {
    var own = signature.annotations.where(isCacheAnnotation).toList();
    if (own.isEmpty) {
      own = signature.mergedAnnotations.where(isCacheAnnotation).toList();
    }
    if (own.isNotEmpty ||
        signature.kind != MemberKind.method ||
        _objectMembers.contains(signature.name)) {
      return own;
    }
    // Spring finds them over the hierarchy and, when there is more than
    // one operation, keeps the local ones: those of the class and the
    // (@Inherited) ones of its superclasses whose type it does not have.
    final found = <Object>[];
    final types = <Type>{};
    for (final level in [
      signature.implementingTypeAnnotations ?? signature.targetAnnotations,
      ...signature.superclassAnnotations,
    ]) {
      final annotations = level.where(isCacheAnnotation).toList();
      found.addAll(annotations.where((a) => !types.contains(a.runtimeType)));
      types.addAll(annotations.map((a) => a.runtimeType));
    }
    return found;
  }

  static const _objectMembers = {'toString', 'noSuchMethod', '==', 'hashCode'};

  /// The operations of the cache annotations that apply to [signature]
  /// (see [cacheAnnotationsOf]), with the class's `@CacheConfig` defaults
  /// filled in; empty when there are none. Throws a `StateError` for a
  /// wrong combination. Computed once per member.
  List<CacheOperation> getCacheOperations(MethodSignature signature) =>
      _operations[signature] ??= _parse(signature);

  static List<CacheOperation> _parse(MethodSignature signature) {
    // Spring's DefaultCacheConfig(method.getDeclaringClass()): the nearest
    // @CacheConfig of the declaring class and its superclasses.
    final config = signature.implementingTypeHierarchyAnnotations
        .whereType<CacheConfig>();
    final defaults = config.isEmpty ? const CacheConfig() : config.first;
    final member = '${signature.declaringType}.${signature.name}';
    final operations = <CacheOperation>[];

    // Spring's DefaultCacheConfig.applyDefault: names when the operation
    // has none; the key generator when it has neither key nor key
    // generator; the resolver (else the manager) when it has neither.
    void add(
      String annotation,
      String? value,
      List<String> cacheNames, {
      required String? key,
      required String? keyGenerator,
      required String? cacheManager,
      required String? cacheResolver,
      required CacheOperation Function(
        List<String> names,
        String? keyGenerator,
        String? cacheManager,
        String? cacheResolver,
      )
      create,
    }) {
      final description = '@$annotation on $member';
      var names = [?value, ...cacheNames];
      if (names.isEmpty) {
        names = defaults.cacheNames;
      }
      var generator = keyGenerator;
      if (key == null && generator == null) {
        generator = defaults.keyGenerator;
      }
      var manager = cacheManager;
      var resolver = cacheResolver;
      if (manager == null && resolver == null) {
        if (defaults.cacheResolver != null) {
          resolver = defaults.cacheResolver;
        } else {
          manager = defaults.cacheManager;
        }
      }
      if (key != null && generator != null) {
        throw StateError(
          'Both key and keyGenerator are set for $description; they exclude '
          'each other: give a SpEL key or the name of a KeyGenerator bean',
        );
      }
      if (manager != null && resolver != null) {
        throw StateError(
          'Both cacheManager and cacheResolver are set for $description; '
          'they exclude each other: a cache resolver replaces the cache '
          'manager',
        );
      }
      operations.add(create(names, generator, manager, resolver));
    }

    void cacheable(Cacheable a) => add(
      'Cacheable',
      a.value,
      a.cacheNames,
      key: a.key,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
      cacheResolver: a.cacheResolver,
      create: (names, keyGenerator, cacheManager, cacheResolver) =>
          CacheableOperation(
            name: member,
            cacheNames: names,
            key: a.key,
            keyGenerator: keyGenerator,
            cacheManager: cacheManager,
            cacheResolver: cacheResolver,
            condition: a.condition,
            unless: a.unless,
            sync: a.sync,
          ),
    );
    void put(CachePut a) => add(
      'CachePut',
      a.value,
      a.cacheNames,
      key: a.key,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
      cacheResolver: a.cacheResolver,
      create: (names, keyGenerator, cacheManager, cacheResolver) =>
          CachePutOperation(
            name: member,
            cacheNames: names,
            key: a.key,
            keyGenerator: keyGenerator,
            cacheManager: cacheManager,
            cacheResolver: cacheResolver,
            condition: a.condition,
            unless: a.unless,
          ),
    );
    void evict(CacheEvict a) => add(
      'CacheEvict',
      a.value,
      a.cacheNames,
      key: a.key,
      keyGenerator: a.keyGenerator,
      cacheManager: a.cacheManager,
      cacheResolver: a.cacheResolver,
      create: (names, keyGenerator, cacheManager, cacheResolver) =>
          CacheEvictOperation(
            name: member,
            cacheNames: names,
            key: a.key,
            keyGenerator: keyGenerator,
            cacheManager: cacheManager,
            cacheResolver: cacheResolver,
            condition: a.condition,
            cacheWide: a.allEntries,
            beforeInvocation: a.beforeInvocation,
          ),
    );

    for (final annotation in cacheAnnotationsOf(signature)) {
      switch (annotation) {
        case final Cacheable a:
          cacheable(a);
        case final CachePut a:
          put(a);
        case final CacheEvict a:
          evict(a);
        case final Caching a:
          a.cacheable.forEach(cacheable);
          a.put.forEach(put);
          a.evict.forEach(evict);
      }
    }

    final returnType = signature.returnType;
    if (returnType == 'Stream' || returnType.startsWith('Stream<')) {
      for (final operation in operations) {
        if (operation is! CacheEvictOperation) {
          throw StateError(
            '${operation.description}: the member returns a Stream, which '
            'cannot be cached (a stream can be listened to only once); '
            'return a Future<List<T>> instead',
          );
        }
      }
    }

    for (final operation in operations) {
      if (operation is! CacheableOperation || !operation.sync) {
        continue;
      }
      if (operations.length > 1) {
        throw StateError(
          '${operation.description} with sync: true cannot be combined with '
          'other cache operations',
        );
      }
      if (operation.cacheNames.length > 1) {
        throw StateError(
          '${operation.description} with sync: true allows a single cache',
        );
      }
      if (operation.unless != null) {
        throw StateError(
          '${operation.description}: sync: true does not support unless',
        );
      }
    }
    return List.unmodifiable(operations);
  }
}
