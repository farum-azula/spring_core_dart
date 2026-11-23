import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/project_model.dart';

/// What every Dart object has, so a member check never reports it.
const dartObjectMembers = {
  'toString',
  'hashCode',
  'runtimeType',
  'noSuchMethod',
};

/// The collections whose first type argument is their element.
const _collections = {
  'List',
  'Set',
  'Iterable',
  'Queue',
  'ListQueue',
  'DoubleLinkedQueue',
  'LinkedHashSet',
  'HashSet',
  'SplayTreeSet',
  'UnmodifiableListView',
  'UnmodifiableSetView',
};

/// The maps, whose second type argument is what an index gives.
const _maps = {
  'Map',
  'LinkedHashMap',
  'HashMap',
  'SplayTreeMap',
  'UnmodifiableMapView',
};

/// The futures, unwrapped when a method's value is read.
const _futures = {'Future', 'FutureOr'};

/// Supertypes of `dart:core` that add nothing an expression can read.
const _plainSupertypes = {'Object', 'Comparable', 'Exception'};

/// Types with no members to look up.
const _withoutMembers = {'dynamic', 'void', 'Never', 'Object', 'Function'};

/// A type as written in a Dart file: its simple name and type arguments,
/// resolved through the imports of [file] when it is asked for.
final class TypeRef {
  /// [name] with [arguments], as [file] sees it (through [prefix]). With
  /// [open] the value at run time may have more members than the type says.
  const TypeRef(
    this.name,
    this.arguments,
    this.file, {
    this.prefix,
    this.open = false,
  });

  /// The simple name.
  final String name;

  /// The type arguments; `null` for one that is not known.
  final List<TypeRef?> arguments;

  /// The file the type is written in.
  final DartFile file;

  /// The import prefix it is written with.
  final String? prefix;

  /// Whether a member the type does not declare may still be there.
  final bool open;

  /// The type as shown in a hover.
  String get display => arguments.isEmpty
      ? name
      : '$name<${arguments.map((a) => a?.display ?? 'dynamic').join(', ')}>';
}

/// A field, getter, setter or method of a type, with where it is declared.
final class DartMember {
  /// The member [name] at [offset] of [file].
  const DartMember(
    this.name,
    this.file,
    this.offset,
    this.type,
    this.typeText, {
    required this.isMethod,
    required this.isStatic,
    required this.owner,
    this.parameters,
  });

  /// The name.
  final String name;

  /// The file that declares it.
  final DartFile file;

  /// The offset of its name.
  final int offset;

  /// Its type, or for a method what it returns; `null` when not known.
  final TypeRef? type;

  /// The type as written.
  final String typeText;

  /// Whether it is a method.
  final bool isMethod;

  /// Whether it is static: declared, but not read on an instance.
  final bool isStatic;

  /// The class that declares it.
  final String owner;

  /// A method's parameters as written.
  final String? parameters;

  /// The member in one line.
  String get signature =>
      '${type?.display ?? typeText} $name${isMethod ? parameters ?? '()' : ''}';
}

/// The members of a type, inherited ones included.
final class TypeMembers {
  /// The [members] of [typeName]; [complete] when no supertype is missing
  /// and the value at run time cannot have more.
  const TypeMembers(this.typeName, this.members, {required this.complete});

  /// The type as shown.
  final String typeName;

  /// The members by name, the nearest declaration of each.
  final Map<String, DartMember> members;

  /// Whether a name missing from [members] is really not there.
  final bool complete;
}

/// The syntax of a class, mixin, enum or extension type, as one shape.
final class _Shape {
  const _Shape(
    this.name,
    this.typeParameters,
    this.supertypes,
    this.members,
    this.declaring, {
    required this.open,
  });

  final String name;
  final List<String> typeParameters;
  final List<NamedType> supertypes;
  final List<ClassMember> members;
  final List<FormalParameter> declaring;
  final bool open;
}

