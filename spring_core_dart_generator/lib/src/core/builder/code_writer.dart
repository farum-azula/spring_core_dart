import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:code_builder/code_builder.dart'
    as cb
    show FunctionType, RecordType;
import 'package:code_builder/code_builder.dart' hide FunctionType, RecordType;
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/beans/bean_model.dart';

// Runtime types are always imported from the public library, never from
// `src/`.
const _springCoreDartUrl = 'package:spring_core_dart/spring_core_dart.dart';

/// A raw string literal of [value], so `$` and backslashes in names and
/// expressions are written as they are.
Expression _rawString(String value) => literalString(value, raw: true);

/// How one generated library of a module names what it uses: the types,
/// constants and functions of the application (imported through the public
/// library that declares or exports them, relative to [output] for the
/// package's own files outside `lib/`), and the top-level functions and
/// constants it declares for the closures of constant descriptions.
///
/// The module's library (`.spring.dart`) and its descriptions
/// (`.spring.introspection.dart`, `.spring.properties.dart`) each have one, and
/// share the types their annotations name ([annotationTypes]), which the module
/// tests values against (`BeanModule.typeTests`).
///
/// ```dart
/// final writer =
///     CodeWriter(output, dependencies: {'app', 'spring_core_dart'});
/// writer.classType(bookType, element); // refer('Book', 'package:app/book.dart')
/// ```
final class CodeWriter {
  /// The writer of the library [output]; [annotationTypes] are shared with
  /// the module's other libraries.
  CodeWriter(
    this.output, {
    this.dependencies,
    Map<String, (InterfaceType, Element)>? annotationTypes,
  }) : annotationTypes = annotationTypes ?? {};

  /// The library being generated. Imports of files of the same package
  /// outside `lib/` (an `asset:` URI) are written relative to it.
  final AssetId output;

  /// The packages the generated library's package depends on directly,
  /// itself included; `null` when unknown.
  ///
  /// A declaration of any other package (a transitive dependency) is
  /// imported through a library of these that exports it, the way the
  /// user's code reaches it. So the output does not trigger
  /// `depend_on_referenced_packages`.
  final Set<String>? dependencies;

  /// The class types written in the annotations of the module being
  /// emitted, by name, each with the element it was found on: the module
  /// gets a `value is T` test for each (`BeanModule.typeTests`).
  final Map<String, (InterfaceType, Element)> annotationTypes;

  /// The type parameters of the generic introspected class being written,
  /// erased to their bound or `dynamic` (the raw introspection): [anyType]
  /// writes the bound in their place.
  Map<TypeParameterElement, DartType?> erasedTypeParameters = const {};

  /// The type parameters of the generic introspected class being written,
  /// bound to the type argument at this index of `specialize`'s
  /// `arguments`.
  Map<TypeParameterElement, int> capturedTypeParameters = const {};

  /// [body], run with the erased [parameter] standing for `dynamic` (also
  /// inside its own bound: `T extends Comparable<T>`).
  T withoutErasure<T>(TypeParameterElement parameter, T Function() body) {
    final bound = erasedTypeParameters[parameter];
    erasedTypeParameters = {...erasedTypeParameters, parameter: null};
    try {
      return body();
    } finally {
      erasedTypeParameters = {...erasedTypeParameters, parameter: bound};
    }
  }

  /// Whether [type] names a type parameter the generated code has no name
  /// for: one of the class that declares a method of a generic base class
  /// (`save(E entity)` of `Crud<E>`, called on a `BookCrud extends
  /// `Crud<Book>`). Those of the generic class being described are erased
  /// ([erasedTypeParameters]) or captured ([capturedTypeParameters]).
  bool hasFreeTypeParameter(DartType type) => switch (type) {
    TypeParameterType(:final element) =>
      !erasedTypeParameters.containsKey(element) &&
          !capturedTypeParameters.containsKey(element),
    InterfaceType(:final typeArguments) => typeArguments.any(
      hasFreeTypeParameter,
    ),
    FunctionType() =>
      hasFreeTypeParameter(type.returnType) ||
          type.formalParameters.any(
            (parameter) => hasFreeTypeParameter(parameter.type),
          ),
    RecordType() =>
      type.positionalFields.any((field) => hasFreeTypeParameter(field.type)) ||
          type.namedFields.any((field) => hasFreeTypeParameter(field.type)),
    _ => false,
  };

