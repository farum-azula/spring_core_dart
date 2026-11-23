import 'package:spring_core_dart/src/beans/object_methods.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';

/// Marks a class whose properties, constructor and methods the generator
/// describes, so the framework can read and fill its objects without
/// reflection.
///
/// Dart has no runtime reflection in Flutter or compiled programs, so
/// anything that must list or set the fields of an object it did not write
/// needs a description generated at build time. Put `@Introspected()` on
/// the classes that are bound from requests or configuration, validated,
/// turned into JSON or used in SpEL expressions. Micronaut's
/// `@Introspected` works the same way.
///
/// ```dart
/// // A form that is validated and bound from request data.
/// @Introspected()
/// class Address {
///   @NotBlank()
///   String city = '';
///   String? zip;
/// }
///
/// // The generated Introspection of Address is registered by the module,
/// // so:
/// BeanWrapper(Address()).setPropertyValue('city', 'Lyon');
/// ```
///
/// Spring (Java): no annotation is needed; Spring discovers properties at
/// runtime with `java.beans.Introspector` (getters and setters) and
/// reflection. Micronaut's `@Introspected` is the closest match.
/// ```java
/// class Address {
///   private String city;
///   public String getCity() { return city; }
///   public void setCity(String city) { this.city = city; }
/// }
/// ```
///
/// Classes of other packages (a shared DTO package, ...) are introspected
/// by listing them: `@Introspected(classes: [ExternalDto])` on any class of
/// the scanned package. Classes of the same package used by an introspected
/// class (property and constructor types) are introspected automatically.
///
/// `@Introspected()` describes everything about a class. A class the build
/// finds in use without it (a controller's return type, a request body, a
/// client's answer) is described only for that use, see
/// [IntrospectionPart]; the annotation is the way to ask for all of it.
class Introspected {
  /// Introspects the annotated class and the [classes] listed.
  const Introspected({this.classes = const []});

  /// More classes to introspect, typically from another package that has
  /// no generator of its own.
  final List<Type> classes;
}

/// A part of an introspected class that its [Introspection] may leave
/// out.
///
/// The generator writes only what the application uses of a class, as the
/// build can tell: a class that is only written out as JSON (a controller's
/// return type) gets its getters, one that is only read in (a request body)
/// its constructor and setters, and methods are described only where an
/// expression may call them. Annotations and the property list are always
/// there. Asking for a part that was left out throws an
/// [IntrospectionPartError]; `@Introspected()` on the class describes all
/// of them.
///
/// ```dart
/// // A request body: created and filled, never read.
/// introspection.describesPart(IntrospectionPart.write); // true
/// introspection.describesPart(IntrospectionPart.read); // false
/// ```
///
/// Spring (Java): no counterpart; reflection always sees everything.
enum IntrospectionPart {
  /// The getters: the values of the properties can be read from an object
  /// (written as JSON, validated, read by an expression).
  read('its getters'),

  /// The constructor, `instantiate`, the setters and `fromJson`: objects
  /// can be created and filled (read from JSON, bound from a request or
  /// from configuration).
  write('its constructor and setters'),

  /// The methods an expression may call.
  methods('its methods');

  IntrospectionPart(this.description);

  /// The part in words, as error messages name it (`its getters`).
  final String description;
}

/// The error thrown when code needs a part of an introspected class that
/// its description leaves out.
///
/// The message names the class and the part and says what to do: the
/// build described only what it saw used, so the class is used somewhere it
/// did not see (a value cast to `Object`, a class that only a plugin
/// reads); `@Introspected()` on the class describes all of it.
///
/// ```dart
/// // Book is only read in (a request body), then written out by hand:
/// // Bad state: Book is described without its getters, but it is written
/// // out as JSON. The build described only what it saw used, and did not
/// // see that: add @Introspected() to Book.
/// ```
///
/// Spring (Java): no counterpart; Java reflection always sees everything.
final class IntrospectionPartError extends StateError {
  /// [type] is described without [part]; [use] says what needs it, a
  /// clause that follows "but" (`it is written out as JSON`).
  IntrospectionPartError(this.type, this.part, String use)
    : super(
        '$type is described without ${part.description}, but $use. The '
        'build described only what it saw used, and did not see that: add '
        '@Introspected() to $type.',
      );

  /// The class whose description lacks [part].
  final Type type;

  /// The part that is needed.
  final IntrospectionPart part;
}

/// The description of one property of an introspected class: its name,
/// type, annotations, and closures that read and write it.
///
/// The generator writes these for `@Introspected` classes; `BeanWrapper`,
/// validation and SpEL use them to reach a field by name. You write one by
/// hand only in a hand-written [Introspection].
///
/// Both closures are optional: the generator writes only the ones the
/// application uses (see [IntrospectionPart]), so a property that is only
/// read from JSON has a setter and no getter ([isReadable] is `false`).
///
/// ```dart
/// // A property of Address, written by hand.
/// final city = IntrospectedProperty<Address>(
///   'city',
///   type: String,
///   get: (address) => address.city,
///   set: (address, value) => address.city = value! as String,
///   annotations: const [NotBlank()],
/// );
/// city.setValue(address, 'Lyon');
/// city.getValue(address); // 'Lyon'
/// ```
///
/// Spring (Java): `java.beans.PropertyDescriptor`, found by reflection:
/// ```java
/// PropertyDescriptor city =
///     BeanUtils.getPropertyDescriptor(Address.class, "city");
/// city.getWriteMethod().invoke(address, "Lyon");
/// ```
final class IntrospectedProperty<T extends Object> {
  /// Describes the property [name] of [T] with the declared [type]; omit
  /// `set` for a read-only property and `get` for a write-only one.
  ///
  /// [type] may be left out when [typeInfo] is given: it is then the type
  /// [typeInfo] describes. The generator writes it only when they differ,
  /// and writes the closures as top-level functions, so its descriptions
  /// are constants.
  const IntrospectedProperty(
    this.name, {
    Type? type,
    this._get,
    this._set,
    this.nullable = false,
    this.typeInfo,
    this.hasInitialValue = false,
    this.initialValue,
    this.annotations = const [],
  }) : _type = type,
       assert(
         type != null || typeInfo != null,
         'An IntrospectedProperty needs a type or a typeInfo',
       );