/// The smallest type resolution SpEL navigation needs, from syntax alone:
/// a name is looked up in its library and through its imports and exports
/// (`show`, `hide` and prefixes respected), across the workspace and the
/// packages of `package_config.json`.
///
/// It cannot follow inferred types (`var`, `final x = ...`), function and
/// record types, or conditional imports' other branches; those are simply
/// not known, and nothing is reported about them.
final class DartTypes {
  /// Types over [model].
  DartTypes(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  final _external = <String, (DateTime, DartFile)>{};
  final _exported = <String, Map<String, String>>{};
  final _exportedFrom = <String, DartFile>{};
  var _generation = -1;

  /// The parsed file at [path]: from the workspace when it is there, else
  /// parsed apart, so a dependency's file never counts as workspace code.
  DartFile? fileAt(String path) {
    if (model.files.loaded(path) case final loaded?) {
      return loaded;
    }
    final file = File(path);
    if (!path.endsWith('.dart') || !file.existsSync()) {
      return null;
    }
    final modified = file.lastModifiedSync();
    final cached = _external[path];
    if (cached != null && cached.$1 == modified) {
      return cached.$2;
    }
    try {
      final parsed = DartFile.parse(path, file.readAsStringSync());
      _external[path] = (modified, parsed);
      return parsed;
    } on Object {
      return null;
    }
  }

  /// [type] as a reference from [file]; [scope] gives what the type
  /// parameters in view stand for. `null` for what has no members to read.
  TypeRef? refOf(
    TypeAnnotation? type,
    DartFile file, [
    Map<String, TypeRef?> scope = const {},
  ]) {
    if (type is! NamedType) {
      return null;
    }
    final name = type.name.lexeme;
    if (scope.containsKey(name)) {
      return scope[name];
    }
    if (_withoutMembers.contains(name)) {
      return null;
    }
    return TypeRef(
      name,
      [
        for (final argument
            in type.typeArguments?.arguments ?? const <TypeAnnotation>[])
          refOf(argument, file, scope),
      ],
      file,
      prefix: type.importPrefix?.name.lexeme,
    );
  }

  /// The value of [type] once awaited: `T` of `Future<T>`.
  TypeRef? awaited(TypeRef? type) {
    var current = type;
    while (current != null &&
        _futures.contains(current.name) &&
        _declaration(current) == null) {
      current = current.arguments.firstOrNull;
    }
    return current;
  }

  /// The element of a collection; `null` for any other type.
  TypeRef? elementOf(TypeRef? type) =>
      type != null &&
          _collections.contains(type.name) &&
          _declaration(type) == null
      ? type.arguments.firstOrNull
      : null;

  /// What `value[index]` gives on [type]: an element, or a map's value.
  TypeRef? indexed(TypeRef? type) {
    if (type != null &&
        _maps.contains(type.name) &&
        _declaration(type) == null) {
      return type.arguments.elementAtOrNull(1);
    }
    return elementOf(type);
  }

  /// Whether [type] is a collection or a map of the core libraries.
  bool isCollection(TypeRef? type) =>
      type != null &&
      (_collections.contains(type.name) || _maps.contains(type.name)) &&
      _declaration(type) == null;

  /// The class, mixin or enum enclosing [node], as a type.
  TypeRef? enclosing(AstNode node, DartFile file) {
    for (AstNode? current = node; current != null; current = current.parent) {
      final name = switch (current) {
        final ClassDeclaration c => c.namePart.typeName.lexeme,
        final MixinDeclaration m => m.name.lexeme,
        final EnumDeclaration e => e.namePart.typeName.lexeme,
        final ExtensionTypeDeclaration e => e.namePart.typeName.lexeme,
        _ => null,
      };
      if (name != null) {
        return TypeRef(name, const [], file);
      }
    }
    return null;
  }

  /// The members of [type]; `null` when its declaration cannot be found.
  TypeMembers? membersOf(TypeRef type) {
    final found = _declaration(type);
    if (found == null) {
      return null;
    }
    final members = <String, DartMember>{};
    final visited = <String>{};
    final complete = _collect(
      found.$1,
      found.$2,
      type.arguments,
      members,
      visited,
    );
    return TypeMembers(
      type.display,
      members,
      complete: complete && !type.open && !members.containsKey('noSuchMethod'),
    );
  }

  /// Whether a class of the workspace below [type] declares [name]: the
  /// value at run time may be one of them.
  bool subtypeDeclares(TypeRef type, String name) {
    for (final info in model.classes.allClasses) {
      if (info.name == type.name ||
          !model.classes.supertypesOf(info.name).contains(type.name)) {
        continue;
      }
      final file = fileAt(info.path);
      if (file == null) {
        continue;
      }
      final shape = _shapeOf(info.declaration);
      if (shape != null &&
          _own(shape, file, const {}).any((member) => member.name == name)) {
        return true;
      }
    }
    return false;
  }

  // Adds the members of [node] and its supertypes; whether all were found.
  bool _collect(
    CompilationUnitMember node,
    DartFile file,
    List<TypeRef?> arguments,
    Map<String, DartMember> members,
    Set<String> visited,
  ) {
    final shape = _shapeOf(node);
    if (shape == null || !visited.add('${file.path}#${shape.name}')) {
      return shape != null;
    }
    final scope = <String, TypeRef?>{
      for (final (index, name) in shape.typeParameters.indexed)
        name: arguments.elementAtOrNull(index),
    };
    for (final member in _own(shape, file, scope)) {
      members.putIfAbsent(member.name, () => member);
    }
    var complete = !shape.open;
    for (final supertype in shape.supertypes) {
      final ref = refOf(supertype, file, scope);
      final name = supertype.name.lexeme;
      final found = ref == null ? null : _declaration(ref);
      if (found == null) {
        complete = complete && _plainSupertypes.contains(name);
        continue;
      }
      complete =
          _collect(found.$1, found.$2, ref!.arguments, members, visited) &&
          complete;
    }
    return complete;
  }

  Iterable<DartMember> _own(
    _Shape shape,
    DartFile file,
    Map<String, TypeRef?> scope,
  ) sync* {
    for (final parameter in shape.declaring) {
      final name = parameter.name;
      if (name == null) {
        continue;
      }
      yield DartMember(
        name.lexeme,
        file,
        name.offset,
        refOf(parameter.type, file, scope),
        parameter.type?.toSource() ?? 'dynamic',
        isMethod: false,
        isStatic: false,
        owner: shape.name,
      );
    }
    for (final member in shape.members) {
      switch (member) {
        case FieldDeclaration(:final fields, :final isStatic):
          for (final variable in fields.variables) {
            yield DartMember(
              variable.name.lexeme,
              file,
              variable.name.offset,
              refOf(fields.type, file, scope),
              fields.type?.toSource() ?? 'dynamic',
              isMethod: false,
              isStatic: isStatic,
              owner: shape.name,
            );
          }
        case MethodDeclaration() when !member.isOperator:
          final methodScope = {
            ...scope,
            for (final parameter
                in member.typeParameters?.typeParameters ??
                    const <TypeParameter>[])
              parameter.name.lexeme: null,
          };
          yield DartMember(
            member.name.lexeme,
            file,
            member.name.offset,
            member.isSetter
                ? refOf(
                    member.parameters?.parameters.firstOrNull?.type,
                    file,
                    methodScope,
                  )
                : refOf(member.returnType, file, methodScope),
            member.returnType?.toSource() ?? 'dynamic',
            isMethod: !member.isGetter && !member.isSetter,
            isStatic: member.isStatic,
            owner: shape.name,
            parameters: member.parameters?.toSource(),
          );
        case _:
          break;
      }
    }
  }

  static List<String> _typeParameterNames(TypeParameterList? list) => [
    for (final parameter in list?.typeParameters ?? const <TypeParameter>[])
      parameter.name.lexeme,
  ];

  static List<FormalParameter> _declaringParameters(
    ClassNamePart part, {
    bool all = false,
  }) => part is PrimaryConstructorDeclaration
      ? [
          for (final parameter in part.formalParameters.parameters)
            if (all ||
                (parameter is! SuperFormalParameter &&
                    parameter is! FieldFormalParameter &&
                    parameter.constFinalOrVarKeyword != null))
              parameter,
        ]
      : const [];

  static _Shape? _shapeOf(CompilationUnitMember node) => switch (node) {
    final ClassDeclaration c => _Shape(
      c.namePart.typeName.lexeme,
      _typeParameterNames(c.namePart.typeParameters),
      [
        ?c.extendsClause?.superclass,
        ...?c.withClause?.mixinTypes,
        ...?c.implementsClause?.interfaces,
      ],
      c.body.members,
      _declaringParameters(c.namePart),
      open: c.abstractKeyword != null || c.interfaceKeyword != null,
    ),
    final MixinDeclaration m => _Shape(
      m.name.lexeme,
      _typeParameterNames(m.typeParameters),
      [
        ...?m.onClause?.superclassConstraints,
        ...?m.implementsClause?.interfaces,
      ],
      m.body.members,
      const [],
      open: true,
    ),
    final EnumDeclaration e => _Shape(
      e.namePart.typeName.lexeme,
      _typeParameterNames(e.namePart.typeParameters),
      [...?e.withClause?.mixinTypes, ...?e.implementsClause?.interfaces],
      e.body.members,
      _declaringParameters(e.namePart),
      // `name` and `index` come from the core library.
      open: true,
    ),
    final ExtensionTypeDeclaration e => _Shape(
      e.namePart.typeName.lexeme,
      _typeParameterNames(e.namePart.typeParameters),
      [...?e.implementsClause?.interfaces],
      e.body.members,
      _declaringParameters(e.namePart, all: true),
      open: true,
    ),
    _ => null,
  };

  static String? _declaredName(CompilationUnitMember node) => switch (node) {
    final ClassDeclaration c => c.namePart.typeName.lexeme,
    final MixinDeclaration m => m.name.lexeme,
    final EnumDeclaration e => e.namePart.typeName.lexeme,
    final ExtensionTypeDeclaration e => e.namePart.typeName.lexeme,
    final TypeAlias a => a.name.lexeme,
    _ => null,
  };

  // The declaration of [type], aliases followed: the node and its file.
  (CompilationUnitMember, DartFile)? _declaration(
    TypeRef type, [
    int depth = 0,
  ]) {
    if (depth > 8) {
      return null;
    }
    final path = _whereDeclared(type);
    final file = path == null ? null : fileAt(path);
    if (file == null) {
      return null;
    }
    for (final node in file.unit.declarations) {
      if (_declaredName(node) != type.name) {
        continue;
      }
      if (node is GenericTypeAlias) {
        final aliased = refOf(node.type, file, {
          for (final (index, name) in _typeParameterNames(
            node.typeParameters,
          ).indexed)
            name: type.arguments.elementAtOrNull(index),
        });
        return aliased == null ? null : _declaration(aliased, depth + 1);
      }
      return node is TypeAlias ? null : (node, file);
    }
    return null;
  }

  // The file declaring [type], as its library sees it: its own units, or
  // the one import that gives the name. Several give it: not known.
  String? _whereDeclared(TypeRef type) {
    _forgetIfChanged();
    final library = _libraryOf(type.file);
    if (type.prefix == null) {
      for (final unit in _unitsOf(library)) {
        if (unit.unit.declarations.any(
          (node) => _declaredName(node) == type.name,
        )) {
          return unit.path;
        }
      }
    }
    final found = <String>{};
    for (final directive in library.unit.directives) {
      if (directive is! ImportDirective ||
          directive.prefix?.name != type.prefix ||
          !_passes(directive.combinators, type.name)) {
        continue;
      }
      final path = _uriPath(library, directive.uri.stringValue);
      if (path == null) {
        continue;
      }
      if (_exportsOf(path, {})[type.name] case final where?) {
        found.add(where);
      }
    }
    return found.length == 1 ? found.single : null;
  }

  void _forgetIfChanged() {
    final generation = model.classes.generation;
    final stale =
        generation != _generation ||
        _exportedFrom.entries.any((entry) {
          final loaded = model.files.loaded(entry.key);
          return loaded != null && !identical(loaded, entry.value);
        });
    if (stale) {
      _generation = generation;
      _exported.clear();
      _exportedFrom.clear();
    }
  }

  static bool _passes(List<Combinator> combinators, String name) {
    for (final combinator in combinators) {
      final passes = switch (combinator) {
        final ShowCombinator show => show.shownNames.any((n) => n.name == name),
        final HideCombinator hide => !hide.hiddenNames.any(
          (n) => n.name == name,
        ),
      };
      if (!passes) {
        return false;
      }
    }
    return true;
  }

  // The names the library at [path] exports, each with its declaring file.
  Map<String, String> _exportsOf(String path, Set<String> visiting) {
    if (_exported[path] case final known?) {
      return known;
    }
    final file = fileAt(path);
    if (file == null || !visiting.add(path)) {
      return const {};
    }
    final library = _libraryOf(file);
    final names = <String, String>{};
    for (final unit in _unitsOf(library)) {
      for (final node in unit.unit.declarations) {
        if (_declaredName(node) case final name?) {
          names[name] = unit.path;
        }
      }
    }
    for (final directive in library.unit.directives) {
      if (directive is! ExportDirective) {
        continue;
      }
      final target = _uriPath(library, directive.uri.stringValue);
      if (target == null) {
        continue;
      }
      for (final MapEntry(:key, :value) in _exportsOf(
        target,
        visiting,
      ).entries) {
        if (_passes(directive.combinators, key)) {
          names.putIfAbsent(key, () => value);
        }
      }
    }
    _exportedFrom[path] = file;
    return _exported[path] = names;
  }

  DartFile _libraryOf(DartFile file) {
    for (final directive in file.unit.directives) {
      if (directive is PartOfDirective) {
        final path = _uriPath(file, directive.uri?.stringValue);
        return (path == null ? null : fileAt(path)) ?? file;
      }
    }
    return file;
  }

  List<DartFile> _unitsOf(DartFile library) => [
    library,
    for (final directive in library.unit.directives)
      if (directive is PartDirective)
        if (_uriPath(library, directive.uri.stringValue) case final path?)
          ?fileAt(path),
  ];

  String? _uriPath(DartFile from, String? uri) {
    if (uri == null || uri.startsWith('dart:')) {
      return null;
    }
    if (uri.startsWith('package:')) {
      return model.metadataFor(from.path).resolve(uri);
    }
    try {
      return File.fromUri(Uri.file(from.path).resolve(uri)).path;
    } on Object {
      return null;
    }
  }
}
