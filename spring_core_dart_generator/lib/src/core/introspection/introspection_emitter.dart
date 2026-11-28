import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/builder/code_writer.dart';
import 'package:spring_core_dart_generator/src/core/introspection/introspection_model.dart';
import 'package:spring_core_dart_generator/src/core/introspection/json_annotation_checker.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_emitter.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_model.dart';

// Runtime types are always imported from the public library, never from
// `src/`.
const _springUrl = 'package:spring_core_dart/spring_core_dart.dart';

// A reference to a public runtime type, e.g. `Introspection`.
Reference _spring(String name) => refer(name, _springUrl);

/// A raw string literal of [value], so `$` and backslashes in names are
/// written as they are.
Expression _str(String value) => literalString(value, raw: true);

/// Writes the descriptions of a module's classes ([IntrospectionModel]s)
/// as `Introspection` instances, with only the parts the build saw used
/// ([IntrospectionModel.need]), and the type descriptions (`TypeInfo`)
/// other generated code writes too.
///
/// It names what it uses through the [CodeWriter] of the library the
/// descriptions go into: the module's `<library>.spring.introspection.dart`,
/// and its `<library>.spring.properties.dart` for the descriptions only the
/// binder of `@ConfigurationProperties` classes uses (see [onlyForBinding]);
/// the module's own library writes the `TypeInfo` instances of its beans'
/// methods with one of its own. [library] writes such a library.
///
/// ```dart
/// // Input:
/// @Introspected()
/// class Form {
///   @NotBlank()
///   String name = '';
/// }
/// // Output (beans.spring.introspection.dart):
/// Object? _$get0(Form object) => object.name;
/// void _$set1(Form object, Object? value) => object.name = (value as String);
///
/// List<Introspection<Object>> get $appBeansIntrospections => [
///   const Introspection<Form>(
///     className: r'Form',
///     properties: [
///       IntrospectedProperty<Form>(r'name', typeInfo: ClassType<String>(),
///           hasInitialValue: true, initialValue: r'', get: _$get0,
///           set: _$set1, annotations: [NotBlank()]),
///     ],
///     instantiate: Form.new,
///   ),
/// ];
/// ```
///
/// Spring (Java): no counterpart; Spring reflects over any class on demand
/// (Spring 6 AOT registers reflection hints instead, `RuntimeHintsRegistrar`).
final class IntrospectionEmitter {
  /// An emitter naming what it writes through [_writer].
  IntrospectionEmitter(this._writer);

  final CodeWriter _writer;

  // The object methods' code, through the same writer.
  late final _objectMethods = ObjectMethodsEmitter(_writer);

  /// The declarations the object methods' annotations of [models] (the
  /// classes this library describes, in its order) give the library: the
  /// `copyWith` types and extensions (see
  /// [ObjectMethodsEmitter.declarations]).
  List<Spec> objectMethodDeclarations(List<ObjectMethodsModel> models) =>
      _objectMethods.declarations(models);

  /// The source of the generated library [_writer] writes: the functions the
  /// descriptions declared, then the getter [getter] returning
  /// [descriptions] (made by [introspection]), documented by [doc], then
  /// [declarations] (those of [objectMethodDeclarations]). A getter, as the
  /// module's, so that after a hot reload the module gets the descriptions
  /// of the new code.
  ///
  /// ```dart
  /// List<Introspection<Object>> get $appBeansIntrospections => [...];
  /// ```
  String library({
    required String getter,
    required String doc,
    required List<Expression> descriptions,
    List<Spec> declarations = const [],
  }) => _writer.source(
    Library(
      (b) => b
        ..body.addAll(_writer.topLevelDeclarations)
        ..body.add(
          Method(
            (m) => m
              ..docs.add(doc)
              ..type = MethodType.getter
              ..returns = TypeReference(
                (t) => t
                  ..symbol = 'List'
                  ..types.add(
                    TypeReference(
                      (t) => t
                        ..symbol = 'Introspection'
                        ..url = _springUrl
                        ..types.add(refer('Object')),
                    ),
                  ),
              )
              ..name = getter
              ..lambda = true
              ..body = literalList(descriptions).code,
          ),
        )
        ..body.addAll(declarations),
    ),
  );