  /// The name of the field or getter.
  final String name;

  final Type? _type;

  /// The declared type, without its nullability (see [nullable]).
  Type get type => _type ?? typeInfo!.type;

  /// Whether the declared type is nullable.
  final bool nullable;

  /// The full declared type (element types, enum values, nullability);
  /// written by the generator, `null` in hand-written introspections.
  final TypeInfo<Object?>? typeInfo;

  /// The const annotations on the field or getter (e.g. constraints).
  final List<Object> annotations;

  /// Whether the field is declared with an initializer that is a constant
  /// the generator could write into the description, so [initialValue] is
  /// meaningful (`bool inStock = true`).
  ///
  /// It is `false` for a field without an initializer, for a getter, and
  /// for an initializer that is not a constant: `DateTime.now()`, a
  /// non-`const` list (`[]`), a call, a reference to a non-const variable.
  /// Written by the generator; `false` in hand-written introspections.
  final bool hasInitialValue;

  /// The constant the field starts with, when [hasInitialValue] is `true`
  /// (`null` for an initializer that is `null`, or when it is not).
  ///
  /// The generator supports `null`, `bool`, `int`, `double`, `String`,
  /// enum values, `const` lists, sets and maps of such values, and
  /// references to public constants. A field of a `double` type with an
  /// `int` initializer (`double rate = 1`) gives the `double`.
  final Object? initialValue;

  final Object? Function(T object)? _get;
  final void Function(T object, Object? value)? _set;

  /// Whether the property can be read; `false` when the description has no
  /// getter for it (the build saw nothing read the class).
  bool get isReadable => _get != null;

  /// Whether the property can be written; `false` for a final field or a
  /// getter without a setter.
  bool get isWritable => _set != null;

  /// The value of the property in [object], which must be a [T]. Throws an
  /// [IntrospectionPartError] when the property has no getter
  /// ([isReadable]).
  Object? getValue(Object object) {
    final getter = _get;
    if (getter == null) {
      throw IntrospectionPartError(
        T,
        IntrospectionPart.read,
        "the value of property '$name' is read",
      );
    }
    return getter(object as T);
  }

  /// Writes [value] into the property of [object]. The value must already
  /// have the property's type (`BeanWrapper` converts first). Throws
  /// `StateError` for a read-only property.
  void setValue(Object object, Object? value) {
    final setter = _set;
    if (setter == null) {
      throw StateError("Property '$name' of $T is read-only");
    }
    setter(object as T, value);
  }

  // This property with what [earlier], the description of the same property
  // registered before it, has and this one lacks: its getter or setter.
  IntrospectedProperty<T> _withEarlier(IntrospectedProperty<T> earlier) {
    if (_get != null && _set != null) {
      return this;
    }
    return IntrospectedProperty<T>(
      name,
      type: _type ?? earlier._type ?? type,
      get: _get ?? earlier._get,
      set: _set ?? earlier._set,
      nullable: nullable,
      typeInfo: typeInfo ?? earlier.typeInfo,
      hasInitialValue: hasInitialValue || earlier.hasInitialValue,
      initialValue: hasInitialValue ? initialValue : earlier.initialValue,
      annotations: annotations.isEmpty ? earlier.annotations : annotations,
    );
  }

  /// The annotations of the property of type [A].
  Iterable<A> annotationsOf<A>() => annotations.whereType<A>();

  @override
  String toString() =>
      'IntrospectedProperty<$T>($name: $type${nullable ? '?' : ''})';
}

/// The description of one public instance method of a class, with a
/// closure that calls it: of an introspected class (in its
/// [Introspection]), or an annotated method of a bean.
///
/// SpEL uses it to call methods on introspected objects, and frameworks
/// use the ones in `BeanDefinition.annotatedMethods` to call annotated
/// methods of beans (`@Scheduled`, request handlers). You write one by
/// hand only in a hand-written introspection.
///
/// ```dart
/// // Person.hello(String name), called by name from an expression.
/// final hello = IntrospectedMethod<Person>(
///   'hello',
///   returnType: String,
///   parameterTypes: const [String],
///   invoke: (person, args) => person.hello(args.first! as String),
/// );
/// hello.invoke(person, ['Ann']);
/// ```
///
/// Spring (Java): `java.lang.reflect.Method`:
/// ```java
/// Method hello = Person.class.getMethod("hello", String.class);
/// hello.invoke(person, "Ann");
/// ```
final class IntrospectedMethod<T extends Object> {
  /// Describes the method [name] of [T], called through `invoke` (and
  /// `invokeNamed` when it has named parameters).
  const IntrospectedMethod(
    this.name, {
    required this._invoke,
    this._invokeNamed,
    this.returnType,
    this.parameterTypes = const [],
    this.parameters = const [],
    this.returnTypeInfo,
    this.isFuture = false,
    this.isVoid = false,
    this.annotations = const [],
  });

