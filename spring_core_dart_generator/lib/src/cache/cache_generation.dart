// spring_boot_starter_cache's part of the module build: what the keys and
// conditions of its annotations reach, and the check that a stream is not
// cached.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart/expression.dart' as spel;
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// The cache annotations, matched by URL (the generator does not depend on
// the cache starter).
const _annotations = 'package:spring_boot_starter_cache/src/annotations.dart';
const _cacheable = TypeChecker.fromUrl('$_annotations#Cacheable');
const _cachePut = TypeChecker.fromUrl('$_annotations#CachePut');
const _cacheEvict = TypeChecker.fromUrl('$_annotations#CacheEvict');
const _caching = TypeChecker.fromUrl('$_annotations#Caching');
const _cacheConfig = TypeChecker.fromUrl('$_annotations#CacheConfig');
const List<TypeChecker> _cacheOperations = [
  _cacheable,
  _cachePut,
  _cacheEvict,
  _caching,
];

/// The part of `spring_boot_starter_cache` in the module build:
///
/// - where the `key`, `condition` and `unless` expressions of
///   `@Cacheable`, `@CachePut` and `@CacheEvict` (and those `@Caching`
///   holds) look: the arguments by `#name` or `args`, the result by
///   `#result`, the bean by `target`; the build describes the classes they
///   reach so their methods can be called;
/// - `@Cacheable` or `@CachePut` on a method returning a `Stream` fails
///   the build: a stream can be listened to only once, so the cached one
///   would fail every later caller;
/// - an expression that is no valid SpEL fails the build, as the interceptor
///   parses it with the same parser at the first call.
///
/// It writes nothing of its own.
///
/// ```dart
/// @Cacheable('books', key: '#isbn.value')
/// Future<Book> find(Isbn isbn) => ...
/// // Isbn: described so the key reads `value`.
/// ```
final class CacheGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const CacheGeneration();

  @override
  String get package => 'spring_boot_starter_cache';

  @override
  List<AnnotationPlacement> get placements => const [
    _CacheOperationPlacement(),
    _CacheConfigPlacement(),
  ];

  @override
  SpelUse? expressionUse(DartObject annotation, ModuleScan scan) {
    final type = annotation.type;
    if (type == null) {
      return null;
    }
    if (_caching.isAssignableFromType(type)) {
      return scan.spelUse(_heldBy(annotation));
    }
    if (!_cacheable.isAssignableFromType(type) &&
        !_cachePut.isAssignableFromType(type) &&
        !_cacheEvict.isAssignableFromType(type)) {
      return null;
    }
    var arguments = false;
    var result = false;
    var target = false;
    for (final field in _expressionFields) {
      final text = ConstantReader(annotation).peek(field)?.stringValue;
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
            _cacheable.isAssignableFromType(type) ||
            _cachePut.isAssignableFromType(type) ||
            (_caching.isAssignableFromType(type) &&
                ['cacheable', 'put'].any(
                  (field) =>
                      ConstantReader(
                        annotation,
                      ).peek(field)?.listValue.isNotEmpty ??
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

const _expressionFields = ['key', 'condition', 'unless'];

// The annotations `@Caching` holds.
List<DartObject> _heldBy(DartObject caching) => [
  for (final field in const ['cacheable', 'put', 'evict'])
    ...?ConstantReader(caching).peek(field)?.listValue,
];

// The cache annotations are advice, and their expressions are parsed here
// with the parser the interceptor uses, so a syntax error stops the build
// instead of the first call (in every build mode: the text is a constant).
final class _CacheOperationPlacement extends AdvicePlacement {
  const _CacheOperationPlacement()
    : super(const [
        _cacheable,
        _cachePut,
        _cacheEvict,
        _caching,
      ], effect: 'nothing would be cached or evicted');

  @override
  String? problem(AnnotationSite site) =>
      super.problem(site) ??
      [
        site.annotation,
        ..._heldBy(site.annotation),
      ].expand((operation) => _syntaxProblems(site, operation)).firstOrNull;

  static Iterable<String> _syntaxProblems(
    AnnotationSite site,
    DartObject operation,
  ) sync* {
    final reader = ConstantReader(operation);
    for (final field in _expressionFields) {
      final text = reader.peek(field)?.stringValue;
      if (text == null) {
        continue;
      }
      try {
        spel.SpelExpressionParser().parseExpression(text);
      } on spel.ExpressionException catch (error) {
        yield '@${operation.type?.element?.name} on ${site.subject}: the '
            "$field expression '$text' is not valid SpEL: "
            '${error.simpleMessage} (at position ${error.position}).';
      }
    }
  }
}

// `@CacheConfig`: the defaults of the cache annotations of a bean class's
// methods; on a class without any, or elsewhere, it would do nothing.
final class _CacheConfigPlacement extends ClassPlacement {
  const _CacheConfigPlacement() : super(const [_cacheConfig]);

  @override
  String? problem(AnnotationSite site) {
    if (super.problem(site) case final problem?) {
      return problem;
    }
    final element = site.element;
    if (element is! InterfaceElement) {
      return null;
    }
    final members = [
      element,
      for (final type in element.allSupertypes) type.element,
    ].expand((type) => [...type.methods, ...type.getters, ...type.setters]);
    if (members.any(
      (member) => _cacheOperations.any((c) => c.hasAnnotationOf(member)),
    )) {
      return null;
    }
    return '@CacheConfig on ${site.subject}: it gives the defaults of the '
        '@Cacheable, @CachePut and @CacheEvict methods of the class, and '
        '${element.displayName} has none, so it would do nothing.';
  }

  @override
  PlacementOwner? owner(AnnotationSite site) => PlacementOwner.bean;
}