  /// The `Introspection<T>` of [model], with typed getter/setter closures
  /// and `Function.apply` for methods: reflection-like access without
  /// mirrors.
  ///
  /// A generic class `Page<T>` is written with `T` erased
  /// (`Introspection<Page<dynamic>>`), plus, when its type parameters
  /// have no bounds, `specialize`: the introspection of `Page<X>` for the
  /// `TypeInfo` instances of the type arguments, captured as type parameters:
  ///
  /// ```dart
  /// specialize: (arguments) => arguments[0].capture(
  ///     <T>() => Introspection<Page<T>>(...,
  ///         typeInfo: ListType<T>(arguments[0] as TypeInfo<T>))),
  /// ```
  Expression introspection(IntrospectionModel model) {
    final parameters = model.type.element.typeParameters;
    if (parameters.isEmpty) {
      return _introspectionOf(model);
    }
    Expression? specialize;
    if (parameters.every((p) => p.bound == null)) {
      _writer.capturedTypeParameters = {
        for (var i = 0; i < parameters.length; i++) parameters[i]: i,
      };
      var body = _introspectionOf(model);
      _writer.capturedTypeParameters = const {};
      for (var i = parameters.length - 1; i >= 0; i--) {
        // A generic function literal (`Method.closure` drops type
        // parameters).
        final captured = CodeExpression(
          Block.of([Code('<${parameters[i].name}>() => '), body.code]),
        );
        body = refer('arguments')
            .index(literalNum(i))
            .property('capture')
            .call([captured]);
      }
      specialize = _writer.closure(['arguments'], body.code, lambda: true);
    }
    _writer.erasedTypeParameters = {
      for (final parameter in parameters) parameter: parameter.bound,
    };
    final raw = _introspectionOf(model, specialize: specialize);
    _writer.erasedTypeParameters = const {};
    return raw;
  }

  // A generic class is created by calling its constructor, not with
  // `Function.apply(Page<T>.new, ...)`: dart2js cannot apply named
  // arguments to an instantiated tear-off. Absent optional parameters get
  // their default values, so all of them must be re-creatable.
  //
  // ```dart
  // create: (positional, named) => Page<T>((positional[0] as List<T>),
  //     total: named.containsKey(#total) ? (named[#total] as int) : 0),
  // ```
  //
  // Classes without type parameters are created the same way, which the
  // compilers can inline and type (`Function.apply` is a dynamic call);
  // `null` when an argument cannot be written that way.
  Expression? _directCall(
    IntrospectionModel model,
    ConstructorModel constructor,
    TypeReference describedType,
  ) {
    final arguments = directArguments(
      constructor.parameters,
      model.element,
      positional: refer('positional'),
      named: refer('named'),
    );
    if (arguments == null) {
      return null;
    }
    final (positional, named) = arguments;
    return constructor.name.isEmpty
        ? describedType.newInstance(positional, named)
        : describedType.newInstanceNamed(constructor.name, positional, named);
  }

  /// The arguments of a direct call to a function with [parameters]
  /// (declared by [element]), read from the lists [positional] and [named]
  /// (by symbol) the way `Function.apply` would pass them: an absent
  /// optional argument gets the parameter's default value. `null` when a
  /// default value or a type cannot be written (a private constant or
  /// type); the caller then keeps `Function.apply`. Without [named] (no
  /// named arguments are passed) an optional named parameter gets its
  /// default value, and a required one makes the call impossible (`null`).
  ///
  /// ```dart
  /// (positional[0] as List<T>), total: named.argumentOr(#total, 0)
  /// ```
  ///
  /// `argumentOr` (the runtime's `NamedArguments` /
  /// `PositionalArguments`) takes its type from the parameter.
  (List<Expression>, Map<String, Expression>)? directArguments(
    List<ConstructorParameterModel> parameters,
    Element element, {
    required Expression positional,
    required Expression? named,
  }) {
    if (parameters.any(
      (p) =>
          (p.hasDefault && p.defaultValue == null) ||
          (named == null && p.isNamed && p.isRequired) ||
          _writer.hasFreeTypeParameter(p.type),
    )) {
      return null;
    }
    final positionalArguments = <Expression>[];
    final namedArguments = <String, Expression>{};
    final types = Map.of(_writer.annotationTypes);
    try {
      for (final parameter in parameters) {
        final type = _writer.anyType(parameter.type, element);
        final fallback = parameter.defaultValue == null
            ? literalNull
            : _writer.constant(parameter.defaultValue!, element);
        if (parameter.isNamed) {
          if (named == null) {
            // Left out, so it gets its default.
            continue;
          }
          final key = CodeExpression(Code('#${parameter.name}'));
          namedArguments[parameter.name] = parameter.isRequired
              ? named.index(key).asA(type)
              : named.property('argumentOr').call([key, fallback]);
        } else {
          final index = literalNum(positionalArguments.length);
          positionalArguments.add(
            parameter.isRequired
                ? positional.index(index).asA(type)
                : positional.property('argumentOr').call([index, fallback]),
          );
        }
      }
    } on InvalidGenerationSource {
      // What `_writer.constant` recorded for the abandoned arguments.
      _writer.annotationTypes
        ..clear()
        ..addAll(types);
      return null;
    }
    return (positionalArguments, namedArguments);
  }