  /// The method's name.
  final String name;

  /// The declared return type; `null` for `void`.
  final Type? returnType;

  /// Declared types of the positional parameters.
  final List<Type> parameterTypes;

  /// Every parameter (positional, then named) with its name, full type and
  /// annotations. Written by the generator for the methods of
  /// `BeanDefinition.annotatedMethods` (what a request handler needs to
  /// bind its arguments); empty in other descriptions.
  final List<IntrospectedParameter> parameters;

  /// The full result type, for a `Future<T>` the type `T` (what a request
  /// handler's answer is converted from). Written by the generator for
  /// every method of `BeanDefinition.annotatedMethods` that returns a
  /// value, with or without parameters; `null` for a `void` method (see
  /// [isVoid]) and in other descriptions.
  final TypeInfo<Object?>? returnTypeInfo;

  /// Whether the method returns a non-nullable `Future` (see
  /// [returnTypeInfo]).
  final bool isFuture;

  /// Whether the result (or the future's value) is `void`.
  final bool isVoid;

  /// The const annotations on the method.
  final List<Object> annotations;
  final Object? Function(T object, List<Object?> arguments) _invoke;
  final Object? Function(
    T object,
    List<Object?> positional,
    Map<Symbol, Object?> named,
  )?
  _invokeNamed;

  /// Calls the method on [object] with positional [arguments] (already of
  /// the parameter types) and [namedArguments] (by
  /// [IntrospectedParameter.symbol]; an omitted optional one keeps its
  /// default value); returns its result (`null` for `void`). Throws
  /// `ArgumentError` when named arguments are given to a method described
  /// without them.
  Object? invoke(
    Object object,
    List<Object?> arguments, [
    Map<Symbol, Object?> namedArguments = const {},
  ]) {
    if (namedArguments.isEmpty) {
      return _invoke(object as T, arguments);
    }
    final invokeNamed = _invokeNamed;
    if (invokeNamed == null) {
      throw ArgumentError.value(
        namedArguments.keys.toList(),
        'namedArguments',
        '$T.$name takes no named parameters',
      );
    }
    return invokeNamed(object as T, arguments, namedArguments);
  }

  /// The first annotation of type [A] on the method, or `null`.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  /// Whether [object] can be passed to [invoke]: an instance of `T`. A
  /// proxy that implements only the bean's interfaces (`aop_proxies:
  /// interfaces`) is not; call the method on `AopUtils.getTarget(object)`
  /// then.
  bool appliesTo(Object object) => object is T;

  @override
  String toString() => 'IntrospectedMethod<$T>($name)';
}

/// The description of one parameter of a constructor or method: its name,
/// full type, whether it is named or required, and its annotations.
///
/// `ObjectMapper` reads those of an [IntrospectedConstructor] to know which
/// JSON fields to pass; request binding reads those of an
/// [IntrospectedMethod] to know what to bind (`@PathVariable()`,
/// `@RequestParam()`). Written by the generator.
///
/// ```dart
/// // Book({required this.isbn, this.tags = const []})
/// const isbn = IntrospectedParameter('isbn', type: ClassType<String>(),
///     symbol: #isbn, isRequired: true);
/// const tags = IntrospectedParameter('tags',
///     type: ListType<String>(ClassType<String>()), symbol: #tags,
///     hasDefaultValue: true, defaultValue: <String>[]);
/// ```
///
/// Spring (Java): `java.lang.reflect.Parameter` (with `-parameters`).
final class IntrospectedParameter {
  /// Describes the parameter [name] of [type]. A named parameter carries
  /// its [symbol] (a const symbol literal, safe in minified builds).
  const IntrospectedParameter(
    this.name, {
    required this.type,
    this.symbol,
    this.isRequired = false,
    this.hasDefaultValue = false,
    this.defaultValue,
    this.annotations = const [],
  });

  /// The parameter's name.
  final String name;

  /// The full declared type.
  final TypeInfo<Object?> type;

  /// `#name` for a named parameter; `null` for a positional one.
  final Symbol? symbol;

  /// Whether a value must be passed (positional without default, or
  /// `required`).
  final bool isRequired;

  /// Whether the parameter declares a default value that the generator
  /// could write into the description, so [defaultValue] is meaningful.
  ///
  /// Only constants it can re-create are described: `null`, `bool`, `int`,
  /// `double`, `String`, enum values, `const` lists, sets and maps of such
  /// values, and `const` objects of public classes. It is `false` for a
  /// parameter without a default (a required one, or an optional one that
  /// defaults to `null` implicitly) and for a default it cannot write
  /// (one that refers to a private constant). Written by the generator for
  /// the parameters of an [IntrospectedConstructor]; `false` elsewhere.
  final bool hasDefaultValue;

  /// The default value when [hasDefaultValue] is `true` (`null` for an
  /// explicit `= null`, and when there is none).
  ///
  /// A parameter written as `this.x = 5` or `super.x = 5` has the default
  /// it declares.
  final Object? defaultValue;

  /// The const annotations on the parameter.
  final List<Object> annotations;

  /// Whether the parameter is named.
  bool get isNamed => symbol != null;

  @override
  String toString() => 'IntrospectedParameter($name: $type)';
}

