// The code of `@EqualsAndHashCode`, `@ToString` and `@CopyWith`: the
// `ObjectMethods` of a class's description, and the `copyWith` of the
// module's `<library>.spring.introspection.dart`.
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart' as cb show FunctionType;
import 'package:code_builder/code_builder.dart' hide FunctionType;
import 'package:spring_core_dart/core.dart' show SecretNames;
import 'package:spring_core_dart_generator/src/core/builder/code_writer.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_model.dart';

// Runtime types are always imported from the public library, never from
// `src/`.
const _springCoreDartUrl = 'package:spring_core_dart/spring_core_dart.dart';

Reference _springCoreDart(String name) => refer(name, _springCoreDartUrl);

// The class whose constant is the default of `copyWith`'s arguments: an
// argument that is still it was left out, so the field keeps its value.
// Private, so no caller can pass it.
const _keepMarkerClass = r'_$Keep';

/// Writes what the object methods' annotations ask of a class, naming what
/// it uses through the [CodeWriter] of the module's
/// `<library>.spring.introspection.dart`: the `ObjectMethods` of its
/// description ([objectMethodsExpression]: typed top-level functions), and
/// the declarations of the file ([declarations]: the `copyWith` type and
/// extension).
///
/// ```dart
/// // Input:
/// @EqualsAndHashCode()
/// @ToString()
/// @CopyWith()
/// class Book with IntrospectedObject {
///   const Book(this.title, {this.subtitle});
///   final String title;
///   final String? subtitle;
/// }
///
/// // Output (app.spring.introspection.dart):
/// bool _$equals0(Book a, Book b) =>
///     a.title == b.title && a.subtitle == b.subtitle;
/// int _$hashCode1(Book object) => Object.hash(object.title, object.subtitle);
/// String _$toString2(Book object) =>
///     'Book(title: ${object.title}, subtitle: ${object.subtitle})';
/// // In Book's description:
/// //   objectMethods: ObjectMethods<Book>(equals: _$equals0, ...)
///
/// typedef BookCopyWith = Book Function({String title, String? subtitle});
///
/// extension $Book on Book {
///   BookCopyWith get copyWith => ({
///     Object? title = const _$Keep(),
///     Object? subtitle = const _$Keep(),
///   }) => Book(title is _$Keep ? this.title : title as String, ...);
/// }
/// ```
final class ObjectMethodsEmitter {
  /// The emitter of the library [_writer] writes.
  ObjectMethodsEmitter(this._writer);

  final CodeWriter _writer;

  /// `ObjectMethods<T>(...)` of [model], with the functions it names
  /// declared in the library; [describedType] is the class as its
  /// description writes it (a generic class with its type parameters
  /// erased).
  Expression objectMethodsExpression(
    ObjectMethodsModel model,
    TypeReference describedType,
  ) {
    final arguments = <String, Expression>{};
    if (model.equalsAndHashCodeModel case final equalsAndHashCode?) {
      arguments['equals'] = _writer.topLevelFunction(
        'equals',
        refer('bool'),
        [('a', describedType), ('b', describedType)],
        _equalsBody(equalsAndHashCode),
      );
      arguments['hashCode'] = _writer.topLevelFunction(
        'hashCode',
        refer('int'),
        [('object', describedType)],
        _hashCodeBody(equalsAndHashCode),
      );
    }
    if (model.toStringModel case final toStringModel?) {
      final writesSuperText =
          toStringModel.superclassPart != SuperclassPart.none;
      arguments[writesSuperText ? 'toStringWithSuper' : 'toString'] = _writer
          .topLevelFunction(
            'toString',
            refer('String'),
            [
              ('object', describedType),
              if (writesSuperText) ('superText', refer('String')),
            ],
            _toStringBody(model, toStringModel),
          );
    }
    final superEquals =
        model.equalsAndHashCodeModel?.superclassPart ??
        (model.equalsFromSuperclass
            ? SuperclassPart.described
            : SuperclassPart.none);
    final superToString =
        model.toStringModel?.superclassPart ??
        (model.toStringFromSuperclass
            ? SuperclassPart.described
            : SuperclassPart.none);
    if (superEquals == SuperclassPart.described ||
        superToString == SuperclassPart.described) {
      final superclass = model.describedSuperclass!;
      arguments['superclass'] = refer(
        superclass.name!,
        _writer.importUrl(
          superclass.library.uri,
          model.element,
          name: superclass.name,
          declaration: superclass,
        ),
      );
    }
    if (superEquals != SuperclassPart.none) {
      arguments['superEquals'] = _springCoreDart(
        'SuperMethod',
      ).property(superEquals.name);
    }
    if (superToString != SuperclassPart.none) {
      arguments['superToString'] = _springCoreDart(
        'SuperMethod',
      ).property(superToString.name);
    }
    return _springCoreDart(
      'ObjectMethods',
    ).newInstance([], arguments, [describedType]);
  }

