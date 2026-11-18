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
// the mapper (the WebSocket session's `sendJson(value)`), which their parts
// list (`StarterGeneration.jsonWriters`), in the libraries that import the
// starter.
//
// Only the classes of the package the call is in are described (a class of
// another package is listed in `@Introspected(classes: [...])`), and only
// what a static type shows: a value of type `Object` or `dynamic` is not
// followed, and one written that way fails at run time with a message that
// says to add `@Introspected()`.

final TypeChecker _objectMapper = _spring('ObjectMapper');

// The calls of the mapper, as words: a library without one is not resolved.
final RegExp _mapperCall = RegExp(
  r'\b(readValue|treeToValue|convertValue|readList|readMap|writeValueAsString'
  r'|valueToTree)\b',
);

// The words of the starters' writers, by their names joined.
final Map<String, RegExp> _writerCalls = {};

/// A method of a starter that writes one of its arguments out as JSON
/// through the `ObjectMapper`, as `ObjectMapper.writeValueAsString` does:
/// the build describes the classes of the package the argument's static
/// type names, for writing out. A clock starter's `feed.publish(tick)`:
///
/// ```dart
/// const JsonWriter('package:clock_starter/src/feed.dart', 'publish', 0)
/// ```
final class JsonWriter {
  /// The method [method] of the library [library] writing its argument at
  /// [argument].
  const JsonWriter(this.library, this.method, this.argument);

  /// The URL of the library that declares the method. A call counts only
  /// in a library that imports its package (directly or through a library
  /// that exports it), since the names are common
  /// (`StreamController.broadcast`).
  final String library;

  /// The method's name.
  final String method;

  /// The index of the positional argument it writes out.
  final int argument;

  /// The package of [library] as a URL prefix (`package:name/`).
  String get packagePrefix =>
      'package:${Uri.parse(library).pathSegments.first}/';
}

/// Whether [source], the text of a library, may call the `ObjectMapper` or
/// one of the starters' [writers] (their method names, those of the
/// starters the library imports): only then is the library resolved.
/// Without the starter imported, `sendJson` and `broadcast` are other
/// methods (`StreamController.broadcast`).
bool mayCallMapper(String source, {Iterable<String> writers = const []}) {
  if (_mapperCall.hasMatch(source)) {
    return true;
  }
  final names = writers.toSet();
  if (names.isEmpty) {
    return false;
  }
  final key = names.join('|');
  return (_writerCalls[key] ??= RegExp(
    '\\b(${names.map(RegExp.escape).join('|')})\\b',
  )).hasMatch(source);
}

/// A class a call of the `ObjectMapper` writes out or reads in.
typedef MapperUse = ({DartType type, IntrospectionNeed need});

extension _MapperCalls on BeanScanner {
  /// Finds the calls of the `ObjectMapper` in [library] (and its parts)
  /// whose static types name classes: [scanLibrary] describes those of the
  /// package for what the calls do with them.
  ///
  /// Call it before [scanLibrary], like [BeanScanner.resolveBeanMethods].
  /// A library that does not mention a method of the mapper (nor one of
  /// the writers of the starters it imports) is not resolved.
  Future<void> resolveMapperCallDeclarations(
    LibraryElement library,
    Future<AstNode?> Function(Fragment fragment) astNodeFor,
  ) async {
    final uses = <MapperUse>[];
    final writers = _importedWriters(library);
    for (
      LibraryFragment? fragment = library.firstFragment;
      fragment != null;
      fragment = fragment.nextFragment
    ) {
      if (!mayCallMapper(fragment.source.contents.data, writers: writers)) {
        continue;
      }
      await astNodeFor(fragment).then(
        (node) => node?.accept(_MapperCallVisitor(uses, _jsonWriters)),
      );
    }
    if (uses.isNotEmpty) {
      _mapperUses[library] = uses;
    }
  }

  // The names of the starters' writers whose package [library] imports.
  List<String> _importedWriters(LibraryElement library) {
    final imported = <String, bool>{};
    return [
      for (final generation in generations)
        for (final writer in generation.jsonWriters)
          if (imported[writer.packagePrefix] ??= _imports(
            library,
            writer.packagePrefix,
          ))
            writer.method,
    ];
  }

  // Whether [library] imports a library of the package of [prefix]
  // (`package:name/`), directly or through a library that exports it.
  bool _imports(LibraryElement library, String prefix) {
    final seen = <LibraryElement>{};
    bool reaches(LibraryElement other) =>
        other.uri.toString().startsWith(prefix) ||
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
  _MapperCallVisitor(this.uses, this.writers);

  final List<MapperUse> uses;

  // The index of the argument each starter's writer writes out, by the URL
  // of its library and its name.
  final Map<(String, String), int> writers;

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
          writers[(
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