/// How generated code reads an optional named argument from the map of an
/// [IntrospectedConstructor] or [IntrospectedMethod] call, as
/// `Function.apply` passes it: the value when the map has it, else the
/// parameter's default.
///
/// ```dart
/// // Generated: Book(total: named.argumentOr(#total, 0))
/// ```
extension NamedArguments on Map<Symbol, Object?> {
  /// The argument [name] as a [T], or [absent] when it is not passed.
  T argumentOr<T>(Symbol name, T absent) =>
      containsKey(name) ? this[name] as T : absent;
}

/// How generated code reads an optional positional argument from the list
/// of an [IntrospectedConstructor] or [IntrospectedMethod] call, as
/// `Function.apply` passes it: the value when the list is long enough,
/// else the parameter's default.
///
/// ```dart
/// // Generated: greet(arguments[0] as String, arguments.argumentOr(1, 1))
/// ```
extension PositionalArguments on List<Object?> {
  /// The argument at [index] as a [T], or [absent] when it is not passed.
  T argumentOr<T>(int index, T absent) =>
      index < length ? this[index] as T : absent;
}

/// The description of the constructor an introspected class is created
/// with (the unnamed one, or the one marked `@JsonCreator()`), with a
/// closure that calls it.
///
/// It lets immutable classes (final fields, `required` and default values)
/// be created from data, for example by `ObjectMapper` from JSON. Written
/// by the generator.
///
/// ```dart
/// final constructor = IntrospectedConstructor<Book>(
///   parameters: const [
///     IntrospectedParameter('isbn', type: ClassType<String>(), symbol: #isbn,
///         isRequired: true),
///   ],
///   create: (positional, named) =>
///       Function.apply(Book.new, positional, named) as Book,
/// );
/// constructor.newInstance(const [], {#isbn: '978-0'});
/// ```
///
/// Spring (Java): `java.lang.reflect.Constructor`:
/// ```java
/// Book book = Book.class.getConstructor(String.class).newInstance("978-0");
/// ```
final class IntrospectedConstructor<T extends Object> {
  /// A constructor with [parameters], called through `create` with the
  /// positional and named arguments.
  const IntrospectedConstructor({
    required this.parameters,
    required this._create,
  });

  /// The parameters, in declaration order.
  final List<IntrospectedParameter> parameters;

  final T Function(List<Object?> positional, Map<Symbol, Object?> named)
  _create;

  /// Calls the constructor with [positional] and [named] arguments;
  /// omitted optional parameters keep their default values.
  T newInstance(
    List<Object?> positional, [
    Map<Symbol, Object?> named = const {},
  ]) => _create(positional, named);

  @override
  String toString() => 'IntrospectedConstructor<$T>(${parameters.join(', ')})';
}

/// Everything the generator knows about an introspected class: its
/// properties, methods, constructor and annotations, with closures to use
/// them.
///
/// It replaces reflection: `BeanWrapper`, data binding, validation, SpEL
/// and `ObjectMapper` read and create objects through it. The generator
/// writes one per `@Introspected` class (and per class the build finds in
/// use, see [IntrospectionPart]) and the module registers it in an
/// [Introspector]; you write one by hand only for a class the generator
/// cannot see. It describes a class, not a bean: the container's beans are
/// `BeanDefinition`s. Micronaut's `BeanIntrospection` is the same idea.
///
/// ```dart
/// // A hand-written introspection of Address, then used by name.
/// final addressIntrospection = Introspection<Address>(
///   properties: [
///     IntrospectedProperty<Address>(
///       'city',
///       type: String,
///       get: (address) => address.city,
///       set: (address, value) => address.city = value! as String,
///     ),
///   ],
///   instantiate: Address.new,
/// );
///
/// final address = addressIntrospection.instantiate();
/// addressIntrospection.getProperty('city')!.setValue(address, 'Lyon');
/// ```
///
/// Spring (Java): no direct counterpart. Spring uses runtime reflection
/// (`BeanUtils`, `java.beans.BeanInfo`, `PropertyDescriptor`):
/// ```java
/// BeanInfo info = Introspector.getBeanInfo(Address.class);
/// Address address = BeanUtils.instantiateClass(Address.class);
/// ```
final class Introspection<T extends Object> {
  /// The description of [T]. `instantiate` calls the no-argument
  /// constructor, if there is one; the other closures are written by the
  /// generator. [parts] lists what the description holds (the generator
  /// leaves out what the build saw nothing use); a hand-written one holds
  /// everything.
  ///
  /// The generator writes it as a constant when it can (a class without
  /// type parameters, closures as top-level functions); the lookups by
  /// name are then indexed on first use.
  const Introspection({
    List<IntrospectedProperty<T>> properties = const [],
    List<IntrospectedMethod<T>> methods = const [],
    this.annotations = const [],
    this.parts = const {
      IntrospectionPart.read,
      IntrospectionPart.write,
      IntrospectionPart.methods,
    },
    this._instantiate,
    this.constructor,
    this._fromJson,
    this._toJson,
    this._className,
    this.library,
    this._specialize,
    this.objectMethods,
  }) : _propertyList = properties,
       _methodList = methods;

  final List<IntrospectedProperty<T>> _propertyList;
  final List<IntrospectedMethod<T>> _methodList;

  // The lookups by name, built on first use (a constant cannot hold them).
  static final _propertyIndex = Expando<Map<String, Object>>(
    'Introspection.properties',
  );
  static final _methodIndex = Expando<Map<String, Object>>(
    'Introspection.methods',
  );