  /// The top-level functions written for the closures of descriptions that
  /// are constants (a closure cannot be part of a constant; a tear-off of a
  /// top-level function can), and the top-level constants several
  /// descriptions share, in the order they are written: the library
  /// declares them.
  final topLevelDeclarations = <Spec>[];

  /// A top-level constant `_$<kind><n>` of the library with the value
  /// [value] (written in a const context); returns a reference to it.
  Expression topLevelConstant(String kind, Expression value) {
    final name = '_\$$kind${topLevelDeclarations.length}';
    topLevelDeclarations.add(
      Field(
        (f) => f
          ..name = name
          ..modifier = FieldModifier.constant
          ..assignment = value.code,
      ),
    );
    return refer(name);
  }

  /// A top-level function `_$<kind><n>` of the library with [parameters]
  /// and the body [body] (an expression, or a block when not [lambda]),
  /// returning [returns]; returns a reference to it.
  Expression topLevelFunction(
    String kind,
    Reference returns,
    List<(String, Reference)> parameters,
    Code body, {
    bool lambda = true,
  }) {
    final name = '_\$$kind${topLevelDeclarations.length}';
    topLevelDeclarations.add(
      Method(
        (m) => m
          ..returns = returns
          ..name = name
          ..requiredParameters.addAll([
            for (final (parameterName, type) in parameters)
              Parameter(
                (p) => p
                  ..name = parameterName
                  ..type = type,
              ),
          ])
          ..lambda = lambda
          ..body = body,
      ),
    );
    return refer(name);
  }

  /// An untyped closure of [parameters] with [body] (an expression when
  /// [lambda], else a block); the parameter types are inferred from the
  /// runtime API's function types.
  Expression closure(
    List<String> parameters,
    Code body, {
    bool lambda = false,
  }) => Method(
    (m) => m
      ..requiredParameters.addAll([
        for (final name in parameters) Parameter((p) => p..name = name),
      ])
      ..lambda = lambda
      ..body = body,
  ).closure;

  /// `Object?`.
  static final objectOrNull = TypeReference(
    (t) => t
      ..symbol = 'Object'
      ..isNullable = true,
  );

  /// `List<Object?>`: the arguments `Function.apply` passes by position.
  static final argumentList = TypeReference(
    (t) => t
      ..symbol = 'List'
      ..types.add(objectOrNull),
  );

  /// `Map<Symbol, Object?>`: the arguments `Function.apply` passes by
  /// name.
  static final namedArgumentMap = TypeReference(
    (t) => t
      ..symbol = 'Map'
      ..types.addAll([refer('Symbol'), objectOrNull]),
  );

  /// A reference to [type] as generated code writes it, with its import:
  /// classes, type parameters, function and record types, with `?` kept.
  /// [element] is where the type was found, for error messages.
  Reference anyType(DartType type, Element element) {
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
    switch (type) {
      // The raw introspection of a generic class.
      case TypeParameterType()
          when erasedTypeParameters.containsKey(type.element):
        final bound = erasedTypeParameters[type.element];
        return bound == null
            ? refer('dynamic')
            : withoutErasure(type.element, () => anyType(bound, element));
      case TypeParameterType():
        return TypeReference(
          (t) => t
            ..symbol = type.element.name
            ..isNullable = nullable,
        );
      case FunctionType():
        return cb.FunctionType(
          (f) => f
            ..returnType = anyType(type.returnType, element)
            ..requiredParameters.addAll([
              for (final parameter in type.formalParameters)
                if (parameter.isRequiredPositional)
                  anyType(parameter.type, element),
            ])
            ..optionalParameters.addAll([
              for (final parameter in type.formalParameters)
                if (parameter.isOptionalPositional)
                  anyType(parameter.type, element),
            ])
            ..namedParameters.addAll({
              for (final parameter in type.formalParameters)
                if (parameter.isOptionalNamed)
                  parameter.name!: anyType(parameter.type, element),
            })
            ..namedRequiredParameters.addAll({
              for (final parameter in type.formalParameters)
                if (parameter.isRequiredNamed)
                  parameter.name!: anyType(parameter.type, element),
            })
            ..isNullable = nullable,
        );
      case RecordType():
        return cb.RecordType(
          (r) => r
            ..positionalFieldTypes.addAll([
              for (final field in type.positionalFields)
                anyType(field.type, element),
            ])
            ..namedFieldTypes.addAll({
              for (final field in type.namedFields)
                field.name: anyType(field.type, element),
            })
            ..isNullable = nullable,
        );
      default:
        return classType(type, element);
    }
  }

