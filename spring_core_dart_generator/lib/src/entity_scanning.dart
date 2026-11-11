part of 'bean_scanner.dart';

// The classes of spring_boot_starter_data's data layer: the entities
// (`@Table`) and the DTOs its `@Query` methods return. Each gets an
// `EntityIntrospection` (see `EntityModel`) in place of the generic
// `BeanIntrospection`: its properties, and the calls that read, create and
// set an instance, and nothing else. Matched by URL, so the generator does
// not depend on the starter.
//
// The type of a `@Json` property is described for the `ObjectMapper` too,
// the way a controller's body is (its classes of the entity's package,
// written and read): no `@Introspected` to add.
//
// ```dart
// @Table('books')
// class Book { ... }                      // described
//
// abstract interface class BookRepository
//     implements DataRepository<Book, int> {
//   @Query('select title, year from books')
//   Future<List<BookCard>> cards();       // BookCard described too
// }
// ```

const _dataAnnotations =
    'package:spring_boot_starter_data/src/annotations.dart';
const _table = TypeChecker.fromUrl('$_dataAnnotations#Table');
const _transient = TypeChecker.fromUrl('$_dataAnnotations#Transient');
const _query = TypeChecker.fromUrl('$_dataAnnotations#Query');
// `@Json`: the property is one column of JSON, written and read by the
// application's `ObjectMapper`.
const _dataJson = TypeChecker.fromUrl('$_dataAnnotations#Json');
const _aggregateReference = TypeChecker.fromUrl(
  '$_dataAnnotations#AggregateReference',
);

// `Page<T>` and `Slice<T>`: what a paged `@Query` returns.
const _slice = TypeChecker.fromUrl(
  'package:spring_boot_starter_data/src/repository/page.dart#Slice',
);

extension _EntityScanning on BeanScanner {
  /// The `@Query` methods of [repository] and of its supertypes, each with
  /// its annotation; a method overridden further down is read once.
  Iterable<(MethodElement, DartObject)> _queryMethods(
    ClassElement repository,
  ) sync* {
    final names = <String>{};
    for (final type in [
      repository.thisType,
      ...repository.thisType.allSupertypes,
    ]) {
      if (type.element.library.isInSdk) {
        continue;
      }
      for (final method in type.methods) {
        final name = method.name;
        if (method.isStatic || name == null || !names.add(name)) {
          continue;
        }
        if (_query.firstAnnotationOf(method) case final query?) {
          yield (method, query);
        }
      }
    }
  }

  // Whether a `@Query` maps its rows itself, so its result class needs no
  // description.
  bool _mapsItself(ConstantReader query) =>
      query.peek('rowMapper')?.isNull == false ||
      query.peek('resultSetExtractor')?.isNull == false;

  /// The classes a `@Query` method of [repository] turns rows into (a DTO
  /// projection): the class its return type holds, as in
  /// `Future<List<BookCard>>`, `Stream<BookCard>`, `Future<Page<BookCard>>`
  /// or `Future<BookCard?>`. Not an entity, not an `AggregateReference`, not
  /// a class of the SDK (a column: `Future<int>`, `Future<String>`), and
  /// not one a `rowMapper` or `resultSetExtractor` builds.
  Iterable<ClassElement> projectionsOf(ClassElement repository) sync* {
    for (final (method, query) in _queryMethods(repository)) {
      if (_mapsItself(ConstantReader(query))) {
        continue;
      }
      if (_projectionOf(method.returnType) case final projection?) {
        yield projection;
      }
    }
    for (final (method, _) in _procedureMethods(repository)) {
      if (_projectionOf(method.returnType) case final projection?) {
        yield projection;
      }
    }
  }