  // Later entries with the same name win, as in a map literal.
  Map<String, IntrospectedProperty<T>> get _properties =>
      (_propertyIndex[this] ??= <String, IntrospectedProperty<T>>{
            for (final p in _propertyList) p.name: p,
          })
          as Map<String, IntrospectedProperty<T>>;

  Map<String, IntrospectedMethod<T>> get _methods =>
      (_methodIndex[this] ??= <String, IntrospectedMethod<T>>{
            for (final m in _methodList) m.name: m,
          })
          as Map<String, IntrospectedMethod<T>>;
  final T Function()? _instantiate;
  final T Function(Object? json)? _fromJson;
  final Object? Function(T object)? _toJson;
  final String? _className;
  final Introspection<Object> Function(List<TypeInfo<Object?>> arguments)?
  _specialize;

  /// What this description holds of the class; the generator leaves out
  /// the parts it saw nothing use (see [IntrospectionPart]).
  ///
  /// A part that is missing leaves its closures out: no getters without
  /// [IntrospectionPart.read], no constructor, `instantiate`, setters or
  /// `fromJson` without [IntrospectionPart.write], no methods without
  /// [IntrospectionPart.methods] (but those that JSON annotations mark,
  /// which `ObjectMapper` needs).
  final Set<IntrospectionPart> parts;

  /// Whether this description holds [part].
  bool describesPart(IntrospectionPart part) => parts.contains(part);

  /// Throws an [IntrospectionPartError] unless this description holds
  /// [part]; [use] says what needs it (`it is written out as JSON`).
  void requirePart(IntrospectionPart part, String use) {
    if (!parts.contains(part)) {
      throw IntrospectionPartError(T, part, use);
    }
  }

  /// The simple name of the class, without type arguments (written by the
  /// generator, so it survives minification; e.g. the default JSON type id).
  String get className => _className ?? '$T'.replaceFirst(RegExp('<.*'), '');

  /// The URI of the library that declares the class
  /// (`package:shop/src/book.dart`), written by the generator; `null` in a
  /// hand-written description that does not give it.
  final String? library;

  /// The name of the class that tells it apart from another of the same
  /// [className]: `<library>#<className>`, or the [className] alone
  /// without a [library]. The same in every run and in a minified build:
  /// what a value kept outside the program (a disk cache entry) names its
  /// class by, as Jackson's default typing writes the fully qualified name.
  String get qualifiedName =>
      library == null ? className : '$library#$className';

  /// Whether this describes a generic class with its type parameters
  /// erased (`Page<Object?>` for `Page<T>`) that can be [specialize]d.
  bool get isGeneric => _specialize != null;

  /// The introspection of this generic class with the type [arguments]
  /// (`Page<Book>` for `[ClassType<Book>()]`): constructor parameters and
  /// properties typed with them. Throws `StateError` when not [isGeneric].
  Introspection<Object> specialize(List<TypeInfo<Object?>> arguments) =>
      (_specialize ?? (throw StateError('$T is not generic')))(arguments);

  /// Whether [S] is a parameterization of the class this describes
  /// (`Page<Book>` for `Page<Object?>`).
  bool isRawTypeOf<S>() => <S>[] is List<T?>;

  /// The constructor to create instances from data (`ObjectMapper`), when
  /// the class has a usable one.
  final IntrospectedConstructor<T>? constructor;

  /// The `==`, `hashCode` and `toString()` the generator wrote for the
  /// class's `@EqualsAndHashCode` and `@ToString`, which
  /// [IntrospectedObject] calls; `null` without those annotations.
  final ObjectMethods<T>? objectMethods;

  /// Whether the class has its own `fromJson` constructor (e.g. from
  /// `json_serializable` or `freezed`), which `ObjectMapper` then uses.
  bool get hasFromJson => _fromJson != null;

  /// Whether the class has its own `toJson()` method.
  bool get hasToJson => _toJson != null;

  /// Calls the class's own `fromJson` with [json].
  T fromJson(Object? json) =>
      (_fromJson ?? (throw StateError('$T has no fromJson constructor')))(json);

  /// Calls the class's own `toJson()` on [object].
  Object? toJson(Object object) =>
      (_toJson ?? (throw StateError('$T has no toJson method')))(object as T);

  /// Whether [S] is [T] or `T?`.
  bool describes<S>() => S == T || (<S>[] is List<T?> && <T?>[] is List<S>);

  /// The const annotations on the class.
  final List<Object> annotations;

  /// The introspected class.
  Type get type => T;

  /// The [TypeInfo] of the class, to read a JSON tree as one when only this
  /// description is at hand (a value kept on disk by the name of its type).
  ClassType<T> get classType => ClassType<T>();

  /// [items], each a [T], as a `List<T>`.
  List<T> listOf(Iterable<Object?> items) => [
    for (final item in items) item! as T,
  ];

  /// [items], each a [T], as a `Set<T>`.
  Set<T> setOf(Iterable<Object?> items) => {
    for (final item in items) item! as T,
  };

  /// [entries], each value a [T], as a `Map<String, T>`.
  Map<String, T> mapOf(Map<String, Object?> entries) => {
    for (final MapEntry(:key, :value) in entries.entries) key: value! as T,
  };

  /// Whether [value] is a [T] (or a subtype).
  bool isInstance(Object? value) => value is T;

  /// Whether [T] is a subtype of the class [other] describes.
  bool isSubtypeOf(Introspection<Object> other) => other._isSupertypeOf<T>();

  bool _isSupertypeOf<S>() => <S>[] is List<T>;