  // `a.title == b.title && deepEquals(a.tags, b.tags)`.
  Code _equalsBody(EqualsAndHashCodeModel equalsAndHashCode) =>
      Code.scope((allocate) {
        final terms = [
          for (final field in equalsAndHashCode.fields)
            if (field.comparedAsDouble)
              '${allocate(_springCoreDart('doubleEquals'))}(a.${field.name}, '
                  'b.${field.name})'
            else if (field.comparedByContent)
              '${allocate(_springCoreDart('deepEquals'))}(a.${field.name}, '
                  'b.${field.name})'
            else
              'a.${field.name} == b.${field.name}',
        ];
        return terms.isEmpty ? 'true' : terms.join(' && ');
      });

  // The fields' hashes (collections by content), by `Object.hash`,
  // `Object.hashAll` past its 20 arguments.
  Code _hashCodeBody(EqualsAndHashCodeModel equalsAndHashCode) =>
      Code.scope((allocate) {
        final fields = equalsAndHashCode.fields;
        final terms = [
          for (final field in fields)
            if (field.comparedAsDouble)
              '${allocate(_springCoreDart('doubleHash'))}(object.${field.name})'
            else if (field.comparedByContent)
              '${allocate(_springCoreDart('deepHash'))}(object.${field.name})'
            else
              'object.${field.name}',
        ];
        return switch (terms.length) {
          0 => '0',
          1
              when fields.single.comparedByContent ||
                  fields.single.comparedAsDouble =>
            terms.single,
          1 => '${terms.single}.hashCode',
          <= 20 => 'Object.hash(${terms.join(', ')})',
          _ => 'Object.hashAll([${terms.join(', ')}])',
        };
      });

  // `'Book(title: ${object.title}, password: ******)'`: the class's name as
  // written in the source, a masked field's value never read.
  Code _toStringBody(ObjectMethodsModel model, ToStringModel toStringModel) {
    String entry(String label, String value) => toStringModel.includeNames
        ? '${_escapedForLiteral(label)}: $value'
        : value;
    final entries = [
      if (toStringModel.superclassPart != SuperclassPart.none)
        entry('super', r'$superText'),
      for (final field in toStringModel.fields)
        entry(
          field.name,
          field.masked ? SecretNames.masked : '\${object.${field.name}}',
        ),
    ];
    return Code(
      "'${_escapedForLiteral(model.name)}(${entries.join(', ')})'",
    );
  }

  // The library at [uri] as a part of a name: its path below `lib/` (and
  // `src/`) without the extension, each part capitalized
  // (`package:app/src/shop/book.dart` -> `ShopBook`).
  static String _librarySuffix(Uri uri) {
    final segments = [...uri.pathSegments];
    if (uri.scheme == 'package' && segments.isNotEmpty) {
      segments.removeAt(0);
    }
    if (segments.firstOrNull == 'lib') {
      segments.removeAt(0);
    }
    if (segments.firstOrNull == 'src') {
      segments.removeAt(0);
    }
    return [
      for (final segment in segments)
        for (final word
            in segment
                .replaceFirst(RegExp(r'\.dart$'), '')
                .split(RegExp('[^A-Za-z0-9]+')))
          if (word.isNotEmpty) '${word[0].toUpperCase()}${word.substring(1)}',
    ].join();
  }

