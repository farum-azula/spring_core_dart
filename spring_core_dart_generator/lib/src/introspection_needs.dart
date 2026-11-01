part of 'bean_scanner.dart';

// What the application does with the classes of its methods, as far as the
// build can see: the generator describes a class only for those uses (see
// `IntrospectionNeed`). The starters' annotations are matched by URL, so the
// generator does not depend on them.
//
// ```dart
// @GetMapping('/books')
// Future<Page<BookDto>> books(@RequestBody SearchForm form) => ...
// // BookDto and Page: written out (getters) and read back (constructor
// // and setters, for a test that reads the answer); SearchForm: read in
// // (constructor and setters).
// ```
//
// A method with an annotation of a user's `@BeanMethodAnnotation()` is
// something the build knows nothing of: its types are described entirely.

const _webAnnotations = 'package:spring_web_dart/src/annotations.dart';
const _mapping = TypeChecker.fromUrl('$_webAnnotations#Mapping');
const _requestBody = TypeChecker.fromUrl('$_webAnnotations#RequestBody');
const _requestPart = TypeChecker.fromUrl('$_webAnnotations#RequestPart');
const _exceptionHandler = TypeChecker.fromUrl(
  'package:spring_web_dart/src/controller_annotations.dart#ExceptionHandler',
);

const _webSocketAnnotations =
    'package:spring_boot_starter_websocket/src/server/web_socket_endpoint.dart';
// The server's message handler: the message is read in, the reply written.
const _onMessage = TypeChecker.fromUrl(
  'package:spring_boot_starter_websocket/src/web_socket_client.dart#OnMessage',
);
// Handlers that get the connection, the status or the error: none of their
// types is read from or written to JSON.
final List<TypeChecker> _webSocketEvents = [
  for (final name in const ['OnOpen', 'OnClose', 'OnError'])
    TypeChecker.fromUrl('$_webSocketAnnotations#$name'),
];

const _scheduled = TypeChecker.fromUrl(
  'package:spring_boot_starter_scheduling/src/scheduled.dart#Scheduled',
);

const _securityAnnotations =
    'package:spring_security_core/src/method/annotations.dart';
const _preAuthorize = TypeChecker.fromUrl('$_securityAnnotations#PreAuthorize');
const _postAuthorize = TypeChecker.fromUrl(
  '$_securityAnnotations#PostAuthorize',
);
const _preFilter = TypeChecker.fromUrl('$_securityAnnotations#PreFilter');
const _postFilter = TypeChecker.fromUrl('$_securityAnnotations#PostFilter');
const _secured = TypeChecker.fromUrl('$_securityAnnotations#Secured');

const _cacheEvict = TypeChecker.fromUrl('$_cacheAnnotations#CacheEvict');

final TypeChecker _validated = _spring('Validated');

/// What the types of one annotated method need: the return type (a
/// `Future`'s value, the elements of a `Stream`, ...) and each parameter,
/// in declaration order.
typedef AnnotatedMethodNeeds = ({
  IntrospectionNeed result,
  List<IntrospectionNeed> parameters,
});

/// Where an expression of a method's annotations looks: at the arguments,
/// at the result, at the bean the method is called on.
typedef SpelUse = ({bool arguments, bool result, bool target});

extension _IntrospectionNeeds on BeanScanner {
  // What each annotation of the method [method] (the `@BeanMethodAnnotation`
  // ones, [marked]) does with its parameters and its result; the union over
  // the annotations.
  AnnotatedMethodNeeds _annotatedMethodNeeds(
    MethodElement method,
    List<InterfaceType> marked,
  ) {
    final parameters = method.formalParameters;
    var result = IntrospectionNeed.none;
    final need = List.filled(parameters.length, IntrospectionNeed.none);
    void all() {
      result |= IntrospectionNeed.all;
      for (var i = 0; i < need.length; i++) {
        need[i] |= IntrospectionNeed.all;
      }
    }

    for (final type in marked) {
      if (_mapping.isAssignableFromType(type) ||
          _exceptionHandler.isExactlyType(type)) {
        // The answer is written out, and a test reads it back
        // (`mapper.readValue<BookDto>(res.body)`, and test/ is not
        // scanned): both. A body or a part is read in (and checked, with
        // `@Valid()`).
        result |= IntrospectionNeed.read | IntrospectionNeed.write;
        for (final (i, parameter) in parameters.indexed) {
          if (_requestBody.hasAnnotationOf(parameter) ||
              _requestPart.hasAnnotationOf(parameter)) {
            need[i] |= IntrospectionNeed.write;
            if (_valid.hasAnnotationOf(parameter) ||
                _validated.hasAnnotationOf(parameter)) {
              need[i] |= IntrospectionNeed.validate;
            }
          }
        }
      } else if (_onMessage.isExactlyType(type)) {
        // A message handler of an endpoint: the message (a parameter that
        // is no path variable or session; of other packages' types nothing
        // is described) is read in, the reply written out.
        result |= IntrospectionNeed.read;
        for (var i = 0; i < need.length; i++) {
          need[i] |= IntrospectionNeed.write;
        }
      } else if (_webSocketEvents.any((c) => c.isExactlyType(type)) ||
          _scheduled.isExactlyType(type) ||
          _secured.isExactlyType(type)) {
        // Nothing of their types is read or written by the framework.
        continue;
      } else if (_preAuthorize.isExactlyType(type) ||
          _postAuthorize.isExactlyType(type) ||
          _preFilter.isExactlyType(type) ||
          _postFilter.isExactlyType(type)) {
        final spel = _spelUse([
          for (final annotation in method.metadata.annotations)
            ?annotation.computeConstantValue(),
        ]);
        if (spel.arguments) {
          for (var i = 0; i < need.length; i++) {
            need[i] |= IntrospectionNeed.spel;
          }
        }
        if (spel.result) {
          result |= IntrospectionNeed.spel;
        }
      } else {
        // An annotation the build does not know: whatever its framework
        // does with the values, it can.
        all();
      }
    }
    return (result: result, parameters: need);
  }