  /// A reference to a class type (with type arguments and nullability),
  /// `void`, `dynamic` or `Never`, declared or used by [element]; other
  /// types are not supported here (use [anyType]).
  ///
  /// Throws `InvalidGenerationSource` when the library cannot be imported
  /// from the output (a file of another package outside `lib/`).
  TypeReference classType(DartType type, Element element) {
    if (type is VoidType || type is DynamicType || type is NeverType) {
      return TypeReference((t) => t..symbol = type.getDisplayString());
    }
    if (type is! InterfaceType) {
      throw InvalidGenerationSource(
        'Unsupported type ${type.getDisplayString()}.',
        element: element,
      );
    }
    return TypeReference(
      (t) => t
        ..symbol = type.element.name
        ..url = importUrl(
          type.element.library.uri,
          element,
          name: type.element.name,
          declaration: type.element,
        )
        ..isNullable = type.nullabilitySuffix == NullabilitySuffix.question
        ..types.addAll([
          // Type arguments may be type parameters, functions or records.
          for (final argument in type.typeArguments) anyType(argument, element),
        ]),
    );
  }

  /// Writes a constant value (a default value, an annotation instance) as
  /// code that re-creates it: literals, lists, maps, sets, records, types,
  /// enum values, functions and `const` constructor calls.
  Expression constant(DartObject value, Element element) {
    final reader = ConstantReader(value);
    if (reader.isNull) {
      return literalNull;
    }
    if (reader.isBool) {
      return literalBool(reader.boolValue);
    }
    if (reader.isInt) {
      return literalNum(reader.intValue);
    }
    if (reader.isDouble) {
      return number(reader.doubleValue);
    }
    if (reader.isString) {
      return _rawString(reader.stringValue);
    }
    if (reader.isType) {
      final type = reader.typeValue;
      if (type is InterfaceType &&
          type.element.isPublic &&
          type.typeArguments.isEmpty &&
          !type.isDartCoreObject) {
        annotationTypes.putIfAbsent(
          type.getDisplayString(),
          () => (type, element),
        );
      }
      return classType(type, element);
    }
    if (reader.isSymbol) {
      return CodeExpression(Code('#${value.toSymbolValue()}'));
    }
    if (value.toRecordValue() case final record?) {
      return literalConstRecord(
        [for (final field in record.positional) constant(field, element)],
        {
          for (final MapEntry(:key, value: field) in record.named.entries)
            key: constant(field, element),
        },
      );
    }
    // Collections with their type arguments when the elements do not give
    // them (`const <int>[]`, `const <Object>[1]`), so the value keeps its
    // runtime type; `const [Tag()]` stays as it is.
    final typeArguments = switch (value.type) {
      final InterfaceType type => type.typeArguments,
      _ => const <DartType>[],
    };
    Reference? typeArgumentNotInferred(
      int index,
      Iterable<DartObject?> elements,
    ) =>
        index < typeArguments.length &&
            (elements.isEmpty ||
                elements.any(
                  (element) => element?.type != typeArguments[index],
                ))
        ? collectionTypeArgument(typeArguments[index], element)
        : null;
    if (reader.isList) {
      final items = reader.listValue;
      return literalConstList([
        for (final item in items) constant(item, element),
      ], typeArgumentNotInferred(0, items));
    }
    if (reader.isSet) {
      final items = reader.setValue;
      return literalConstSet({
        for (final item in items) constant(item, element),
      }, typeArgumentNotInferred(0, items));
    }
    if (reader.isMap) {
      final entries = reader.mapValue;
      // Both type arguments or none: code_builder writes `<K, dynamic>` for
      // a key type alone, and nothing for a value type alone.
      final writesTypeArguments =
          typeArgumentNotInferred(0, entries.keys) != null ||
          typeArgumentNotInferred(1, entries.values) != null;
      Reference? mapTypeArgument(int index) =>
          writesTypeArguments && index < typeArguments.length
          ? collectionTypeArgument(typeArguments[index], element) ??
                refer('dynamic')
          : null;
      return literalConstMap(
        {
          for (final MapEntry(:key, :value) in entries.entries)
            constant(key!, element): constant(value!, element),
        },
        mapTypeArgument(0),
        mapTypeArgument(1),
      );
    }
    final function = value.toFunctionValue();
    if (function != null) {
      return functionReference(function, element);
    }
    // Any other object is "revived": source_gen finds a public const
    // constructor invocation (or a top-level constant / enum value) that
    // recreates it, which is written as `const Type(...)` with recursively
    // re-created arguments.
    final revivable = reader.revive();
    if (revivable.isPrivate) {
      throw InvalidGenerationSource(
        'Cannot re-create private constant ${value.type}.',
        element: element,
      );
    }
    final source = revivable.source;
    final url = importUrl(
      source.removeFragment(),
      element,
      name: source.fragment.isEmpty
          ? revivable.accessor.split('.').first
          : source.fragment,
    );
    if (source.fragment.isEmpty) {
      // A top-level constant or an enum value (`Enum.value`).
      final [first, ...rest] = revivable.accessor.split('.');
      return rest.fold<Expression>(
        refer(first, url),
        (target, name) => target.property(name),
      );
    }
    final type = refer(source.fragment, url);
    final positional = [
      for (final argument in revivable.positionalArguments)
        constant(argument, element),
    ];
    final named = {
      for (final MapEntry(:key, :value) in revivable.namedArguments.entries)
        key: constant(value, element),
    };
    return revivable.accessor.isEmpty
        ? type.constInstance(positional, named)
        : type.constInstanceNamed(revivable.accessor, positional, named);
  }

