import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/metadata.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:spring_core_dart_generator/query_syntax.dart';

/// A stored property of an [EntityView]: where it is declared, its column,
/// and what it references.
final class PropertyView implements PartTreeProperty {
  /// A property read from the source (with [path] and [offset]) or from the
  /// metadata ([source] and [line]).
  PropertyView({
    required this.name,
    required this.type,
    required this.kind,
    this.column,
    this.relationEntity,
    this.relationId,
    this.path,
    this.offset,
    this.source,
    this.line,
  });

  @override
  final String name;

  /// The declared type as written.
  final String type;

  /// `column`, `transient` or `collection`.
  final String kind;

  /// The column's name; `null` when the naming strategy of the application
  /// decides and no `@Column` names it.
  final String? column;

  /// The entity this property references, and the type of its id.
  final String? relationEntity;

  /// The type of the referenced entity's id.
  final String? relationId;

  /// Where the field is in the workspace: the file and the offset of its
  /// name.
  final String? path;

  /// The offset of the field's name in [path].
  final int? offset;

  /// Where the metadata says it is: a `package:` URI and a one-based line.
  final String? source;

  /// The one-based line of the field in [source].
  final int? line;

  @override
  bool get isMappedCollection => kind == 'collection';

  @override
  bool get isString => type.replaceAll('?', '') == 'String';

  /// Whether the property has a column of the entity's own table.
  bool get isColumn => kind == 'column';
}

/// A `@Table` class as the editor sees it: the properties of the source
/// (live) and of the metadata (what the last build saw), merged.
final class EntityView implements PartTreeEntity {
  /// An entity called [name].
  EntityView({
    required this.name,
    required this.properties,
    required this.complete,
    this.table,
    this.id,
    this.path,
    this.offset,
    this.source,
    this.line,
  });

  @override
  final String name;

  /// The stored properties, collections included, transients left out.
  @override
  final List<PropertyView> properties;

  /// Whether [properties] are all of them: false when a superclass the
  /// editor cannot see may add more, so nothing is said about a name it
  /// lacks.
  final bool complete;

  /// The table's name; `null` when the naming strategy decides.
  final String? table;

  /// The name of the `@Id` property.
  final String? id;

  /// The class in the workspace: its file and the offset of its name.
  final String? path;

  /// The offset of the class name in [path].
  final int? offset;

  /// The class in the metadata: a `package:` URI and a one-based line.
  final String? source;

  /// The one-based line of the class in [source].
  final int? line;

  /// Properties that are not stored (`@Transient`), by name; `{Book.x}` is
  /// an error for them but they are not unknown.
  final transients = <String>{};

  @override
  PropertyView? property(String name) {
    for (final property in properties) {
      if (property.name == name) {
        return property;
      }
    }
    return null;
  }

  @override
  Iterable<PropertyView> get columns => properties.where((p) => p.isColumn);
}

/// What the editor knows of the data layer of a project: its entities and
/// repositories, from the source and from the Spring metadata.
///
/// The source is read as syntax only, so it answers at once when you type
/// (a new field, a renamed class), before the next build; the metadata
/// adds the column names the naming strategy gives and the entities of
/// dependencies. Where they disagree the source wins and nothing from the
/// metadata that the source lost is kept.
final class DataModel {
  /// A model over [workspace].
  DataModel(this.workspace);

  /// The workspace whose classes and metadata are used.
  final SpringWorkspace workspace;

  /// The class of a `@Table` entity called [name], seen from the file
  /// [path]: the one in that file first, then one in the same package,
  /// then any. A workspace holds many classes of the same name (tests and
  /// examples of other packages each have their `Book`).
  ClassInfo? _sourceClass(String name, String path) {
    final root = workspace.metadataFor(path).packageRoot;
    int rank(ClassInfo info) => info.path == path
        ? 0
        : root != null && info.path.startsWith('$root/')
        ? 1
        : 2;
    final candidates = [
      for (final info in workspace.classesNamed(name))
        if (info.annotationNames.contains('Table')) info,
    ]..sort((a, b) => rank(a) - rank(b));
    return candidates.firstOrNull;
  }

  /// Whether a class called [name] is declared in the workspace (with or
  /// without `@Table`).
  bool classExists(String name) => workspace.classesNamed(name).isNotEmpty;

  /// The names of every entity visible from the file [path].
  List<String> entityNames(String path) => {
    for (final entity in workspace.metadataFor(path).entities) entity.className,
    for (final info in workspace.allClasses)
      if (info.annotationNames.contains('Table')) info.name,
  }.toList()..sort();