  // [type] as [_writer.anyType] writes it, its free type parameters (see
  // [_writer.hasFreeTypeParameter]) written as `Object?`, at any depth:
  // `List<E>` of a method of `Crud<E>` described for `BookCrud` is a
  // `List<Object?>`, `Map<String, List<E>>` a
  // `Map<String, List<Object?>>`. A function or record type that uses one
  // is an `Object?` as a whole.
  Reference _withoutFree(DartType type, Element element) => switch (type) {
    _ when !_writer.hasFreeTypeParameter(type) => _writer.anyType(
      type,
      element,
    ),
    InterfaceType() =>
      _writer
          .classType(type, element)
          .rebuild(
            (t) => t
              ..types.clear()
              ..types.addAll([
                for (final argument in type.typeArguments)
                  _withoutFree(argument, element),
              ]),
          ),
    _ => CodeWriter.objectOrNull,
  };

  // The methods to describe: all of them when expressions may call them,
  // else those a JSON annotation makes part of writing (`@JsonValue`,
  // `@JsonAnyGetter`) or reading (`@JsonAnySetter`) the class out or in.
  List<IntrospectionMethodModel> _methodsOf(IntrospectionModel model) {
    final need = model.need;
    if (need.includes(IntrospectionNeed.methods)) {
      return model.methods;
    }
    return [
      for (final method in model.methods)
        if (method.jsonNeed.intersects(need)) method,
    ];
  }