  /// Writes the initial value of a field (see `InitialValue`): a literal, a
  /// referenced constant, or a `const` collection of those.
  ///
  /// [type] is the field's declared type: a collection gets its type
  /// arguments, as Dart infers them from the field (`const <String>[]`,
  /// `const <num>[1]` for a `List<num>`), so the value keeps its runtime
  /// type outside the field.
  Expression initialValue(Object? value, Element element, [DartType? type]) {
    final typeArguments = type is InterfaceType ? type.typeArguments : null;
    DartType? typeArgumentAt(int index) =>
        typeArguments != null && index < typeArguments.length
        ? typeArguments[index]
        : null;
    Reference? writtenTypeArgument(int index) =>
        collectionTypeArgument(typeArgumentAt(index), element);
    // Both type arguments of a map or none (see `constant`).
    (Reference?, Reference?) mapTypeArguments() {
      final keyType = writtenTypeArgument(0);
      final valueType = writtenTypeArgument(1);
      return keyType == null && valueType == null
          ? (null, null)
          : (keyType ?? refer('dynamic'), valueType ?? refer('dynamic'));
    }

    return switch (value) {
      null => literalNull,
      final bool value => literalBool(value),
      final num value => number(value),
      final String value => _rawString(value),
      final DartObject value => constant(value, element),
      final List<Object?> value => literalConstList([
        for (final item in value)
          initialValue(item, element, typeArgumentAt(0)),
      ], writtenTypeArgument(0)),
      final Set<Object?> value => literalConstSet({
        for (final item in value)
          initialValue(item, element, typeArgumentAt(0)),
      }, writtenTypeArgument(0)),
      final Map<Object?, Object?> value => switch (mapTypeArguments()) {
        (final keyType, final valueType) => literalConstMap(
          {
            for (final MapEntry(:key, value: item) in value.entries)
              initialValue(key, element, typeArgumentAt(0)): initialValue(
                item,
                element,
                typeArgumentAt(1),
              ),
          },
          keyType,
          valueType,
        ),
      },
      _ => throw StateError('Unsupported initial value $value'),
    };
  }