  /// All properties, in declaration order.
  Iterable<IntrospectedProperty<T>> get properties => _properties.values;

  /// All public instance methods, in declaration order.
  Iterable<IntrospectedMethod<T>> get methods => _methods.values;

  /// The property named [name], or `null`.
  IntrospectedProperty<T>? getProperty(String name) => _properties[name];

  /// The method named [name], or `null` (Dart has no overloads).
  IntrospectedMethod<T>? getMethod(String name) => _methods[name];

  /// Whether [instantiate] is available (a no-argument constructor).
  bool get isInstantiable => _instantiate != null;

  /// Creates a new instance with the no-argument constructor; throws
  /// `StateError` when [isInstantiable] is `false`, an
  /// [IntrospectionPartError] when the description has no
  /// [IntrospectionPart.write].
  T instantiate() {
    final factory = _instantiate;
    if (factory == null) {
      requirePart(IntrospectionPart.write, 'an instance is created');
      throw StateError('$T has no no-argument constructor');
    }
    return factory();
  }

  // This description together with [earlier], another one of the same class
  // that was registered before it: each holds what the build saw one module
  // use of the class (a read-only DTO in one, a request body in another), and
  // the class is used by both. Whatever this one has wins; what it leaves
  // out is taken from [earlier]. The parts are the union.
  Introspection<T> _withEarlier(Introspection<Object> earlier) {
    final before = earlier as Introspection<T>;
    final properties = <String, IntrospectedProperty<T>>{
      for (final MapEntry(:key, :value) in before._properties.entries)
        key: _properties[key]?._withEarlier(value) ?? value,
      for (final MapEntry(:key, :value) in _properties.entries)
        if (!before._properties.containsKey(key)) key: value,
    };
    final specialize = _specialize;
    final earlierSpecialize = before._specialize;
    return Introspection<T>(
      properties: properties.values.toList(),
      methods: [...before._methods.values, ..._methods.values],
      annotations: [
        ...annotations,
        for (final annotation in before.annotations)
          if (!annotations.contains(annotation)) annotation,
      ],
      parts: {...before.parts, ...parts},
      instantiate: _instantiate ?? before._instantiate,
      constructor: constructor ?? before.constructor,
      fromJson: _fromJson ?? before._fromJson,
      toJson: _toJson ?? before._toJson,
      className: _className ?? before._className,
      library: library ?? before.library,
      objectMethods: objectMethods ?? before.objectMethods,
      specialize: specialize == null
          ? earlierSpecialize
          : earlierSpecialize == null
          ? specialize
          : (arguments) =>
                specialize(arguments)
                    ._withEarlier(earlierSpecialize(arguments)),
    );
  }

  @override
  String toString() => 'Introspection<$T>';
}

/// The registry that finds the [Introspection] of a class or object.
///
/// Code that reads objects without reflection asks it for their
/// description. Each application context has its own introspector (the
/// bean `introspector`), filled from its modules, with [shared] as
/// parent; lookups that fail here go to the [parent]. Applications rarely
/// use it directly; `BeanWrapper` and `ObjectMapper` do. Micronaut's
/// `BeanIntrospector` is the same idea.
///
/// ```dart
/// // List the property names of any introspected object.
/// final introspector = Introspector(
///   introspections: [personIntrospection, addressIntrospection],
/// );
/// final meta = introspector.getIntrospection(person);
/// log.info(meta.properties.map((p) => p.name));
/// ```
///
/// Spring (Java): no counterpart; Spring introspects any class at runtime
/// (cached by `CachedIntrospectionResults`):
/// ```java
/// PropertyDescriptor[] props = BeanUtils.getPropertyDescriptors(Person.class);
/// ```
class Introspector {
  /// Creates a registry holding [introspections], delegating misses to
  /// [parent].
  Introspector({
    Iterable<Introspection<Object>> introspections = const [],
    this.parent,
  }) {
    introspections.forEach(register);
  }

  /// The process-wide registry, the default of `BeanWrapper`; each context
  /// uses a child of it.
  static final Introspector shared = Introspector();

  /// The registry consulted when this one has no match.
  final Introspector? parent;
  final _byType = <Type, Introspection<Object>>{};
  final _enums = <Type, EnumType<Enum>>{};

  /// The description of the class whose [Introspection.qualifiedName] is
  /// [name] (the same in a minified build), here or in [parent]; `null`
  /// when none is registered, or when two classes here share the name (two
  /// classes `Book` described without their library): which one was meant
  /// cannot be told.
  Introspection<Object>? byQualifiedName(String name) {
    final byName = _byQualifiedName ??= _indexByQualifiedName();
    if (byName.containsKey(name)) {
      return byName[name];
    }
    return parent?.byQualifiedName(name);
  }

  Map<String, Introspection<Object>?> _indexByQualifiedName() {
    final byName = <String, Introspection<Object>?>{};
    for (final introspection in _byType.values) {
      final name = introspection.qualifiedName;
      byName[name] = byName.containsKey(name) ? null : introspection;
    }
    return byName;
  }

  Map<String, Introspection<Object>?>? _byQualifiedName;