  ClassElement? _projectionOf(DartType returned) {
    var type = returned;
    // The wrappers around the class: futures, streams, collections, pages.
    while (type is InterfaceType &&
        type.typeArguments.length == 1 &&
        (type.isDartAsyncFuture ||
            type.isDartAsyncFutureOr ||
            type.isDartAsyncStream ||
            type.isDartCoreList ||
            type.isDartCoreSet ||
            type.isDartCoreIterable ||
            _slice.isAssignableFromType(type))) {
      type = type.typeArguments.single;
    }
    return switch (type) {
      InterfaceType(:final ClassElement element)
          when !element.library.isInSdk &&
              !_table.hasAnnotationOf(element) &&
              !_aggregateReference.isExactly(element) =>
        element,
      _ => null,
    };
  }

  /// What the `@Query` methods of [repository] need from the build: the
  /// description of their DTOs. (The classes of the arguments of a method
  /// whose `:#{...}` expressions the starter interprets are described for
  /// SpEL once every expression is known, see `_checkQueries`.)
  void scanQueries(ClassElement repository) {
    for (final (method, query) in _queryMethods(repository)) {
      final reader = ConstantReader(query);
      if (_mapsItself(reader)) {
        continue;
      }
      if (_projectionOf(method.returnType) case final projection?) {
        scanEntity(projection, returnedBy: '${repository.name}.${method.name}');
      }
    }
    // The rows of a database function (`@Procedure`) become objects the same
    // way.
    for (final (method, _) in _procedureMethods(repository)) {
      if (_projectionOf(method.returnType) case final projection?) {
        scanEntity(projection, returnedBy: '${repository.name}.${method.name}');
      }
    }
  }