  /// [value] as code: a literal, or `double.infinity`,
  /// `double.negativeInfinity` and `double.nan`, which have none (their
  /// `toString` is `Infinity` and `NaN`).
  static Expression number(num value) => switch (value) {
    double(isNaN: true) => refer('double').property('nan'),
    double(isInfinite: true) => refer(
      'double',
    ).property(value > 0 ? 'infinity' : 'negativeInfinity'),
    _ => literalNum(value),
  };

  /// The type argument [type] of a constant collection, when it can be
  /// written there: `null` (none, inferred) for `dynamic` and for a type
  /// that names a type parameter or cannot be imported ([element] is where
  /// it was found).
  Reference? collectionTypeArgument(DartType? type, Element element) {
    if (type == null ||
        type is DynamicType ||
        type is NeverType ||
        hasFreeTypeParameter(type)) {
      return null;
    }
    final annotationTypesBefore = Map.of(annotationTypes);
    try {
      return anyType(type, element);
    } on InvalidGenerationSource {
      annotationTypes
        ..clear()
        ..addAll(annotationTypesBefore);
      return null;
    }
  }

  /// A tear-off of the top-level [function] or `Class.staticMethod`, used
  /// by [element].
  Expression functionReference(ExecutableElement function, Element element) {
    final name = function.name!;
    final url = importUrl(
      function.library.uri,
      element,
      name: switch (function.enclosingElement) {
        final InterfaceElement enclosing => enclosing.name,
        _ => function.name,
      },
    );
    final enclosing = function.enclosingElement;
    if (function is MethodElement && enclosing is InterfaceElement) {
      return refer(enclosing.name!, url).property(name);
    }
    return refer(name, url);
  }

  // A library of a direct dependency (or of the generated package) that
  // the library of [element] imports and that exports [name] of [uri].
  Uri? _exportingLibrary(Uri uri, String name, Element element) {
    final library = element.library;
    if (library == null) {
      return null;
    }
    for (final fragment in library.fragments) {
      for (final imported in fragment.importedLibraries) {
        final candidate = imported.uri;
        if (candidate.scheme == 'package' &&
            dependencies!.contains(candidate.pathSegments.first) &&
            imported.exportNamespace.get2(name)?.library?.uri == uri) {
          return candidate;
        }
      }
    }
    return null;
  }