  /// Adds [introspection], replacing any for the same type. The enums its
  /// properties and constructor parameters use are registered too (see
  /// [registerEnum]).
  ///
  /// A description that holds less than the one it would replace (it lacks
  /// a [IntrospectionPart] the other has) does not take it away: the two
  /// are merged, so a class that two modules of one package describe for
  /// their own uses (one writes it out, the other reads it in) can be used
  /// for both, whichever module loads last. Where both have a getter, a
  /// setter, a method or the constructor, the new one is kept; the parts
  /// are the union.
  void register(Introspection<Object> introspection) {
    final existing = _byType[introspection.type];
    _byType[introspection.type] =
        existing == null ||
            identical(existing, introspection) ||
            introspection.parts.containsAll(existing.parts)
        ? introspection
        : introspection._withEarlier(existing);
    _specialized.clear();
    _byQualifiedName = null;
    final registered = _byType[introspection.type]!;
    if (registered.objectMethods case final methods?) {
      _registerObjectMethods(registered.type, methods);
    }
    for (final property in registered.properties) {
      _collectEnums(property.typeInfo);
    }
    for (final parameter
        in registered.constructor?.parameters ??
            const <IntrospectedParameter>[]) {
      _collectEnums(parameter.type);
    }
  }

  void _collectEnums(TypeInfo<Object?>? type) {
    switch (type) {
      case final EnumType<Enum> enumType:
        _enums.putIfAbsent(enumType.type, () => enumType);
      case ListType(:final element):
        _collectEnums(element);
      case SetType(:final element):
        _collectEnums(element);
      case MapType(:final key, :final value):
        _collectEnums(key);
        _collectEnums(value);
      case GenericType(:final arguments):
        arguments.forEach(_collectEnums);
      case ClassType() || DynamicType() || null:
        break;
    }
  }

  /// Makes the values of an enum (and its `@JsonValue` form) known, so
  /// values of it are converted where no [EnumType] is at hand:
  /// `ObjectMapper.readValue<Color>(...)`, `readList<Color>`, enums in
  /// `Object?` properties or map values. The enums the properties and
  /// constructor parameters of registered introspections use are
  /// registered automatically; the first registration of an enum wins.
  ///
  /// ```dart
  /// Introspector.shared.registerEnum(EnumType<Color>(Color.values));
  /// ```
  void registerEnum(EnumType<Enum> type) =>
      _enums.putIfAbsent(type.type, () => type);

  /// The registered [EnumType] of the enum [type] (here, else in the
  /// [parent]).
  EnumType<Enum>? enumTypeFor(Type type) =>
      _enums[type] ?? parent?.enumTypeFor(type);

  /// The registered [EnumType] of the enum [T] (also when [T] is a
  /// nullable `Color?`).
  EnumType<Enum>? enumTypeOf<T>() {
    final exact = _enums[T];
    if (exact != null) {
      return exact;
    }
    for (final type in _enums.values) {
      if (type.capture(<E>() => <T>[] is List<E?> && <E?>[] is List<T>)) {
        return type;
      }
    }
    return parent?.enumTypeOf<T>();
  }

  /// Every registered introspection, this registry's first, then the
  /// [parent]'s.
  Iterable<Introspection<Object>> get introspections sync* {
    yield* _byType.values;
    if (parent case final parent?) {
      yield* parent.introspections;
    }
  }

  final _specialized = <Type, Introspection<Object>?>{};

  /// The introspection of the generic type [T] (`Page<Book>`): the generic
  /// introspection of its class specialized with the type [arguments];
  /// `null` when its class is not introspected (or not generic). Cached per
  /// type.
  Introspection<Object>? forGenericType<T>(
    List<TypeInfo<Object?>> arguments,
  ) {
    if (_specialized.containsKey(T)) {
      return _specialized[T];
    }
    Introspection<Object>? found;
    for (final introspection in introspections) {
      if (introspection.isGeneric && introspection.isRawTypeOf<T>()) {
        final specialized = introspection.specialize(arguments);
        if (specialized.describes<T>()) {
          found = specialized;
          break;
        }
      }
    }
    return _specialized[T] = found;
  }

  /// Adds every one of [introspections] (see [register]): for instance the
  /// descriptions a module's generated `<library>.spring.introspection.dart`
  /// lists, so a unit test reads and writes the application's classes without
  /// starting a context.
  ///
  /// ```dart
  /// import 'package:shop/spring_gen/src/app.spring.introspection.dart';
  ///
  /// void main() {
  ///   setUpAll(
  ///     () => Introspector.shared.registerAll($appBeansIntrospections),
  ///   );
  ///   test('reads a book', () {
  ///     expect(ObjectMapper().readValue<Book>('{"title":"Dune"}').title,
  ///         'Dune');
  ///   });
  /// }
  /// ```
  void registerAll(Iterable<Introspection<Object>> introspections) =>
      introspections.forEach(register);

  final _typeTests = <Type, bool Function(Object? value)>{};

  /// Adds [tests], each telling whether a value is of its type (or a
  /// subtype); the generated modules give one per type written in an
  /// annotation.
  void registerTypeTests(Map<Type, bool Function(Object? value)> tests) =>
      _typeTests.addAll(tests);

  final _typeDepths = <Type, int>{};

  /// Adds [depths], the supertype chain length of each type (see
  /// `BeanModule.typeDepths`).
  void registerTypeDepths(Map<Type, int> depths) => _typeDepths.addAll(depths);

  /// The length of the longest chain of supertypes from [type] up to
  /// `Object`, as registered here or in the [parent]; `null` when no module
  /// described it. Of two types a value is an instance of, the one with
  /// the greater depth is the closer to the value's class.
  int? typeDepth(Type type) => _typeDepths[type] ?? parent?.typeDepth(type);