  // The expressions in [annotations] (of one method): cache keys and
  // conditions, security expressions. Which values they may reach:
  //
  // - `#name`, `#p0`, `#a0`, `args`: the arguments;
  // - `#result` (cache), `returnObject` and `filterObject` (security): the
  //   result;
  // - `target`: the bean.
  SpelUse _spelUse(Iterable<DartObject> annotations) {
    var arguments = false;
    var result = false;
    var target = false;

    String? textOf(DartObject annotation, String field) {
      final text = annotation.getField(field)?.toStringValue();
      return text == null || text.isEmpty ? null : text;
    }

    bool mentions(String text, String word) =>
        RegExp('\\b$word\\b').hasMatch(text);

    void visit(DartObject annotation) {
      final type = annotation.type;
      if (type == null) {
        return;
      }
      if (_cacheable.isExactlyType(type) ||
          _cachePut.isExactlyType(type) ||
          _cacheEvict.isExactlyType(type)) {
        for (final field in const ['key', 'condition', 'unless']) {
          final text = textOf(annotation, field);
          if (text == null) {
            continue;
          }
          arguments |= text.contains('#') || mentions(text, 'args');
          result |= text.contains('#result');
          target |= mentions(text, 'target');
        }
      } else if (_caching.isExactlyType(type)) {
        for (final field in const ['cacheable', 'put', 'evict']) {
          annotation.getField(field)?.toListValue()?.forEach(visit);
        }
      } else if (_preAuthorize.isExactlyType(type) ||
          _postAuthorize.isExactlyType(type) ||
          _preFilter.isExactlyType(type) ||
          _postFilter.isExactlyType(type)) {
        final text = textOf(annotation, 'value');
        if (text == null) {
          return;
        }
        final before =
            _preAuthorize.isExactlyType(type) || _preFilter.isExactlyType(type);
        arguments |=
            text.contains('#') ||
            (_preFilter.isExactlyType(type) && mentions(text, 'filterObject'));
        result |=
            !before &&
            (_postAuthorize.isExactlyType(type)
                ? mentions(text, 'returnObject')
                : mentions(text, 'filterObject'));
        target |= mentions(text, 'target');
      }
    }

    annotations.forEach(visit);
    return (arguments: arguments, result: result, target: target);
  }

  // The classes an expression on a method of [model]'s bean reaches (cache
  // keys, security conditions) are read, and their methods called: the
  // arguments, the result when the expression looks at it, and the bean.
  void _introspectSpelTypes(ProxyModel? model) {
    if (model == null || model.targetType.element is! ClassElement) {
      return;
    }
    final owner = model.targetType.element as ClassElement;
    for (final member in model.members) {
      if (member.kind != ProxyMemberKind.method) {
        continue;
      }
      final use = _spelUse(member.mergedAnnotations);
      if (use.arguments) {
        for (final parameter in member.parameters) {
          _introspectUsed(parameter.type, owner, need: IntrospectionNeed.spel);
        }
      }
      if (use.result) {
        _introspectUsed(
          _valueTypeOf(member.returnType),
          owner,
          need: IntrospectionNeed.spel,
        );
      }
      if (use.target) {
        _scanIntrospected(owner, IntrospectionNeed.spel, automatic: true);
      }
    }
  }

  // The type of the value of a `Future`, else the type itself.
  static DartType _valueTypeOf(DartType type) =>
      type is InterfaceType &&
          type.isDartAsyncFuture &&
          type.typeArguments.length == 1
      ? type.typeArguments.single
      : type;
}
