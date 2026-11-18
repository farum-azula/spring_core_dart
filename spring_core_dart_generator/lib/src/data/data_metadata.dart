part of 'bean_scanner.dart';

// What the editors need of the data layer, for `spring_metadata.json`: the
// entities (`@Table` classes) with their tables, columns and relations, and
// the repositories with their methods. Read from the same models the data
// generator writes its code from (`EntityModel`, `RepositoryModel`), so
// the editor and the build agree. See `roadmap/spring_metadata.md`.
//
// ```json
// { "class": "Book", "table": "books", "id": "id",
//   "properties": [{ "name": "author", "column": "author",
//     "relation": { "entity": "Author", "id": "int" } }] }
// ```

const _idAnnotation = TypeChecker.fromUrl('$_dataAnnotations#Id');
const _referenceAnnotation = TypeChecker.fromUrl(
  '$_dataAnnotations#Reference',
);

/// The data layer's part of `spring_metadata.json`.
extension DataMetadata on BeanScanner {
  /// The `entities` of the metadata: the `@Table` classes scanned so far.
  ///
  /// `table` and every `column` are the names the entity spells out or the
  /// default naming gives; they are `null` when the application declares its
  /// own `NamingStrategy` (the build cannot know them then).
  List<Map<String, Object?>> entityMetadata() {
    final customNaming = module.beans.any(
      (bean) => _namingStrategy.isAssignableFromType(bean.type),
    );
    return [
      for (final entity in module.entities)
        if (_table.hasAnnotationOf(entity.element))
          _entityEntry(entity, customNaming),
    ];
  }

  Map<String, Object?> _entityEntry(EntityModel entity, bool customNaming) {
    final description = _entityDescription(entity);
    final element = entity.element;
    String? id;
    final properties = <Map<String, Object?>>[];
    for (final (index, property) in entity.properties.indexed) {
      final described = description.properties[index];
      final isId = property.annotations.any(
        (a) => a.type != null && _idAnnotation.isAssignableFromType(a.type!),
      );
      if (isId) {
        id = property.name;
      }
      // The field, in the class that declares it (a superclass may).
      final getter = element.thisType.lookUpGetter(
        property.name,
        element.library,
      );
      final declared = getter?.variable ?? getter;
      final column =
          described.column ??
          (customNaming ? null : DataSchema.snakeCase(property.name));
      properties.add({
        'name': property.name,
        'type': property.type.getDisplayString(),
        'kind': described.kind.name,
        'column': described.kind == EntityPropertyKind.column ? column : null,
        'relation': _relation(property),
        'source': declared == null ? null : sourceOf(declared),
        'line': declared == null ? null : lineOf(declared),
      });
    }
    return {
      'class': element.name,
      'table':
          description.table ??
          (customNaming ? null : DataSchema.snakeCase(description.className)),
      'source': sourceOf(element),
      'line': lineOf(element),
      'id': id,
      'properties': properties,
    };
  }

  // The aggregate a property references: `AggregateReference<Author, int>`
  // or an id marked `@Reference(Author)`.
  Map<String, Object?>? _relation(EntityPropertyModel property) {
    final type = property.type;
    if (type is InterfaceType) {
      for (final candidate in [type, ...type.allSupertypes]) {
        if (_aggregateReference.isExactlyType(candidate) &&
            candidate.typeArguments.length == 2) {
          return {
            'entity': candidate.typeArguments[0].element?.name,
            'id': candidate.typeArguments[1].getDisplayString(),
          };
        }
      }
    }
    for (final annotation in property.annotations) {
      if (annotation.type != null &&
          _referenceAnnotation.isAssignableFromType(annotation.type!)) {
        final target = annotation.getField('target')?.toTypeValue();
        return {
          'entity': target?.element?.name,
          'id': type.getDisplayString().replaceAll('?', ''),
        };
      }
    }
    return null;
  }

  /// The `repositories` of the metadata: the repository interfaces scanned
  /// so far, with the methods the generated class writes (the CRUD ones the
  /// starter implements are not listed).
  List<Map<String, Object?>> repositoryMetadata() {
    final result = <Map<String, Object?>>[];
    for (final bean in module.beans) {
      final creation = bean.creation;
      if (creation is! RepositoryCreation) {
        continue;
      }
      final model = creation.model;
      final element = model.type.element;
      result.add({
        'name': element.name,
        'entity': model.entityType.element.name,
        'id': model.idType.getDisplayString(),
        'source': sourceOf(element),
        'line': lineOf(element),
        'methods': [
          for (final method in model.methods) _methodEntry(model, method),
        ],
      });
    }
    result.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return result;
  }

  Map<String, Object?> _methodEntry(
    RepositoryModel repository,
    RepositoryMethodModel method,
  ) {
    final member = method.member;
    final declared = repository.type.lookUpMethod(
      member.name,
      repository.type.element.library,
    );
    String? sql;
    String? count;
    if (method is QueryMethodModel) {
      final reader = ConstantReader(method.query);
      sql = reader.peek('value')?.stringValue;
      final countQuery = reader.peek('countQuery');
      count = countQuery != null && countQuery.isString
          ? countQuery.stringValue
          : null;
    }
    return {
      'name': member.name,
      'kind': switch (method) {
        QueryMethodModel() => 'query',
        ProcedureMethodModel() => 'procedure',
        DerivedMethodModel() => 'derived',
        LockedMethodModel() => 'locked',
      },
      'query': sql,
      'countQuery': count,
      'parameters': [
        for (final parameter in member.parameters)
          {'name': parameter.name, 'type': parameter.type.getDisplayString()},
      ],
      'returns': member.returnType.getDisplayString(),
      'line': declared == null ? null : lineOf(declared),
    };
  }
}