  /// The entity called [name], seen from the file [path]; `null` when there
  /// is none.
  EntityView? entity(String name, String path) {
    final source = _sourceClass(name, path);
    MetaEntity? meta;
    for (final candidate in workspace.metadataFor(path).entities) {
      if (candidate.className == name) {
        meta = candidate;
        break;
      }
    }
    if (source == null && meta == null) {
      return null;
    }
    if (source == null) {
      return _fromMetadata(meta!);
    }
    final fromSource = _fromSource(source);
    if (meta == null) {
      return fromSource;
    }
    // The metadata knows the names the naming strategy gave.
    final byName = {for (final p in meta.properties) p.name: p};
    final merged = <PropertyView>[
      for (final property in fromSource.properties)
        if (byName[property.name] case final known?)
          PropertyView(
            name: property.name,
            type: property.type,
            kind: property.kind,
            column: property.column ?? known.column,
            relationEntity: property.relationEntity ?? known.relationEntity,
            relationId: property.relationId ?? known.relationId,
            path: property.path,
            offset: property.offset,
            source: known.source,
            line: known.line,
          )
        else
          property,
      // What the source cannot see (a superclass of a dependency) the
      // metadata may have.
      if (!fromSource.complete)
        for (final known in meta.properties)
          if (fromSource.property(known.name) == null &&
              known.kind != 'transient')
            _metaProperty(known),
    ];
    final view = EntityView(
      name: name,
      properties: merged,
      complete: fromSource.complete || meta.properties.isNotEmpty,
      table: fromSource.table ?? meta.table,
      id: fromSource.id ?? meta.id,
      path: fromSource.path,
      offset: fromSource.offset,
      source: meta.source,
      line: meta.line,
    );
    view.transients.addAll(fromSource.transients);
    return view;
  }

  PropertyView _metaProperty(MetaEntityProperty p) => PropertyView(
    name: p.name,
    type: p.type,
    kind: p.kind,
    column: p.column,
    relationEntity: p.relationEntity,
    relationId: p.relationId,
    source: p.source,
    line: p.line,
  );

  EntityView _fromMetadata(MetaEntity meta) {
    final view = EntityView(
      name: meta.className,
      properties: [
        for (final p in meta.properties)
          if (p.kind != 'transient') _metaProperty(p),
      ],
      complete: true,
      table: meta.table,
      id: meta.id,
      source: meta.source,
      line: meta.line,
    );
    for (final p in meta.properties) {
      if (p.kind == 'transient') {
        view.transients.add(p.name);
      }
    }
    return view;
  }

  // The entity of a class in the workspace: the fields of the class and of
  // the superclasses and mixins the workspace has. A class with a
  // supertype it cannot see is not complete.
  EntityView _fromSource(ClassInfo info) {
    final properties = <PropertyView>[];
    final transients = <String>{};
    var complete = true;
    String? id;
    final seen = <String>{};
    void collect(ClassInfo current) {
      if (!seen.add('${current.path}#${current.name}')) {
        return;
      }
      final declaration = current.declaration;
      for (final member in declaration.body.members) {
        if (member is! FieldDeclaration ||
            member.isStatic ||
            member.fields.isConst) {
          continue;
        }
        for (final variable in member.fields.variables) {
          final name = variable.name.lexeme;
          if (name.startsWith('_') ||
              properties.any((p) => p.name == name) ||
              transients.contains(name)) {
            continue;
          }
          final annotationNames = {
            for (final a in member.metadata) annotationName(a),
          };
          if (annotationNames.contains('Transient')) {
            transients.add(name);
            continue;
          }
          final type = member.fields.type?.toSource() ?? 'dynamic';
          Annotation? annotation(String n) =>
              member.metadata.where((a) => annotationName(a) == n).firstOrNull;
          if (annotationNames.contains('Id')) {
            id ??= name;
          }
          var relationEntity = _referenceOf(type);
          String? relationId;
          if (relationEntity != null) {
            relationId = type
                .replaceFirst(RegExp('^[^<]*<'), '')
                .replaceFirst(RegExp(r'>\??$'), '')
                .split(',')
                .last
                .trim();
          } else if (annotation('Reference') case final reference?) {
            relationEntity = switch (positionalArgument(reference)) {
              final SimpleIdentifier target => target.name,
              _ => null,
            };
            relationId = type.replaceAll('?', '');
          }
          final columnAnnotation = annotation('Column');
          final column = columnAnnotation == null
              ? DataSchema.snakeCase(name)
              : stringValue(positionalArgument(columnAnnotation));
          properties.add(
            PropertyView(
              name: name,
              type: type,
              kind: annotationNames.contains('MappedCollection')
                  ? 'collection'
                  : 'column',
              column: column,
              relationEntity: relationEntity,
              relationId: relationId,
              path: current.path,
              offset: variable.name.offset,
            ),
          );
        }
      }
      // A superclass or a mixin the workspace does not have may add fields
      // (an `implements` interface adds none).
      final parents = <String>{
        if (declaration.extendsClause case final clause?)
          clause.superclass.name.lexeme,
        for (final type in declaration.withClause?.mixinTypes ?? <NamedType>[])
          type.name.lexeme,
      };
      for (final parent in parents) {
        final classes = workspace.classesNamed(parent);
        if (classes.isNotEmpty) {
          collect(classes.first);
        } else if (parent != 'Object') {
          complete = false;
        }
      }
    }

    collect(info);
    final table = _tableOf(info);
    return EntityView(
      name: info.name,
      properties: properties,
      complete: complete,
      table: table,
      id: id,
      path: info.path,
      offset: info.nameOffset,
    )..transients.addAll(transients);
  }