  Expression _introspectionOf(
    IntrospectionModel model, {
    Expression? specialize,
  }) {
    final element = model.element;
    final describedType = _writer.classType(model.type, element);
    // Only the parts of the class the build saw used (IntrospectionNeed).
    final need = model.need;
    final reads = need.includes(IntrospectionNeed.read);
    final writes = need.includes(IntrospectionNeed.write);
    final validates = need.includes(IntrospectionNeed.validate);
    final calls = need.includes(IntrospectionNeed.methods);
    // A class without type parameters is described by a constant: its
    // closures become top-level functions.
    final constant =
        _writer.erasedTypeParameters.isEmpty &&
        _writer.capturedTypeParameters.isEmpty;
    final properties = [
      for (final property
          in need.isNone
              ? const <IntrospectionPropertyModel>[]
              : model.properties)
        _property(
          model,
          property,
          describedType,
          constant: constant,
          reads: reads,
          writes: writes,
          validates: validates,
        ),
    ];
    // A closure, or in a constant a top-level function `_$<kind><n>`.
    Expression function(
      String kind,
      Reference returns,
      List<(String, Reference)> parameters,
      Code body,
    ) => constant
        ? _writer.topLevelFunction(kind, returns, parameters, body)
        : _writer.closure(
            [for (final (name, _) in parameters) name],
            body,
            lambda: true,
          );
    var isConst = constant && properties.every((property) => property.$2);
    final methods = [
      for (final method in _methodsOf(model))
        _spring('IntrospectedMethod').newInstance(
          [_str(method.name)],
          {
            if (method.returnType case final returnType?)
              'returnType': _withoutFree(returnType, element),
            if (method.parameterTypes.isNotEmpty)
              // Not const when a type uses a captured type parameter.
              'parameterTypes':
                  (_writer.capturedTypeParameters.isEmpty
                  ? literalConstList
                  : literalList)([
                    for (final t in method.parameterTypes)
                      _withoutFree(t, element),
                  ]),
            if (method.isFuture) 'isFuture': literalTrue,
            // `Function.apply` checks the arguments an expression passes
            // (their number and types) as the method declares them.
            'invoke': function(
              'invoke',
              CodeWriter.objectOrNull,
              [
                ('object', describedType),
                ('arguments', CodeWriter.argumentList),
              ],
              refer('Function').property('apply').call([
                refer('object').property(method.name),
                refer('arguments'),
              ]).code,
            ),
            if (method.annotations.isNotEmpty)
              'annotations': literalConstList([
                for (final annotation in method.annotations)
                  _writer.constant(annotation, element),
              ]),
          },
          [describedType],
        ),
    ];
    final constructor = writes ? model.constructor : null;
    Expression? describedConstructor;
    if (constructor != null) {
      final parameters = <Expression>[];
      for (final parameter in constructor.parameters) {
        final (type, typeIsConst) = typeInfo(parameter.type, element);
        isConst = isConst && typeIsConst;
        parameters.add(
          _spring('IntrospectedParameter').newInstance(
            [_str(parameter.name)],
            {
              'type': type,
              if (parameter.isNamed)
                'symbol': CodeExpression(Code('#${parameter.name}')),
              if (parameter.isRequired) 'isRequired': literalTrue,
              if (parameter.defaultValue case final value?) ...{
                'hasDefaultValue': literalTrue,
                'defaultValue': _writer.constant(value, element),
              },
              if (parameter.annotations.isNotEmpty)
                'annotations': literalConstList([
                  for (final annotation in parameter.annotations)
                    _writer.constant(annotation, element),
                ]),
            },
          ),
        );
      }
      describedConstructor = _spring('IntrospectedConstructor').newInstance(
        [],
        {
          'parameters': literalList(parameters),
          'create': function(
            'create',
            describedType,
            [
              ('positional', CodeWriter.argumentList),
              ('named', CodeWriter.namedArgumentMap),
            ],
            (_directCall(model, constructor, describedType) ??
                    refer('Function')
                        .property('apply')
                        .call([
                          describedType.property(
                            constructor.name.isEmpty ? 'new' : constructor.name,
                          ),
                          refer('positional'),
                          refer('named'),
                        ])
                        .asA(describedType))
                .code,
          ),
        },
        [describedType],
      );
    }
    final fromJson = writes ? model.fromJson : null;
    final arguments = {
      'className': _str(model.element.name!),
      'specialize': ?specialize,
      // The properties of a class that is only known are of no use.
      'properties': isConst
          ? literalList([for (final (property, _) in properties) property])
          : _list(properties),
      if (methods.isNotEmpty) 'methods': literalList(methods),
      if (model.annotations.isNotEmpty)
        'annotations': literalConstList([
          for (final annotation in model.annotations)
            _writer.constant(annotation, element),
        ]),
      'library': literalString('${element.library!.uri}', raw: true),
      if (!(reads && writes && calls))
        'parts': literalConstSet({
          if (reads) _spring('IntrospectionPart').property('read'),
          if (writes) _spring('IntrospectionPart').property('write'),
          if (calls) _spring('IntrospectionPart').property('methods'),
        }),
      if (writes && model.instantiable)
        'instantiate': constant
            ? describedType.property('new')
            : _writer.closure(
                [],
                describedType.newInstance([]).code,
                lambda: true,
              ),
      'constructor': ?describedConstructor,
      if (fromJson != null)
        'fromJson': function(
          'fromJson',
          describedType,
          [('json', CodeWriter.objectOrNull)],
          describedType.property('fromJson').call([
            refer('json').asA(_writer.anyType(fromJson.parameterType, element)),
          ]).code,
        ),
      if (reads && model.hasToJson)
        'toJson': function(
          'toJson',
          CodeWriter.objectOrNull,
          [('object', describedType)],
          refer('object').property('toJson').call([]).code,
        ),
      // `@EqualsAndHashCode` and `@ToString`, in the raw description of a
      // generic class only (the one registered).
      if (model.objectMethods case final methods?
          when methods.hasObjectMethods &&
              _writer.capturedTypeParameters.isEmpty)
        'objectMethods': _objectMethods.objectMethodsExpression(
          methods,
          describedType,
        ),
    };
    // In a constant everything is: `const Introspection<T>(...)`; the
    // object methods are a constant anyway.
    if (arguments['objectMethods'] case final methods? when !isConst) {
      arguments['objectMethods'] = _asConst(methods);
    }
    return isConst
        ? _spring('Introspection').constInstance([], arguments, [describedType])
        : _spring('Introspection').newInstance([], arguments, [describedType]);
  }

