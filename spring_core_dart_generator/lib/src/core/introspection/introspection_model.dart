// The model of introspection: what the scan of the classes found out about
// each class the application describes (`IntrospectionScanner` fills it,
// `IntrospectionEmitter` writes it as `Introspection`s). Examples in this
// file show generated code without its import prefixes (`_i1.`, `_i2.`).

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:spring_core_dart_generator/src/core/introspection/object_methods/object_methods_model.dart';

/// What a use of an introspected class asks of its description: which of
/// its parts the runtime will touch. The scanner gives every request one,
/// merges the requests for a class (a class reached by several routes gets
/// the union) and the emitter writes only the parts that were asked for;
/// the class's annotations and property list are always written.
///
/// ```dart
/// // A request body that is validated: created and filled, and the
/// // constrained properties read.
/// IntrospectionNeed.write | IntrospectionNeed.validate
/// // A controller's return type: written out as JSON, and read back by the
/// // tests of the application.
/// IntrospectionNeed.read | IntrospectionNeed.write
/// ```
///
/// Spring (Java): no counterpart; reflection sees every part of any class.
final class IntrospectionNeed {
  const IntrospectionNeed._(this._bits);

  /// Nothing: the class is only known (a `@JsonView` marker, compared with
  /// other views).
  static const none = IntrospectionNeed._(0);

  /// The values of the properties are read from instances: the getters
  /// (written out as JSON, a cache value an expression reads, a bound
  /// configuration object).
  static const read = IntrospectionNeed._(1);

  /// Instances are created and filled: the constructor, `instantiate`, the
  /// setters and `fromJson` (a request body, an HTTP response, a message
  /// read in, configuration binding).
  static const write = IntrospectionNeed._(2);

  /// The validator reads the properties that have constraints or
  /// `@Valid()`: a getter for each of those, none for the others.
  static const validate = IntrospectionNeed._(4);

  /// Expressions may call the methods (SpEL).
  static const methods = IntrospectionNeed._(8);

  /// What an expression does with a value: reads its properties and calls
  /// its methods.
  static const spel = IntrospectionNeed._(1 | 8);

  /// What the configuration binder does: it sets the properties and reads
  /// their current values, to bind nested objects and maps in place.
  static const configuration = IntrospectionNeed._(1 | 2);

  /// Everything: what `@Introspected()` asks for.
  static const all = IntrospectionNeed._(1 | 2 | 4 | 8);

  final int _bits;

  /// The union of this need and [other].
  IntrospectionNeed operator |(IntrospectionNeed other) =>
      IntrospectionNeed._(_bits | other._bits);

  /// Whether every part of [other] is in this need.
  bool includes(IntrospectionNeed other) => _bits & other._bits == other._bits;

  /// Whether this need has any part of [other].
  bool intersects(IntrospectionNeed other) => _bits & other._bits != 0;

  /// Whether this is [none].
  bool get isNone => _bits == 0;

  @override
  bool operator ==(Object other) =>
      other is IntrospectionNeed && other._bits == _bits;

  @override
  int get hashCode => _bits;

  @override
  String toString() => isNone
      ? 'none'
      : [
          if (includes(read)) 'read',
          if (includes(write)) 'write',
          if (includes(validate)) 'validate',
          if (includes(methods)) 'methods',
        ].join('+');
}

/// A property of an `@Introspected` class: a public field, or a getter
/// with an optional setter, that runtime code can read and write by name.
///
/// The emitter writes it as an `IntrospectedProperty` with `get` and `set`
/// closures. JSON mapping, validation and property binding use it in
/// place of reflection.
///
/// ```dart
/// // Input:
/// @Introspected()
/// class Form {
///   @Size(max: 3)
///   String? nick;
/// }
/// // Output:
/// IntrospectedProperty<Form>(
///   r'nick',
///   type: String,
///   nullable: true,
///   get: (object) => object.nick,
///   set: (object, value) => object.nick = (value as String?),
///   annotations: const [Size(max: 3)],
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // BeanWrapperImpl discovers properties with java.beans.Introspector
/// // and reads/writes them through reflected getters and setters:
/// var wrapper = new BeanWrapperImpl(form);
/// wrapper.setPropertyValue("nick", "neo");
/// ```
class IntrospectionPropertyModel {
  /// Creates an introspected property.
  IntrospectionPropertyModel({
    required this.name,
    required this.type,
    required this.declaredType,
    required this.nullable,
    required this.writable,
    required this.annotations,
    this.validated = false,
    this.initialValue,
  });

  /// Whether a rule of the validator looks at the property: it has a
  /// constraint, `@Valid()`, `@Each()` or `@EachKey()`. A class that is
  /// only validated gets the getters of these properties and no other.
  final bool validated;

  /// The constant the field is initialized with, when the generated code
  /// can write it; `null` when there is none (no initializer, or one that
  /// is not a constant). A [DartObject] is a referenced constant (an enum
  /// value); a `List`, `Set` or `Map` holds such values or `null`, `bool`,
  /// `int`, `double` and `String`.
  final ({Object? value})? initialValue;