  // `@Table('books')`, else the class name in snake case.
  static String _tableOf(ClassInfo info) {
    for (final annotation in info.annotations) {
      if (annotationName(annotation) == 'Table') {
        if (stringValue(positionalArgument(annotation)) case final name?) {
          return name;
        }
      }
    }
    return DataSchema.snakeCase(info.name);
  }

  // `AggregateReference<Author, int>?` references `Author`.
  static String? _referenceOf(String type) {
    final match = RegExp(
      r'^AggregateReference\s*<\s*(\w+)\s*,',
    ).firstMatch(type);
    return match?.group(1);
  }

  /// The entity of the repository interface [declaration] in the file
  /// [path]: the metadata knows it by the interface's name; else the type
  /// arguments of the repository interface it implements
  /// (`ListCrudRepository<Book, int>`), through the repositories of the
  /// workspace.
  String? entityOf(ClassDeclaration declaration, String path) {
    final name = declaration.namePart.typeName.lexeme;
    for (final repository in workspace.metadataFor(path).repositories) {
      if (repository.name == name) {
        return repository.entity;
      }
    }
    return _entityOfTypes(declaration, <String>{});
  }

  String? _entityOfTypes(ClassDeclaration declaration, Set<String> seen) {
    final types = <NamedType>[
      ...?declaration.implementsClause?.interfaces,
      if (declaration.extendsClause case final clause?) clause.superclass,
    ];
    for (final type in types) {
      final arguments = type.typeArguments?.arguments ?? const [];
      if (arguments.length == 2 && type.name.lexeme.endsWith('Repository')) {
        if (arguments.first is NamedType) {
          return (arguments.first as NamedType).name.lexeme;
        }
      }
    }
    for (final type in types) {
      if (!seen.add(type.name.lexeme)) {
        continue;
      }
      for (final parent in workspace.classesNamed(type.name.lexeme)) {
        if (_entityOfTypes(parent.declaration, seen) case final found?) {
          return found;
        }
      }
    }
    return null;
  }

  /// Where the class of [entity] is: the workspace's declaration, else the
  /// line the metadata names.
  List<SourceRange> locate(EntityView entity, String from) {
    if (entity.path != null && entity.offset != null) {
      if (workspace.file(entity.path!) case final file?) {
        return [
          workspace.rangeOf(
            file,
            entity.offset!,
            entity.offset! + entity.name.length,
          ),
        ];
      }
    }
    return _metaRange(entity.source, entity.line, from);
  }

  /// Where the field of [property] is, as [locate].
  List<SourceRange> locateProperty(PropertyView property, String from) {
    if (property.path != null && property.offset != null) {
      if (workspace.file(property.path!) case final file?) {
        return [
          workspace.rangeOf(
            file,
            property.offset!,
            property.offset! + property.name.length,
          ),
        ];
      }
    }
    return _metaRange(property.source, property.line, from);
  }

  List<SourceRange> _metaRange(String? source, int? line, String from) {
    final path = workspace.metadataFor(from).resolve(source);
    if (path == null || line == null) {
      return const [];
    }
    final row = line > 0 ? line - 1 : 0;
    return [SourceRange(path, row, 0, row, 0)];
  }
}