  // A list of [items], each `(expression, isConst)` with the expression
  // written without `const`: `const [...]` when every item is a constant,
  // else `[...]` with `const` on the items that are.
  static Expression _list(List<(Expression, bool)> items) =>
      items.every((item) => item.$2)
      ? literalConstList([for (final (item, _) in items) item])
      : literalList([
          for (final (item, isConst) in items)
            if (isConst) _asConst(item) else item,
        ]);

  // [instance] (`new` written as `Type(...)`) as `const Type(...)`.
  static Expression _asConst(Expression instance) =>
      CodeExpression(Block.of([const Code('const '), instance.code]));

  // The `IntrospectedProperty<T>(...)` of [property], and whether it is a
  // constant ([constant]: its closures are written as top-level functions).
  (Expression, bool) _property(
    IntrospectionModel model,
    IntrospectionPropertyModel property,
    TypeReference describedType, {
    required bool constant,
    required bool reads,
    required bool writes,
    required bool validates,
  }) {
    final element = model.element;
    final (info, typeInfoIsConst) = typeInfo(
      property.declaredType,
      element,
    );
    final getBody = refer('object').property(property.name).code;
    final setBody = refer('object')
        .property(property.name)
        .assign(
          refer('value').asA(
            property.declaredType is TypeParameterType
                ? _writer.anyType(property.declaredType, element)
                : _writer
                      .classType(
                        property.type,
                        element,
                      )
                      .rebuild((t) => t..isNullable = property.nullable),
          ),
        )
        .code;
    final initial = writes ? property.initialValue : null;
    final arguments = {
      if (!constant || !_typeInfoIsExact(property.declaredType))
        'type': _writer.anyType(property.type, element),
      if (property.nullable) 'nullable': literalTrue,
      'typeInfo': info,
      if (initial != null) ...{
        'hasInitialValue': literalTrue,
        'initialValue': _writer.initialValue(
          initial.value,
          element,
          property.declaredType,
        ),
      },
      // Validation reads the properties that have rules only.
      if (reads || (validates && property.validated))
        'get': constant
            ? _writer.topLevelFunction(
                'get',
                CodeWriter.objectOrNull,
                [('object', describedType)],
                getBody,
              )
            : _writer.closure(['object'], getBody, lambda: true),
      if (writes && property.writable)
        'set': constant
            ? _writer.topLevelFunction(
                'set',
                refer('void'),
                [('object', describedType), ('value', CodeWriter.objectOrNull)],
                setBody,
              )
            : _writer.closure(['object', 'value'], setBody, lambda: true),
      if (property.annotations.isNotEmpty)
        'annotations': literalConstList([
          for (final annotation in property.annotations)
            _writer.constant(annotation, element),
        ]),
    };
    return (
      _spring('IntrospectedProperty').newInstance(
        [_str(property.name)],
        arguments,
        [describedType],
      ),
      constant && typeInfoIsConst,
    );
  }

