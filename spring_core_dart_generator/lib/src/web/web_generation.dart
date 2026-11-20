// spring_web_dart's part of the module build: what a controller's methods
// do with the classes of their bodies and answers, so the build describes
// those classes for that.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';

// The web annotations, matched by URL (the generator does not depend on
// the web starter).
const _annotations = 'package:spring_web_dart/src/annotations.dart';
const _mapping = TypeChecker.fromUrl('$_annotations#Mapping');
const _requestBody = TypeChecker.fromUrl('$_annotations#RequestBody');
const _requestPart = TypeChecker.fromUrl('$_annotations#RequestPart');
const _exceptionHandler = TypeChecker.fromUrl(
  'package:spring_web_dart/src/controller_annotations.dart#ExceptionHandler',
);

// The validation of a body, by spring_core_dart's annotations.
const _valid = TypeChecker.typeNamedLiterally(
  'Valid',
  inPackage: 'spring_core_dart',
);
const _validated = TypeChecker.typeNamedLiterally(
  'Validated',
  inPackage: 'spring_core_dart',
);

/// The part of `spring_web_dart` in the module build: what a request
/// mapping (`@GetMapping`, `@PostMapping`, ...) or an `@ExceptionHandler`
/// does with its values. It writes nothing of its own.
///
/// ```dart
/// @GetMapping('/books')
/// Future<Page<BookDto>> books(@RequestBody SearchForm form) => ...
/// // BookDto and Page: written out (getters) and read back (constructor
/// // and setters, for a test that reads the answer); SearchForm: read in
/// // (constructor and setters), and validated with @Valid().
/// ```
final class WebGeneration extends PackageGeneration {
  /// The part; it keeps no state of a build.
  const WebGeneration();

  @override
  String get package => 'spring_web_dart';

  // The answer is written out, and a test reads it back
  // (`mapper.readValue<BookDto>(res.body)`, and test/ is not scanned):
  // both. A body or a part is read in (and checked, with `@Valid()`).
  @override
  AnnotatedMethodNeeds? methodNeeds(
    InterfaceType annotation,
    MethodElement method,
    ModuleScan scan,
  ) {
    if (!_mapping.isAssignableFromType(annotation) &&
        !_exceptionHandler.isExactlyType(annotation)) {
      return null;
    }
    return (
      result: IntrospectionNeed.read | IntrospectionNeed.write,
      parameters: [
        for (final parameter in method.formalParameters) _bodyNeed(parameter),
      ],
    );
  }

  // What is done with [parameter]: a body or a part is read in, and
  // checked with `@Valid()`; any other is not read from JSON.
  static IntrospectionNeed _bodyNeed(FormalParameterElement parameter) {
    if (!_requestBody.hasAnnotationOf(parameter) &&
        !_requestPart.hasAnnotationOf(parameter)) {
      return IntrospectionNeed.none;
    }
    return _valid.hasAnnotationOf(parameter) ||
            _validated.hasAnnotationOf(parameter)
        ? IntrospectionNeed.write | IntrospectionNeed.validate
        : IntrospectionNeed.write;
  }
}
