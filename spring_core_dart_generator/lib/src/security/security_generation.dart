// spring_security_core's part of the module build: what the expressions of
// its method annotations reach, so the build describes those classes for
// the expressions.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// The method annotations, matched by URL (the generator does not depend on
// the security starter).
const _annotations = 'package:spring_security_core/src/method/annotations.dart';
const _preAuthorize = TypeChecker.fromUrl('$_annotations#PreAuthorize');
const _postAuthorize = TypeChecker.fromUrl('$_annotations#PostAuthorize');
const _preFilter = TypeChecker.fromUrl('$_annotations#PreFilter');
const _postFilter = TypeChecker.fromUrl('$_annotations#PostFilter');
const _secured = TypeChecker.fromUrl('$_annotations#Secured');
const _webArguments =
    'package:spring_boot_starter_security/src/web/arguments.dart';

const List<TypeChecker> _expressions = [
  _preAuthorize,
  _postAuthorize,
  _preFilter,
  _postFilter,
];

// `this` of the expression root, the bean; not the variable `#this`.
final RegExp _readsBean = RegExp(r'(?<!#)\bthis\b');

/// The part of `spring_security_core` in the module build: where the
/// expressions of `@PreAuthorize`, `@PostAuthorize`, `@PreFilter` and
/// `@PostFilter` look (the arguments by `#name`, the result by
/// `returnObject` or `filterObject`, the bean by `this`), so the classes
/// they reach can have their methods called; `@Secured` names roles only.
/// It writes nothing of its own.
///
/// ```dart
/// @PreAuthorize('#order.owner == authentication.name')
/// Future<void> cancel(Order order) => ...
/// // Order: described so the expression reads `owner`.
/// ```
final class SecurityGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const SecurityGeneration();

  @override
  String get package => 'spring_security_core';

  // The method security annotations are advice: where the proxy cannot
  // run them, the method would run unchecked, for anyone. The web
  // arguments of the security starter (by URL: it has no part) are read on
  // handler parameters only.
  @override
  List<AnnotationPlacement> get placements => const [
    AdvicePlacement([
      _preAuthorize,
      _postAuthorize,
      _preFilter,
      _postFilter,
      _secured,
    ], effect: 'the method would run unchecked, for anyone'),
    ParameterPlacement(
      [
        TypeChecker.fromUrl('$_webArguments#AuthenticationPrincipal'),
        TypeChecker.fromUrl('$_webArguments#CurrentSecurityContext'),
      ],
      methodNoun: 'a handler method (@GetMapping, @PostMapping...)',
    ),
  ];

  @override
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) {
    if (_secured.isAssignableFromType(annotation)) {
      // Nothing of its types is read or written by the framework.
      return (
        result: IntrospectionNeed.none,
        parameters: [
          for (final _ in method.formalParameters) IntrospectionNeed.none,
        ],
      );
    }
    if (!_expressions.any(
      (checker) => checker.isAssignableFromType(annotation),
    )) {
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
  // (`@PostFilter`), the bean by `this` (`#this` is the expression's own
  // current object, the root).
  @override
  SpelUse? expressionUse(DartObject annotation, ModuleScan scan) {
    final type = annotation.type;
    if (type == null ||
        !_expressions.any((checker) => checker.isAssignableFromType(type))) {
      return null;
    }
    final text = ConstantReader(annotation).peek('value')?.stringValue;
    if (text == null || text.isEmpty) {
      return (arguments: false, result: false, target: false);
    }
    bool mentions(String word) => RegExp('\\b$word\\b').hasMatch(text);
    final before =
        _preAuthorize.isAssignableFromType(type) ||
        _preFilter.isAssignableFromType(type);
    return (
      arguments:
          text.contains('#') ||
          (_preFilter.isAssignableFromType(type) && mentions('filterObject')),
      result:
          !before &&
          (_postAuthorize.isAssignableFromType(type)
              ? mentions('returnObject')
              : mentions('filterObject')),
      target: _readsBean.hasMatch(text),
    );
  }
}