  /// The declared type as written, with nullability and type arguments,
  /// for `IntrospectedProperty.typeInfo`.
  final DartType declaredType;

  /// The property name.
  final String name;

  /// The declared type without `?`: a class type, or a type parameter of
  /// a generic introspected class.
  final DartType type;

  /// Whether the declared type is nullable; always `true` for a type
  /// parameter.
  final bool nullable;

  /// Whether the property has a setter, so it gets a `set` closure.
  final bool writable;

  /// The user annotations of the field and its getter, such as
  /// constraints and JSON annotations.
  final List<DartObject> annotations;
}

/// A public method of an `@Introspected` class that runtime code can call
/// by name, written as an `IntrospectedMethod` with an `invoke` closure.
///
/// ```dart
/// // Input:
/// String greet(String name, [int times = 1]) => name * times;
/// // Output:
/// IntrospectedMethod<Form>(
///   r'greet',
///   returnType: String,
///   parameterTypes: const [String, int],
///   invoke: (object, arguments) => Function.apply(object.greet, arguments),
/// ),
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring invokes methods reflectively, e.g. through ReflectionUtils:
/// Method greet = ReflectionUtils.findMethod(Form.class, "greet",
///     String.class, int.class);
/// ReflectionUtils.invokeMethod(greet, form, "Neo", 2);
/// ```
class IntrospectionMethodModel {
  /// Creates an introspected method.
  IntrospectionMethodModel({
    required this.name,
    required this.returnType,
    required this.parameterTypes,
    required this.annotations,
    this.isFuture = false,
    this.jsonNeed = IntrospectionNeed.none,
  });

  /// The method name.
  final String name;

  /// The return type; `null` for `void` and for non-class return types.
  final InterfaceType? returnType;

  /// The types of the positional parameters, without `?`.
  final List<InterfaceType> parameterTypes;

  /// The user annotations of the method.
  final List<DartObject> annotations;

  /// Whether it returns a `Future`: a security expression refuses it
  /// without calling it.
  final bool isFuture;

  /// What `ObjectMapper` needs the method for: [IntrospectionNeed.read]
  /// for `@JsonValue` and `@JsonAnyGetter` (writing the object out),
  /// [IntrospectionNeed.write] for `@JsonAnySetter` (reading it in);
  /// [IntrospectionNeed.none] for any other method. Such a method is
  /// described whenever its need is, also without
  /// [IntrospectionNeed.methods].
  final IntrospectionNeed jsonNeed;
}

/// An `@Introspected` class: the metadata that lets runtime code create
/// instances, read and write properties and call methods by name.
///
/// Spring reflects over any class when it needs to; Dart cannot, so a
/// class that JSON mapping, validation or binding works on is marked
/// `@Introspected` (or introspected automatically), and the module lists
/// an `Introspection` for it.
///
/// ```dart
/// // Input:
/// @Introspected()
/// @PasswordsMatch()
/// class SignupForm {
///   @NotBlank()
///   String name = '';
/// }
/// // Output (BeanModule argument):
/// introspections: [
///   Introspection<SignupForm>(
///     properties: [IntrospectedProperty<SignupForm>(r'name', ...)],
///     annotations: const [PasswordsMatch()],
///     instantiate: () => SignupForm(),
///   ),
/// ],
/// ```
///
/// Spring (Java):
///
/// ```java
/// // Spring reflects over any class on demand; Spring 6 AOT registers
/// // reflection hints instead (RuntimeHintsRegistrar) for native images:
/// BeanUtils.getPropertyDescriptors(SignupForm.class);
/// BeanUtils.instantiateClass(SignupForm.class);
/// ```
class IntrospectionModel {
  /// Creates an introspection model.
  IntrospectionModel({
    required this.element,
    required this.type,
    required this.properties,
    required this.methods,
    required this.annotations,
    required this.instantiable,
    this.need = IntrospectionNeed.none,
    this.nonDefaultInclusion = false,
    this.constructor,
    this.fromJson,
    this.hasToJson = false,
  });

  /// What the application does with the class, as far as the build saw:
  /// the union of every use found (see [IntrospectionNeed]). It only
  /// grows while the module is scanned; the emitter writes the parts it
  /// names and no others.
  IntrospectionNeed need;

  /// Whether the class has `@JsonInclude(JsonInclusion.nonDefault)`, which
  /// compares each value with that of a new instance, so writing the class
  /// out also needs [IntrospectionNeed.write].
  final bool nonDefaultInclusion;

  /// The constructor that creates instances from data, such as JSON (the
  /// `@JsonCreator` one, else the unnamed one), when it is usable.
  final ConstructorModel? constructor;

  /// The class's own `fromJson` (constructor or static method), which JSON
  /// reading then uses instead of the properties.
  final FromJsonModel? fromJson;

