import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_cache/src/annotations.dart';

/// One cache annotation of a member, with the defaults of the class's
/// `@CacheConfig` applied, like Spring's `CacheOperation`: what a
/// `CacheResolver` sees as `CacheOperationInvocationContext.operation`.
///
/// ```dart
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

  /// The annotated member, `Class.member`.
  final String name;

  /// The caches to use (may be empty when a `CacheResolver` picks them).
  final List<String> cacheNames;

  /// SpEL computing the key; `null` for the key generator.
  final String? key;

  /// Name of the `KeyGenerator` bean; `null` for the default one.
  final String? keyGenerator;

  /// Name of the `CacheManager` bean; `null` for the default one.
  final String? cacheManager;

  /// Name of the `CacheResolver` bean; `null` for the default one.
  final String? cacheResolver;

  /// SpEL; the operation applies only when it is `true`.
  final String? condition;

  /// The annotation's name (`Cacheable`, `CachePut`, `CacheEvict`).
  String get annotation;

  /// `@Cacheable on Books.find`, for error messages.
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

/// A `@Cacheable` operation, like Spring's `CacheableOperation`.
final class CacheableOperation extends CacheOperation {
  /// An operation of the member [name] (`Class.member`).
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

  /// SpEL with `#result`; the result is not stored when it is `true`.
  final String? unless;

  /// Whether concurrent calls with the same key share one call.
  final bool sync;

  @override
  String get annotation => 'Cacheable';
}

/// A `@CachePut` operation, like Spring's `CachePutOperation`.
final class CachePutOperation extends CacheOperation {
  /// An operation of the member [name] (`Class.member`).
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

  /// SpEL with `#result`; nothing is stored when it is `true`.
  final String? unless;

  @override
  String get annotation => 'CachePut';
}

/// A `@CacheEvict` operation, like Spring's `CacheEvictOperation`.
final class CacheEvictOperation extends CacheOperation {
  /// An operation of the member [name] (`Class.member`).
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

  /// Clears the whole caches (the annotation's `allEntries`; Spring's
  /// `isCacheWide()`).
  final bool cacheWide;

  /// Evicts before the method runs (also when it throws).
  final bool beforeInvocation;

  @override
  String get annotation => 'CacheEvict';
}

/// Reads the cache annotations of members, like Spring's
/// `AnnotationCacheOperationSource`: applies the class's `@CacheConfig`
/// and rejects invalid combinations (with a `StateError` naming the
/// member), as Spring's `SpringCacheAnnotationParser` does:
///
/// - `key` together with `keyGenerator`, `cacheManager` together with
///   `cacheResolver`;
/// - `sync: true` with other operations, several caches or `unless`;
/// - `@Cacheable` / `@CachePut` on a member returning a `Stream` (a stream
///   can be listened to once; return a `Future<List<T>>` instead).
///
/// The result is computed once per member.
///
/// ```dart
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
  /// Creates the source.
  AnnotationCacheOperationSource();

  final _operations = Map<MethodSignature, List<CacheOperation>>.identity();

  /// Whether [annotation] is one of the cache annotations.
  static bool isCacheAnnotation(Object annotation) =>
      annotation is Cacheable ||
      annotation is CachePut ||
      annotation is CacheEvict ||
      annotation is Caching;

  /// The cache annotations that apply to the member [signature], like
  /// Spring's `AbstractFallbackCacheOperationSource`: its own (and those
  /// of its interface declarations), else those of the superclass or
  /// mixin method it overrides ([MethodSignature.mergedAnnotations], the
  /// nearest first), else those on the class that declares the method's
  /// body and its superclasses
  /// ([MethodSignature.implementingTypeHierarchyAnnotations], like Spring's
  /// fallback to `method.getDeclaringClass()` with find semantics):
  /// `@Cacheable` on the class applies to every public method, not to
  /// getters, setters or `Object`'s members.
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

  /// The operations of the cache annotations on the member [signature]
  /// (or on its class, see [cacheAnnotationsOf]; empty when there are
  /// none); throws a `StateError` for an invalid combination.
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
