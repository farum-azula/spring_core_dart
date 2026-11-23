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

const _controllers = 'package:spring_web_dart/src/controller_annotations.dart';
const _requestMappings = [
  TypeChecker.fromUrl('$_annotations#RequestMapping'),
  TypeChecker.fromUrl('$_annotations#GetMapping'),
  TypeChecker.fromUrl('$_annotations#PostMapping'),
  TypeChecker.fromUrl('$_annotations#PutMapping'),
  TypeChecker.fromUrl('$_annotations#PatchMapping'),
  TypeChecker.fromUrl('$_annotations#DeleteMapping'),
];
const _crossOrigin = TypeChecker.fromUrl('$_controllers#CrossOrigin');
const _responseStatus = TypeChecker.fromUrl('$_controllers#ResponseStatus');
const _controllerAdvice = TypeChecker.fromUrl('$_controllers#ControllerAdvice');
// The web starter has no part of its own: its rate limits are read on the
// controllers' handlers, so they are placed here, by URL.
const _rateLimiter = TypeChecker.fromUrl(
  'package:spring_boot_starter_web/src/ratelimit/rate_limiter.dart#RateLimiter',
);
const _controller = TypeChecker.typeNamedLiterally(
  'Controller',
  inPackage: 'spring_core_dart',
);
const _handlerParameters = [
  TypeChecker.fromUrl('$_annotations#PathVariable'),
  TypeChecker.fromUrl('$_annotations#RequestParam'),
  TypeChecker.fromUrl('$_annotations#RequestHeader'),
  TypeChecker.fromUrl('$_annotations#CookieValue'),
  _requestBody,
  _requestPart,
];

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

  // Spring 6 ignores a mapping on a class that is no @Controller, and a
  // request value off a handler; both answer 404 or a missing value at
  // run time, so the build names them.
  @override
  List<AnnotationPlacement> get placements => const [
    _HandlerPlacement(
      _requestMappings,
      does: 'the route is registered',
      methodOwner: AnnotatedOwner([_controller]),
      ownerNoun: '@RestController (or @Controller)',
      ownerFix: '@RestController()',
    ),
    // What a server does with a route: an HTTP client's interface only
    // sends requests, and a base counts through a controller extending it.
    _HandlerPlacement(
      [_crossOrigin, _rateLimiter],
      does: 'the route is registered',
      methodOwner: AnnotatedOwner([_controller]),
      ownerNoun: '@RestController (or @Controller)',
      ownerFix: '@RestController()',
      serverOnly: true,
    ),
    _HandlerPlacement(
      [_exceptionHandler],
      does: 'the exceptions of the requests are handled',
      methodOwner: AnnotatedOwner([_controller, _controllerAdvice]),
      ownerNoun: '@RestController or @RestControllerAdvice',
      ownerFix: '@RestControllerAdvice()',
      onClass: false,
    ),
    _ResponseStatusPlacement(),
    ParameterPlacement(
      _handlerParameters,
      methodNoun:
          'a method the framework calls with a request (@GetMapping, '
          '@PostMapping..., or a method of an HTTP client)',
    ),
  ];

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

// A handler annotation: a method of a controller (or of an HTTP client's
// interface), or, for a mapping, a cross-origin rule or a rate limit, the
// controller class for all of its methods.
final class _HandlerPlacement extends MethodPlacement {
  const _HandlerPlacement(
    super.checkers, {
    required super.does,
    required super.methodOwner,
    required super.ownerNoun,
    required super.ownerFix,
    this.onClass = true,
    this.serverOnly = false,
  });

  final bool onClass;

  // Whether it means nothing on an interface whose client the build writes.
  final bool serverOnly;

  @override
  bool get checksBases => serverOnly;

  @override
  String? generatedBeanProblem(AnnotationSite site) => serverOnly
      ? '${site.name} on ${site.subject}: it applies to the routes of a '
            'server, and the build writes this interface as a client, so it '
            'would do nothing. Put it on a @RestController.'
      : null;

  @override
  String? problem(AnnotationSite site) =>
      onClass && site.kind == PlaceKind.classDeclaration
      ? null
      : super.problem(site);
}

// `@ResponseStatus`: a handler method, or a controller class for all of its
// handlers. On an exception class Spring maps the exception to the
// status; here it is not, so the build says what to write instead.
final class _ResponseStatusPlacement extends CheckedPlacement {
  const _ResponseStatusPlacement() : super(const [_responseStatus]);

  @override
  String? generatedBeanProblem(AnnotationSite site) =>
      '@ResponseStatus on ${site.subject}: it sets the status a server '
      'answers with, and the build writes this interface as a client, so it '
      'would do nothing. Remove it.';

  @override
  String? problem(AnnotationSite site) {
    final subject = site.subject;
    switch (site.kind) {
      case PlaceKind.classDeclaration
          when site.has(const [_controller, _controllerAdvice]):
        return null;
      case PlaceKind.classDeclaration:
        return '@ResponseStatus on $subject: only a controller class (for '
            'its handlers) or a handler method carries it here; an '
            'exception class is not mapped to the status as in Spring. '
            'Throw ResponseStatusException(status) instead, or write an '
            '@ExceptionHandler that answers with the status.';
      case PlaceKind.method
          when site.has([..._requestMappings, _exceptionHandler]):
        return null;
      default:
        return '@ResponseStatus on $subject: it sets the status of a '
            'handler (a method with @GetMapping, @PostMapping... or '
            '@ExceptionHandler), or of a controller class; here it would '
            'do nothing.';
    }
  }
}