  /// Maps the library URI [uri] of a declaration [name] (found on
  /// [element]) to an import usable from [output]: `dart:core` needs none,
  /// runtime `src/` libraries map to the public library, `package:` and
  /// `dart:` URIs are kept, `asset:` URIs under `lib/` become `package:`
  /// URIs and other files of the same package (e.g. `test/`) become
  /// relative paths. Anything else cannot be imported (throws
  /// `InvalidGenerationSource`).
  String? importUrl(
    Uri uri,
    Element element, {
    String? name,
    Element? declaration,
  }) {
    switch (uri.scheme) {
      case 'dart' when uri.path == 'core':
        return null;
      // `HttpClient` is declared in `dart:_http`, which cannot be imported:
      // use the public library that exports it (`dart:io`), which the
      // user's code or the declaring library imports.
      case 'dart' when uri.path.startsWith('_'):
        final public = name == null
            ? null
            : publicSdkLibrary(name, element, declaration: declaration);
        if (public != null) {
          return public.path == 'core' ? null : public.toString();
        }
        throw InvalidGenerationSource(
          'Cannot reference ${name ?? 'a declaration'} of the internal '
          'library $uri: import the public library that exports it '
          '(for example dart:io) in the file that uses it.',
          element: element,
        );
      case 'package' when uri.pathSegments.first == 'spring_core_dart':
        // Public library instead of the runtime's src/ files; the Jakarta
        // names (`Provider`, `Resource`) are not exported by the main one.
        return uri.path.endsWith('/src/beans/jakarta.dart')
            ? 'package:spring_core_dart/jakarta.dart'
            : _springCoreDartUrl;
      case 'package'
          when name != null &&
              dependencies != null &&
              !dependencies!.contains(uri.pathSegments.first):
        return _exportingLibrary(uri, name, element)?.toString() ??
            uri.toString();
      case 'dart' || 'package':
        return uri.toString();
      case 'asset':
        final [package, ...segments] = uri.pathSegments;
        if (segments.firstOrNull == 'lib') {
          return importUrl(
            Uri(
              scheme: 'package',
              pathSegments: [package, ...segments.skip(1)],
            ),
            element,
            name: name,
          );
        }
        if (package != output.package) {
          break;
        }
        return p.url.relative(
          p.url.joinAll(segments),
          from: p.url.dirname(output.path),
        );
    }
    throw InvalidGenerationSource(
      'Cannot import $uri from ${output.uri}.',
      element: element,
    );
  }

  /// A Dart emitter for [output]: its imports get prefixes (`_i1.`), the
  /// container's API is imported through `spring_boot_dart` when the
  /// package depends on that and not on `spring_core_dart`. The libraries
  /// written with one emitter share its imports (a library and its parts).
  DartEmitter emitter() => DartEmitter(
    allocator: _ReexportingAllocator(
      Allocator.simplePrefixing(),
      _reexportingLibraries(dependencies),
    ),
    orderDirectives: true,
    useNullSafetySyntax: true,
  );

  /// The source of [library], written with a new [emitter] after the
  /// generated files' header ([generatedHeader]); the builder formats it
  /// as its package's files are (`DartFormat`).
  String source(Library library) =>
      '$generatedHeader\n${library.accept(emitter())}';
}

/// The first lines of every generated file of a module: what wrote it, and
/// the diagnostics its code does not answer to (proxies and descriptions
/// call members of the user's classes whatever their `package:meta` and
/// `@Deprecated` markers say).
const generatedHeader =
    '// GENERATED CODE - DO NOT MODIFY BY HAND\n'
    '// Generated by spring_core_dart_generator from @ComponentScan.\n\n'
    '// ignore_for_file: type=lint, implementation_imports, unnecessary_cast\n'
    '// ignore_for_file: deprecated_member_use\n'
    '// ignore_for_file: invalid_use_of_visible_for_testing_member\n'
    '// ignore_for_file: invalid_use_of_internal_member\n'
    '// ignore_for_file: invalid_use_of_protected_member\n';

// The container API through `spring_boot_dart`, which re-exports it, when
// the package depends on `spring_boot_dart` but not on `spring_core_dart`
// (a starter): pub.dev refuses a package whose lib/ imports a package that
// is not in its `dependencies`, and the user's code reaches the API the
// same way.
Map<String, String> _reexportingLibraries(Set<String>? dependencies) => {
  if (dependencies != null &&
      !dependencies.contains('spring_core_dart') &&
      dependencies.contains('spring_boot_dart'))
    _springCoreDartUrl: 'package:spring_boot_dart/spring_boot_dart.dart',
};

// An allocator that imports the libraries of [_reexportingLibrary] through
// the library that re-exports them.
class _ReexportingAllocator implements Allocator {
  _ReexportingAllocator(this._inner, this._reexportingLibrary);

  final Allocator _inner;
  final Map<String, String> _reexportingLibrary;

  @override
  String allocate(Reference reference) {
    final url = _reexportingLibrary[reference.url];
    return _inner.allocate(
      url == null ? reference : Reference(reference.symbol, url),
    );
  }

  @override
  Iterable<Directive> get imports => _inner.imports;
}