  /// Whether [value] is of [type] or of a subtype of it.
  ///
  /// Dart cannot test `value is T` for a `Type` value without reflection;
  /// this uses the test registered for [type] here or in the [parent]
  /// (the generator registers one for every type written in an annotation,
  /// such as `@Transactional(noRollbackFor: [OutOfStock])`), and without
  /// one compares the exact runtime type.
  bool isInstanceOf(Type type, Object? value) {
    if (_typeTest(type) case final test?) {
      return test(value);
    }
    return value != null && value.runtimeType == type;
  }

  bool Function(Object? value)? _typeTest(Type type) =>
      _typeTests[type] ?? parent?._typeTest(type);

  /// The introspection registered for exactly [type], here or in the
  /// [parent]; `null` when there is none.
  Introspection<Object>? forType(Type type) =>
      _byType[type] ?? parent?.forType(type);

  /// The introspection of [T] (also when [T] is a nullable `Book?`), here
  /// or in the [parent]; `null` when there is none.
  Introspection<Object>? forTypeArgument<T>() {
    final exact = _byType[T];
    if (exact != null) {
      return exact;
    }
    for (final introspection in _byType.values) {
      if (introspection.describes<T>()) {
        return introspection;
      }
    }
    return parent?.forTypeArgument<T>();
  }

  /// The introspection for [object]: its exact runtime type (here or in a
  /// parent), else the most specific registered supertype (here, then in
  /// the parent).
  Introspection<Object>? findIntrospection(Object object) =>
      _exact(object.runtimeType) ?? _mostSpecific(object);

  Introspection<Object>? _exact(Type type) =>
      _byType[type] ?? parent?._exact(type);

  // A linear scan with `is` checks, so subclasses of introspected classes
  // are handled too: the most specific match wins (a `Manager extends
  // Employee extends Person` instance uses Employee's metadata, not
  // Person's).
  Introspection<Object>? _mostSpecific(Object object) {
    Introspection<Object>? best;
    for (final introspection in _byType.values) {
      if (introspection.isInstance(object) &&
          (best == null || introspection.isSubtypeOf(best))) {
        best = introspection;
      }
    }
    return best ?? parent?._mostSpecific(object);
  }

  // The object methods of the descriptions any introspector registered,
  // by the described type. `==` has no context at hand, so they are known
  // to the whole isolate: a class's functions are the same in every
  // context.
  static final _registeredObjectMethods = <Type, ObjectMethods<Object>>{};

  // The object methods by runtime type: the registered ones, and those a
  // lookup found for a subclass or a parameterization of a generic class
  // (their types in [_foundObjectMethods], forgotten at a registration).
  static final _objectMethods = <Type, ObjectMethods<Object>>{};
  static final _foundObjectMethods = <Type>{};

  // The last lookup: a loop, a set or a sort compares objects of one class.
  static Type? _lastType;
  static ObjectMethods<Object>? _lastMethods;

  static void _registerObjectMethods(
    Type type,
    ObjectMethods<Object> methods,
  ) {
    _registeredObjectMethods[type] = methods;
    _foundObjectMethods
      ..forEach(_objectMethods.remove)
      ..clear();
    _objectMethods[type] = methods;
    _lastType = null;
    _lastMethods = null;
  }

  /// The `==`, `hashCode` and `toString()` generated for [object]'s class
  /// (`@EqualsAndHashCode`, `@ToString`), which [IntrospectedObject] calls:
  /// those of its runtime type's description, else of its closest described
  /// supertype (a subclass the build did not annotate, `Page<Book>` of a
  /// generic `Page`), whichever introspector registered it (a context's,
  /// or [shared]). Cached per runtime type.
  ///
  /// Throws a `StateError` that says how to register them when no
  /// description of the class is registered.
  static ObjectMethods<Object> objectMethodsOf(Object object) {
    final type = object.runtimeType;
    if (identical(type, _lastType)) {
      return _lastMethods!;
    }
    final methods = _objectMethods[type] ?? _findObjectMethods(object, type);
    _lastType = type;
    _lastMethods = methods;
    return methods;
  }

  /// The object methods registered for exactly [type] (a class's
  /// description, see [objectMethodsOf]); `null` when there are none.
  static ObjectMethods<Object>? objectMethodsForType(Type type) =>
      _registeredObjectMethods[type];

  static ObjectMethods<Object> _findObjectMethods(Object object, Type type) {
    ObjectMethods<Object>? best;
    for (final methods in _registeredObjectMethods.values) {
      if (methods.isInstance(object) &&
          (best == null || methods.isSubtypeOf(best))) {
        best = methods;
      }
    }
    if (best == null) {
      throw StateError(
        'No description of $type is registered, so its ==, hashCode and '
        'toString() (IntrospectedObject, generated for @EqualsAndHashCode '
        "and @ToString) cannot run. Start the application (or the test's "
        'context) first, or register the generated descriptions in a unit '
        r'test: Introspector.shared.registerAll($<module>Introspections), '
        "the getter of the module's "
        'lib/spring_gen/<library>.spring.introspection.dart.',
      );
    }
    _foundObjectMethods.add(type);
    return _objectMethods[type] = best;
  }

  /// Like [findIntrospection], but throws `ArgumentError` when [object]'s
  /// class is not introspected (or its module is not registered).
  Introspection<Object> getIntrospection(Object object) =>
      findIntrospection(object) ??
      (throw ArgumentError.value(
        object,
        'object',
        '${object.runtimeType} is not @Introspected (or its module is not '
            'registered)',
      ));
}
