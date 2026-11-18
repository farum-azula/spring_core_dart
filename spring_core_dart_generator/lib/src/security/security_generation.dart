// spring_security_core's part of the module build: what the expressions of
// its method annotations reach, so the build describes those classes for
// the expressions.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/bean_model.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';

// The method annotations, matched by URL (the generator does not depend on
// the security starter).
const _annotations = 'package:spring_security_core/src/method/annotations.dart';
const _preAuthorize = TypeChecker.fromUrl('$_annotations#PreAuthorize');
const _postAuthorize = TypeChecker.fromUrl('$_annotations#PostAuthorize');
const _preFilter = TypeChecker.fromUrl('$_annotations#PreFilter');
const _postFilter = TypeChecker.fromUrl('$_annotations#PostFilter');
const _secured = TypeChecker.fromUrl('$_annotations#Secured');

const List<TypeChecker> _expressions = [
  _preAuthorize,
  _postAuthorize,
  _preFilter,
  _postFilter,
];

/// The part of `spring_security_core` in the module build: where the
/// expressions of `@PreAuthorize`, `@PostAuthorize`, `@PreFilter` and
/// `@PostFilter` look (the arguments by `#name`, the result by
/// `returnObject` or `filterObject`, the bean by `target`), so the classes
/// they reach can have their methods called; `@Secured` names roles only.
/// It writes nothing of its own.
///
/// ```dart
/// @PreAuthorize('#order.owner == authentication.name')
/// Future<void> cancel(Order order) => ...
/// // Order: described so the expression reads `owner`.
/// ```
final class SecurityGeneration extends StarterGeneration {
  /// The part; it keeps no state of a build.
  const SecurityGeneration();

  @override
  String get package => 'spring_security_core';

  @override
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) {
    if (_secured.isExactlyType(annotation)) {
      // Nothing of its types is read or written by the framework.
      return (
        result: IntrospectionNeed.none,
        parameters: [
          for (final _ in method.formalParameters) IntrospectionNeed.none,
        ],
      );
    }
    if (!_expressions.any((checker) => checker.isExactlyType(annotation))) {
      return null;
    }
    final spel = scan.spelUse([
      for (final other in method.metadata.annotations)
        ?other.computeConstantValue(),
    ]);
    final arguments = spel.arguments
        ? IntrospectionNeed.spel
        : IntrospectionNeed.none;
    return (
      result: spel.result ? IntrospectionNeed.spel : IntrospectionNeed.none,
      parameters: [for (final _ in method.formalParameters) arguments],
    );
  }

  // The arguments by `#name` (and `filterObject` before a `@PreFilter`),
  // the result by `returnObject` (`@PostAuthorize`) or `filterObject`
  // (`@PostFilter`), the bean by `target`.
  @override
  SpelUse? expressionUse(DartObject annotation, ModuleScan scan) {
    final type = annotation.type;
    if (type == null ||
        !_expressions.any((checker) => checker.isExactlyType(type))) {
      return null;
    }
    final text = annotation.getField('value')?.toStringValue();
    if (text == null || text.isEmpty) {
      return (arguments: false, result: false, target: false);
    }
    bool mentions(String word) => RegExp('\\b$word\\b').hasMatch(text);
    final before =
        _preAuthorize.isExactlyType(type) || _preFilter.isExactlyType(type);
    return (
      arguments:
          text.contains('#') ||
          (_preFilter.isExactlyType(type) && mentions('filterObject')),
      result:
          !before &&
          (_postAuthorize.isExactlyType(type)
              ? mentions('returnObject')
              : mentions('filterObject')),
      target: mentions('target'),
    );
  }
}
