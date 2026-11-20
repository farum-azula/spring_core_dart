// The model of a class's object methods: what `@EqualsAndHashCode`,
// `@ToString` and `@CopyWith` ask of it, read and checked by
// `ObjectMethodsScanner`, written by `ObjectMethodsEmitter` into the
// class's description and the module's `<library>.spring.introspection.dart`.
import 'package:analyzer/dart/element/element.dart';

/// Where the superclass's part of an object method comes from with
/// `callSuper: true`, as the runtime's `SuperMethod` says it.
enum SuperclassPart {
  /// No part of the superclass.
  none,

  /// The described superclass's
  /// ([ObjectMethodsModel.describedSuperclass]).
  described,

  /// The superclass's own method, called as `super` by `IntrospectedObject`.
  inherited,
}

/// A field of an annotated class as the generated code reads it.
final class ObjectField {
  /// The field [element]; [comparedByContent] when it is compared and
  /// hashed by content, [masked] when `toString()` writes `******` for it.
  ObjectField(
    this.element, {
    required this.comparedByContent,
    this.masked = false,
  });

  /// The field.
  final FieldElement element;

  /// Its name.
  String get name => element.name!;

  /// Whether `==` and `hashCode` use `deepEquals` and `deepHash`: a
  /// collection, or a type that may hold one (`Object`, `dynamic`, a type
  /// parameter).
  final bool comparedByContent;

  /// Whether `toString()` writes `******` (a secret-looking name, or
  /// `mask:`); its value is never read.
  final bool masked;
}

/// `@EqualsAndHashCode` of a class: the [fields] compared, and where the
/// superclass's part comes from ([superclassPart]).
final class EqualsAndHashCodeModel {
  /// `==` and `hashCode` over [fields].
  EqualsAndHashCodeModel(this.fields, {required this.superclassPart});

  /// The fields, in their declaration order.
  final List<ObjectField> fields;

  /// The superclass's part.
  final SuperclassPart superclassPart;
}

/// `@ToString` of a class: the [fields] written, with their names or not,
/// after the superclass's text or not.
final class ToStringModel {
  /// A `toString()` of [fields].
  ToStringModel(
    this.fields, {
    required this.includeNames,
    required this.superclassPart,
  });

  /// The fields, in their declaration order.
  final List<ObjectField> fields;

  /// `title: Dune` rather than `Dune`.
  final bool includeNames;

  /// The superclass's text.
  final SuperclassPart superclassPart;
}

/// An argument of the constructor `copyWith` calls: the parameter
/// [parameter] (named or not), given the value of `copyWith`'s argument
/// for the [changeableField], or the original's [keptGetter].
final class CopyWithArgument {
  /// The argument for [parameter].
  CopyWithArgument(this.parameter, {this.changeableField, this.keptGetter});

  /// The constructor's parameter.
  final FormalParameterElement parameter;

  /// The field `copyWith` may change, when the parameter sets one.
  final FieldElement? changeableField;

  /// The getter of the original whose value is passed on otherwise.
  final String? keptGetter;
}

/// `@CopyWith` of a class: the [fields] `copyWith` takes, and the
/// [arguments] of the [constructor] that makes the copy.
final class CopyWithModel {
  /// A `copyWith` of [fields] through [constructor].
  CopyWithModel(this.fields, this.constructor, this.arguments);

  /// The fields, in their declaration order: `copyWith`'s parameters.
  final List<FieldElement> fields;

  /// The constructor called.
  final ConstructorElement constructor;

  /// Its arguments, in the order of its parameters (left out: an optional
  /// parameter that sets no field, which takes its default).
  final List<CopyWithArgument> arguments;
}

/// A class annotated with any of the three, and what the build writes for
/// it: the object methods of its description ([equalsAndHashCodeModel],
/// [toStringModel]) and its `copyWith` ([copyWithModel]).
final class ObjectMethodsModel {
  /// The model of [element].
  ObjectMethodsModel(this.element);

  /// The annotated class.
  final ClassElement element;

  /// `@EqualsAndHashCode`, when it is there and checked.
  EqualsAndHashCodeModel? equalsAndHashCodeModel;

  /// `@ToString`, when it is there and checked.
  ToStringModel? toStringModel;

  /// `@CopyWith`, when it is there and checked.
  CopyWithModel? copyWithModel;

  /// The closest class above with `@EqualsAndHashCode` or `@ToString`,
  /// whose description the superclass's parts come from.
  InterfaceElement? describedSuperclass;

  /// Whether `==` and `hashCode`, which the class does not generate, are
  /// those of [describedSuperclass] (a subclass with `@ToString` alone).
  bool equalsFromSuperclass = false;

  /// Whether `toString()`, which the class does not generate, is that of
  /// [describedSuperclass].
  bool toStringFromSuperclass = false;

  /// The class's name.
  String get name => element.name!;

  /// Whether the description gets `ObjectMethods`.
  bool get hasObjectMethods =>
      equalsAndHashCodeModel != null || toStringModel != null;

  /// Whether the module's `<library>.spring.introspection.dart` gets the
  /// class's `copyWith`.
  bool get hasCopyWith => copyWithModel != null;
}