  /// Adds the description of [element], a `@Table` class, or when
  /// [returnedBy] (the `@Query` method) is given, a DTO that method
  /// returns. Each class is described once.
  ///
  /// The class needs a public unnamed constructor; every parameter of it
  /// takes the value of the field of the same name, which must be
  /// assignable to the parameter. A field no parameter takes needs a setter
  /// (or `@Transient`): reading a row has no other way to give it its
  /// value. A getter written out (`bool get isNew => id == null`) computes
  /// its value and is no property, unless a parameter takes its name.
  void scanEntity(ClassElement element, {String? returnedBy}) {
    if (!_entityClasses.add(element)) {
      return;
    }
    final name = _requireName(element);
    final what = returnedBy == null
        ? '@Table class $name'
        : 'Class $name (read by the @Query method $returnedBy)';
    // Names a DTO's origin in front of the problems of its members.
    final context = returnedBy == null ? '' : '$what: ';
    if (element.isPrivate) {
      BeanScanner._fail(
        '$what must be public: the generated code cannot name it. '
        'Make it public.',
        element,
      );
    }
    if (element.isAbstract) {
      BeanScanner._fail(
        '$what is abstract: rows cannot be turned into an instance of it. '
        'Make it a concrete class.',
        element,
      );
    }
    if (element.typeParameters.isNotEmpty) {
      BeanScanner._fail(
        '$what is generic, which is not supported: remove its type '
        'parameters.',
        element,
      );
    }
    final constructor = element.unnamedConstructor;
    if (constructor == null || constructor.isPrivate) {
      BeanScanner._fail(
        '$what has no public unnamed constructor, which the data layer '
        'calls to create an instance. Add one, such as '
        '$name({this.id, required this.title}).',
        element,
      );
    }
    final type = element.thisType;
    final parameters = {
      for (final parameter in constructor.formalParameters)
        ?parameter.name: parameter,
    };
    final properties = <EntityPropertyModel>[];
    for (final field in _describedFields(_describedClasses(element))) {
      final fieldName = field.name!;
      final parameter = parameters[fieldName];
      final writable = field.setter != null;
      if (field.isOriginGetterSetter && !writable && parameter == null) {
        // A computed getter (`hashCode`, `isNew`): nothing is stored.
        continue;
      }
      final annotations = [
        ..._userAnnotations(field),
        if (field.getter case final getter?) ..._userAnnotations(getter),
      ];
      if (!writable &&
          parameter == null &&
          !annotations.any((a) => _transient.isAssignableFromType(a.type!))) {
        BeanScanner._fail(
          '$context$name.$fieldName is final and no parameter of the '
          'constructor takes it, so nothing could set it when reading a '
          'row. Make it a constructor parameter (this.$fieldName), make it '
          'non-final (so it has a setter), or mark it @Transient.',
          field,
        );
      }
      if (annotations.any((a) => _dataJson.isExactlyType(a.type!))) {
        // The mapper writes the value into the column and reads it back.
        _introspectUsed(
          _fieldType(element, field),
          element,
          need: IntrospectionNeed.read | IntrospectionNeed.write,
        );
      }
      final initial = initialValueOf(field);
      DartObject? parameterDefault;
      if (parameter != null && parameter.hasDefaultValue) {
        parameterDefault = parameter.computeConstantValue();
        if (initial == null &&
            parameterDefault != null &&
            !_isRecreatable(parameterDefault)) {
          BeanScanner._fail(
            '$context$name.$fieldName: the default of the constructor '
            'parameter $fieldName cannot be written by the build, so a row '
            'without a value for it would not get that default. Make the '
            'constant public, or give the field an initializer.',
            parameter,
          );
        }
      }
      properties.add(
        EntityPropertyModel(
          name: fieldName,
          type: _fieldType(element, field),
          annotations: annotations,
          parameter: parameter != null,
          writable: writable,
          defaultValue:
              initial ??
              (parameterDefault == null ? null : (value: parameterDefault)),
        ),
      );
    }
    final indexes = {
      for (final (index, property) in properties.indexed) property.name: index,
    };
    final arguments = <EntityArgument>[];
    // An optional positional parameter that names no field is left out; a
    // later positional one could then not be passed.
    String? skipped;
    for (final parameter in constructor.formalParameters) {
      final parameterName = _requireName(parameter);
      final index = indexes[parameterName];
      if (index == null) {
        if (parameter.isRequired) {
          BeanScanner._fail(
            '$context$name($parameterName): the constructor parameter '
            '$parameterName names no field, so no column could give it a '
            'value. Name a field $parameterName (this.$parameterName), or '
            'make the parameter optional.',
            parameter,
          );
        }
        if (parameter.isPositional) {
          skipped ??= parameterName;
        }
        continue;
      }
      if (parameter.isPositional && skipped != null) {
        BeanScanner._fail(
          '$context$name($parameterName): the optional positional parameter '
          '$skipped names no field, but $parameterName, after it, does: '
          'the data layer cannot leave $skipped out. Make them named '
          'parameters, or name $skipped after a field.',
          parameter,
        );
      }
      // The data layer passes the value of the property as it is, so it
      // must fit the parameter (`Link({required String url}) : url =
      // Uri.parse(url)` does not take a `Uri`).
      final propertyType = properties[index].type;
      if (!element.library.typeSystem.isAssignableTo(
        propertyType,
        parameter.type,
      )) {
        BeanScanner._fail(
          '$context$name($parameterName): the constructor parameter has '
          'the type ${parameter.type.getDisplayString()}, but the field '
          '$parameterName has the type ${propertyType.getDisplayString()}, '
          'and the data layer passes the value of the field as it is. Give '
          'the parameter the type of the field (this.$parameterName) and '
          'convert in a named constructor or a factory instead.',
          parameter,
        );
      }
      arguments.add(
        EntityArgument(index, name: parameter.isNamed ? parameterName : null),
      );
    }
    module.entities.add(
      EntityModel(
        element: element,
        type: type,
        properties: properties,
        arguments: arguments,
        annotations: _userAnnotations(element),
      ),
    );
  }

  // The declared type of [field] as [element] sees it: the type arguments
  // of a generic superclass are put in (`Base<T>.tags`, a `List<T>`, of
  // `Author extends Base<String>` is a `List<String>`).
  DartType _fieldType(ClassElement element, FieldElement field) =>
      element.thisType.lookUpGetter(field.name!, element.library)?.returnType ??
      field.type;
}
