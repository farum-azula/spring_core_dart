part of 'bean_scanner.dart';

// The classes the application's own calls of the `ObjectMapper` name. The
// build sees the static types of such a call, so it can describe a class
// for what the call does with it:
//
// ```dart
// final book = mapper.readValue<Book>(json);        // Book: read in
// final text = mapper.writeValueAsString(order);    // Order: written out
// final copy = mapper.convertValue<Dto>(entity);    // Dto: read in, the
//                                                   // entity's class: out
// ```
//
// So do the methods of the starters that write a value out as JSON through
// the mapper (the WebSocket session's `sendJson(value)` and the registry's
// `broadcast(pattern, value)`), matched by URL, in the libraries that import
// the starter.
//
// Only the classes of the package the call is in are described (a class of
// another package is listed in `@Introspected(classes: [...])`), and only
// what a static type shows: a value of type `Object` or `dynamic` is not
// followed, and one written that way fails at run time with a message that
// says to add `@Introspected()`.

final TypeChecker _objectMapper = _spring('ObjectMapper');

// Methods of the starters that write their argument out as JSON: the URL of
// the library that declares the method, its name, and the index of the
// argument.
const _jsonWriters = <(String, String), int>{
  (
    'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart',
    'sendJson',
  ): 0,
  (
    'package:spring_boot_starter_websocket/src/server/web_socket_handler.dart',
    'broadcast',
  ): 1,
};

// The calls of the mapper, as words: a library without one is not resolved.
final RegExp _mapperCall = RegExp(
  r'\b(readValue|treeToValue|convertValue|readList|readMap|writeValueAsString'
  r'|valueToTree)\b',
);

// The calls of the WebSocket starter that write a value out. Common names
// (`StreamController.broadcast`), so they only count in a library that
// imports the starter.
final RegExp _webSocketCall = RegExp(r'\b(sendJson|broadcast)\b');

const _webSocketStarter = 'package:spring_boot_starter_websocket/';

/// Whether [source], the text of a library, may call the `ObjectMapper` or
/// a method of a starter that writes through it: only then is the library
/// resolved. [webSocket] says the library imports the WebSocket starter,
/// without which `sendJson` and `broadcast` are other methods
/// (`StreamController.broadcast`).
bool mayCallMapper(String source, {required bool webSocket}) =>
    _mapperCall.hasMatch(source) ||
    (webSocket && _webSocketCall.hasMatch(source));

/// A class a call of the `ObjectMapper` writes out or reads in.
typedef MapperUse = ({DartType type, IntrospectionNeed need});

extension _MapperCalls on BeanScanner {
  /// Finds the calls of the `ObjectMapper` in [library] (and its parts)
  /// whose static types name classes: [scanLibrary] describes those of the
  /// package for what the calls do with them.
  ///
  /// Call it before [scanLibrary], like [BeanScanner.resolveBeanMethods].
  /// A library that does not mention a method of the mapper (nor, when it
  /// imports the WebSocket starter, one of its writers) is not resolved.
  Future<void> resolveMapperCallDeclarations(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) async {
    final uses = <MapperUse>[];
    final webSocket = _importsWebSocketStarter(library);
    for (
      LibraryFragment? fragment = library.firstFragment;
      fragment != null;
      fragment = fragment.nextFragment
    ) {
      if (!mayCallMapper(fragment.source.contents.data, webSocket: webSocket)) {
        continue;
      }
      await astNodeFor(fragment)
          .then((node) => node?.accept(_MapperCallVisitor(uses)));
    }
    if (uses.isNotEmpty) {
      _mapperUses[library] = uses;
    }
  }

  // Whether [library] imports the WebSocket starter, directly or through a
  // library that exports it.
  bool _importsWebSocketStarter(LibraryElement library) {
    final seen = <LibraryElement>{};
    bool reaches(LibraryElement other) =>
        other.uri.toString().startsWith(_webSocketStarter) ||
        (seen.add(other) && other.exportedLibraries.any(reaches));
    return [
      for (final fragment in library.fragments) ...fragment.importedLibraries,
    ].any(reaches);
  }

  /// Describes the classes of [library]'s package that its calls of the
  /// `ObjectMapper` found by [resolveMapperCallDeclarations] name.
  void _introspectMapperUses(LibraryElement library) {
    final package = BeanScanner._packageOf(library);
    for (final use in _mapperUses.remove(library) ?? const <MapperUse>[]) {
      _introspectInPackage(use.type, package, use.need);
    }
  }
}

// The types a call of the mapper names: what it reads in (the type
// argument) and what it writes out (the static type of the value).
final class _MapperCallVisitor extends RecursiveAstVisitor<void> {
  _MapperCallVisitor(this.uses);

  final List<MapperUse> uses;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    void read(DartType type) =>
        uses.add((type: type, need: IntrospectionNeed.write));
    void write(DartType? type) {
      if (type != null) {
        uses.add((type: type, need: IntrospectionNeed.read));
      }
    }

    final arguments = node.argumentList.arguments;
    // A method of a starter that writes its argument out.
    if (node.methodName.element case final ExecutableElement method) {
      final index =
          _jsonWriters[(
            '${method.library.uri}',
            node.methodName.name,
          )];
      if (index != null && index < arguments.length) {
        write(arguments[index].argumentExpression.staticType);
        return;
      }
    }
    final target = node.realTarget?.staticType;
    if (target is! InterfaceType ||
        !_objectMapper.isAssignableFromType(target)) {
      return;
    }
    final value = arguments.isEmpty
        ? null
        : arguments.first.argumentExpression.staticType;
    final typeArguments = node.typeArgumentTypes ?? const <DartType>[];
    switch (node.methodName.name) {
      case 'writeValueAsString' || 'valueToTree':
        write(value);
      case 'readValue' || 'treeToValue' || 'readList' || 'readMap':
        typeArguments.forEach(read);
      case 'convertValue':
        write(value);
        typeArguments.forEach(read);
    }
  }
}