  /// The `TypeInfo` of the declared [type] (declared or used by
  /// [element]): `ClassType<T>`, `ListType<E>(...)`, `SetType`, `MapType`,
  /// `GenericType`, `EnumType<E>(E.values)` or `DynamicType`; `$2` says
  /// whether the expression is const (an enum with `@JsonValue` needs a
  /// closure).
  (Expression, bool) typeInfo(DartType type, Element element) {
    final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
    // A captured type parameter of a specialized generic introspection:
    // the TypeInfo of its type argument.
    final erasedTo = type is TypeParameterType
        ? _writer.erasedTypeParameters[type.element]
        : null;
    if (type is TypeParameterType && erasedTo != null) {
      return _writer.withoutErasure(
        type.element,
        () => typeInfo(erasedTo, element),
      );
    }
    final captured = type is TypeParameterType
        ? _writer.capturedTypeParameters[type.element]
        : null;
    if (type is TypeParameterType && captured != null) {
      // `asA` writes `(arguments[0] as TypeInfo<T>)`.
      final info = refer('arguments')
          .index(literalNum(captured))
          .asA(
            TypeReference(
              (t) => t
                ..symbol = 'TypeInfo'
                ..url = _springUrl
                ..types.add(refer(type.element.name!)),
            ),
          );
      return (nullable ? info.property('asNullable').call([]) : info, false);
    }
    final named = <String, Expression>{if (nullable) 'nullable': literalTrue};
    (Expression, bool) kind(
      String name,
      List<DartType> arguments,
      Map<String, Expression> extra,
    ) {
      final infos = [for (final a in arguments) typeInfo(a, element)];
      final isConst = infos.every((info) => info.$2);
      final typeArguments = [
        for (final argument in arguments)
          if (_isDynamicInfo(argument))
            refer('dynamic')
          else
            _withoutFree(argument, element),
      ];
      final positional = [for (final info in infos) info.$1];
      return (
        isConst
            ? _spring(
                name,
              ).constInstance(positional, {...named, ...extra}, typeArguments)
            : _spring(name)
                  .newInstance(positional, {...named, ...extra}, typeArguments),
        isConst,
      );
    }

    if (type is InterfaceType && !_isDynamicInfo(type)) {
      final arguments = type.typeArguments;
      if ((type.isDartCoreList || type.isDartCoreIterable) &&
          arguments.length == 1) {
        return kind('ListType', arguments, const {});
      }
      if (type.isDartCoreSet && arguments.length == 1) {
        return kind('SetType', arguments, const {});
      }
      if (type.isDartCoreMap && arguments.length == 2) {
        return kind('MapType', arguments, const {});
      }
      // Other generic classes (`ResponseEntity<Book>`): the whole type plus
      // the description of each type argument.
      if (arguments.isNotEmpty) {
        final infos = [
          for (final argument in arguments) typeInfo(argument, element),
        ];
        final isConst = infos.every((info) => info.$2);
        final whole = _writer
            .classType(
              type,
              element,
            )
            .rebuild((t) => t..isNullable = false);
        final described = literalList([for (final info in infos) info.$1]);
        return (
          isConst
              ? _spring('GenericType')
                    .constInstance([described], named, [whole])
              : _spring('GenericType').newInstance([described], named, [whole]),
          isConst,
        );
      }
      final self = _writer
          .classType(type, element)
          .rebuild((t) => t..isNullable = false);
      if (type.element case final EnumElement enumElement) {
        // `@JsonValue` on a field or getter, or `@JsonProperty` names of
        // the constants.
        final jsonValue = enumJsonValue(
          enumElement,
          self,
          (parameters, body) => _writer.closure(parameters, body, lambda: true),
        );
        final values = self.property('values');
        if (jsonValue == null) {
          return (
            _spring('EnumType').constInstance([values], named, [self]),
            true,
          );
        }
        return (
          _spring(
            'EnumType',
          ).newInstance([values], {...named, 'jsonValue': jsonValue}, [self]),
          false,
        );
      }
      return (_spring('ClassType').constInstance([], named, [self]), true);
    }
    if (type is VoidType) {
      return (_spring('DynamicType').constInstanceNamed('forVoid', []), true);
    }
    return (_spring('DynamicType').constInstance([]), true);
  }

  // Types described as `DynamicType`: `dynamic`, `Object`, functions,
  // records, type parameters (but captured ones).
  bool _isDynamicInfo(DartType type) => type is TypeParameterType
      ? !_writer.capturedTypeParameters.containsKey(type.element) &&
            _writer.erasedTypeParameters[type.element] == null
      : type is! InterfaceType || type.isDartCoreObject;

  // Whether the `TypeInfo` of the declared type [type] describes exactly
  // the type an `IntrospectedProperty` has (its `type` without nullability), so
  // the property's `type:` can be left out: a class, an enum, a generic
  // class, or a `List` / `Set` / `Map` whose type arguments it writes as
  // they are (not `Object` written as `dynamic`).
  bool _typeInfoIsExact(DartType type) {
    if (type is! InterfaceType || _isDynamicInfo(type)) {
      return false;
    }
    final arguments = type.typeArguments;
    if (type.isDartCoreIterable) {
      return false;
    }
    if (type.isDartCoreList || type.isDartCoreSet || type.isDartCoreMap) {
      return arguments.every(
        (argument) => !_isDynamicInfo(argument) || argument is DynamicType,
      );
    }
    return true;
  }
}