  // [text] inside a single-quoted literal: `$` and `\` escaped (a class or
  // field may be named `a$b`).
  static String _escapedForLiteral(String text) =>
      text.replaceAll(r'\', r'\\').replaceAll(r'$', r'\$');

  /// The declarations of [models] (those of the module's
  /// `<library>.spring.introspection.dart`, in its order) for the library:
  /// for each class with `@CopyWith`, its `copyWith` type and its
  /// extension; then the marker of `copyWith`'s defaults when a class has
  /// one.
  ///
  /// Two classes of one name (in two libraries) get names that say the
  /// library of each (`BookCopyWithShopBook`, from `lib/src/shop/book.dart`),
  /// so a name stays the same whatever order the build reads them in; a
  /// number is added only when those are taken too.
  List<Spec> declarations(List<ObjectMethodsModel> models) {
    final usedNames = <String>{};
    String uniqueName(String name) {
      var candidate = name;
      for (var number = 2; !usedNames.add(candidate); number++) {
        candidate = '$name$number';
      }
      return candidate;
    }

    final sameName = <String, int>{};
    for (final model in models) {
      if (model.copyWithModel != null) {
        sameName.update(model.name, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final specs = <Spec>[];
    for (final model in models) {
      if (model.copyWithModel case final copyWith?) {
        final suffix = sameName[model.name]! > 1
            ? _librarySuffix(model.element.library.uri)
            : '';
        final typedefName = uniqueName('${model.name}CopyWith$suffix');
        final extensionName = uniqueName('\$${model.name}$suffix');
        specs
          ..add(_copyWithTypedef(model, copyWith, typedefName))
          ..add(
            _copyWithExtension(model, copyWith, extensionName, typedefName),
          );
      }
    }
    if (models.any((model) => model.hasCopyWith)) {
      specs.add(
        Class(
          (c) => c
            ..docs.add(
              "/// The default of `copyWith`'s arguments: left out, the field "
              'keeps its value.',
            )
            ..modifier = ClassModifier.final$
            ..name = _keepMarkerClass
            ..constructors.add(Constructor((k) => k..constant = true)),
        ),
      );
    }
    return specs;
  }

  // The type parameters of [element] as declared (`T extends num`).
  List<Reference> _typeParameters(ClassElement element) => [
    for (final parameter in element.typeParameters)
      TypeReference(
        (t) => t
          ..symbol = parameter.name
          ..bound = switch (parameter.bound) {
            final DartType bound => _writer.anyType(bound, element),
            null => null,
          },
      ),
  ];

  // [symbol] with [element]'s type parameters as its arguments
  // (`PageCopyWith<T>`).
  static TypeReference _withTypeParameters(
    String symbol,
    ClassElement element,
  ) => TypeReference(
    (t) => t
      ..symbol = symbol
      ..types.addAll([
        for (final parameter in element.typeParameters) refer(parameter.name!),
      ]),
  );

  // `typedef BookCopyWith = Book Function({String title, ...});`.
  Spec _copyWithTypedef(
    ObjectMethodsModel model,
    CopyWithModel copyWith,
    String name,
  ) {
    final element = model.element;
    return TypeDef(
      (t) => t
        ..docs.add(
          '/// `copyWith` of [${model.name}] (`@CopyWith`): a copy with the '
          'values given; one left out keeps its value, `null` clears a '
          'nullable one.',
        )
        ..name = name
        ..types.addAll(_typeParameters(element))
        ..definition = cb.FunctionType(
          (f) => f
            ..returnType = _writer.classType(element.thisType, element)
            ..namedParameters.addAll({
              for (final field in copyWith.fields)
                field.name!: _writer.anyType(field.type, element),
            }),
        ),
    );
  }

  // `extension $Book on Book { BookCopyWith get copyWith => ... }`.
  Spec _copyWithExtension(
    ObjectMethodsModel model,
    CopyWithModel copyWith,
    String name,
    String typedefName,
  ) {
    final element = model.element;
    final classType = _writer.classType(element.thisType, element);
    return Extension(
      (e) => e
        ..docs.add('/// `copyWith` of [${model.name}].')
        ..name = name
        ..types.addAll(_typeParameters(element))
        ..on = classType
        ..methods.add(
          Method(
            (m) => m
              ..type = MethodType.getter
              ..returns = _withTypeParameters(typedefName, element)
              ..name = 'copyWith'
              ..lambda = true
              ..body = _copyWithClosure(model, copyWith, classType).code,
          ),
        ),
    );
  }

  // `({Object? title = const _$Keep(), ...}) => Book(title is _$Keep ?
  // this.title : title as String, ...)`.
  Expression _copyWithClosure(
    ObjectMethodsModel model,
    CopyWithModel copyWith,
    TypeReference classType,
  ) {
    final element = model.element;
    final keepMarker = refer(_keepMarkerClass);
    final positional = <Expression>[];
    final named = <String, Expression>{};
    for (final argument in copyWith.arguments) {
      final parameter = argument.parameter;
      final value = switch (argument) {
        CopyWithArgument(changeableField: final field?) =>
          refer(field.name!)
              .isA(keepMarker)
              .conditional(
                refer('this').property(field.name!),
                refer(field.name!).asA(_writer.anyType(field.type, element)),
              ),
        CopyWithArgument(:final keptGetter) => refer(
          'this',
        ).property(keptGetter!),
      };
      if (parameter.isNamed) {
        named[parameter.name!] = value;
      } else {
        positional.add(value);
      }
    }
    return Method(
      (m) => m
        ..optionalParameters.addAll([
          for (final field in copyWith.fields)
            Parameter(
              (p) => p
                ..named = true
                ..name = field.name!
                ..type = CodeWriter.objectOrNull
                ..defaultTo = keepMarker.constInstance([]).code,
            ),
        ])
        ..lambda = true
        ..body = _constructorCall(
          classType,
          copyWith.constructor,
          positional,
          named,
        ).code,
    ).closure;
  }

  static Expression _constructorCall(
    TypeReference classType,
    ConstructorElement constructor,
    List<Expression> positional,
    Map<String, Expression> named,
  ) => switch (constructor.name) {
    null || 'new' => classType.newInstance(positional, named),
    final name => classType.newInstanceNamed(name, positional, named),
  };
}