  /// Whether the class has its own `toJson()` method, which JSON writing
  /// then uses.
  final bool hasToJson;

  /// The class element, for error messages and imports.
  final Element element;

  /// The introspected class.
  final InterfaceType type;

  /// The public instance properties, subclass declarations first.
  final List<IntrospectionPropertyModel> properties;

  /// The public instance methods that can be called with positional
  /// arguments.
  final List<IntrospectionMethodModel> methods;

  /// The user annotations of the class.
  final List<DartObject> annotations;

  /// Whether the class has a public unnamed constructor callable without
  /// arguments, so the introspection gets an `instantiate` closure.
  final bool instantiable;

  /// Whether the binder of configuration properties asked for the class
  /// itself: a `@ConfigurationProperties` class, or the result of a
  /// `@ConfigurationProperties` `@Bean` method.
  bool forBinding = false;

  /// Whether a use other than the binder's asked for the class itself:
  /// `@Introspected()`, a controller's result, an expression...
  bool forOtherUses = false;

  /// The descriptions this one passed its need on to: the classes it is
  /// made of (the types of its properties and constructor parameters, the
  /// classes its JSON annotations name), which serve its uses too.
  final reaches = <IntrospectionModel>{};

  /// What `@EqualsAndHashCode`, `@ToString` and `@CopyWith` ask of the
  /// class: the description's `ObjectMethods`, and the `copyWith` of the
  /// module's `<library>.spring.introspection.dart`.
  ObjectMethodsModel? objectMethods;
}

/// The descriptions of [models] that only the binder of configuration
/// properties uses: asked for by the binder ([IntrospectionModel.forBinding])
/// or reached from such a description, and reached from no other use. The
/// module writes them apart, with the binding of its `@ConfigurationProperties`
/// classes (`<library>.spring.properties.dart`); a class the binder and another
/// use share stays with the other descriptions.
Set<IntrospectionModel> onlyForBinding(Iterable<IntrospectionModel> models) {
  Set<IntrospectionModel> reached(bool Function(IntrospectionModel) root) {
    final result = <IntrospectionModel>{};
    final pending = [
      for (final model in models)
        if (root(model)) model,
    ];
    while (pending.isNotEmpty) {
      final model = pending.removeLast();
      if (result.add(model)) {
        pending.addAll(model.reaches);
      }
    }
    return result;
  }

  return reached((model) => model.forBinding).difference(
    reached((model) => model.forOtherUses),
  );
}

/// The constructor of an introspected class that creates instances from
/// data (JSON reading, constructor binding), written as
/// `Introspection.constructor`.
///
/// ```dart
/// // Input: Book({required this.isbn, this.tags = const []})
/// // Output:
/// constructor: IntrospectedConstructor<Book>(
///   parameters: [
///     IntrospectedParameter(r'isbn', type: const ClassType<String>(),
///         symbol: #isbn, isRequired: true),
///     IntrospectedParameter(r'tags',
///         type: const ListType<String>(ClassType<String>()), symbol: #tags),
///   ],
///   create: (positional, named) =>
///       Function.apply(Book.new, positional, named) as Book,
/// ),
/// ```
class ConstructorModel {
  /// Creates the model.
  ConstructorModel({required this.name, required this.parameters});

  /// The constructor name; empty for the unnamed constructor.
  final String name;

  /// Its parameters, in declaration order.
  final List<ConstructorParameterModel> parameters;
}

/// A parameter of a [ConstructorModel], an `AnnotatedMethodModel` or an
/// `InterfaceMethodModel`, written as an `IntrospectedParameter` that
/// runtime code fills by name or position.
class ConstructorParameterModel {
  /// Creates the model.
  ConstructorParameterModel({
    required this.name,
    required this.type,
    required this.isNamed,
    required this.isRequired,
    required this.annotations,
    this.hasDefault = false,
    this.defaultValue,
  });

  /// The parameter name.
  final String name;

  /// The declared type.
  final DartType type;

  /// Whether the parameter is named.
  final bool isNamed;

  /// Whether a value must be passed: a required positional parameter, or
  /// a `required` named one.
  final bool isRequired;

  /// The user annotations on the parameter, such as `@JsonProperty` or
  /// `@PathVariable`.
  final List<DartObject> annotations;

  /// Whether the parameter declares a default value.
  final bool hasDefault;

  /// The default value when generated code can re-create it; set for
  /// introspected constructors only.
  final DartObject? defaultValue;
}

/// A `fromJson` that an introspected class declares itself
/// (`factory Book.fromJson(Map json)` or a static method), written as
/// `Introspection.fromJson`.
///
/// JSON reading calls it instead of filling the properties, so a class
/// that already knows how to read itself keeps doing so.
class FromJsonModel {
  /// Creates the model.
  FromJsonModel({required this.parameterType});

  /// The type of its JSON parameter (`Map<String, dynamic>`...); the
  /// runtime converts the decoded JSON to it.
  final DartType parameterType;
}
