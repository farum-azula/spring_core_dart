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
/// // The generated BeanIntrospection is registered by the module, so:
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

/// A part of an introspected class that a [BeanIntrospection] may leave
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
  /// [beanType] is described without [part]; [use] says what needs it, a
  /// clause that follows "but" (`it is written out as JSON`).
  IntrospectionPartError(this.beanType, this.part, String use)
    : super(
        '$beanType is described without ${part.description}, but $use. The '
        'build described only what it saw used, and did not see that: add '
        '@Introspected() to $beanType.',
      );

  /// The class whose description lacks [part].
  final Type beanType;

  /// The part that is needed.
  final IntrospectionPart part;
}

/// The description of one property of an introspected class: its name,
/// type, annotations, and closures that read and write it.
///
/// The generator writes these for `@Introspected` classes; `BeanWrapper`,
/// validation and SpEL use them to reach a field by name. You write one by
/// hand only in a hand-written [BeanIntrospection].
///
/// Both closures are optional: the generator writes only the ones the
/// application uses (see [IntrospectionPart]), so a property that is only
/// read from JSON has a setter and no getter ([isReadable] is `false`).
///
/// ```dart
/// // A property of Address, written by hand.
/// final city = BeanProperty<Address>(
///   'city',
///   type: String,
///   get: (b) => b.city,
///   set: (b, v) => b.city = v! as String,
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
final class BeanProperty<T extends Object> {
  /// Describes the property [name] of [T] with the declared [type]; omit
  /// `set` for a read-only property and `get` for a write-only one.
  BeanProperty(
    this.name, {
    required this.type,
    this._get,
    this._set,
    this.nullable = false,
    this.typeInfo,
    this.hasInitialValue = false,
    this.initialValue,
    List<Object> annotations = const [],
  }) : annotations = List.unmodifiable(annotations);

  /// The name of the field or getter.
  final String name;

  /// The declared type, without its nullability (see [nullable]).
  final Type type;

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

  final Object? Function(T bean)? _get;
  final void Function(T bean, Object? value)? _set;

  /// Whether the property can be read; `false` when the description has no
  /// getter for it (the build saw nothing read the class).
  bool get isReadable => _get != null;

  /// Whether the property can be written; `false` for a final field or a
  /// getter without a setter.
  bool get isWritable => _set != null;

  /// The value of the property in [bean], which must be a [T]. Throws an
  /// [IntrospectionPartError] when the property has no getter
  /// ([isReadable]).
  Object? getValue(Object bean) {
    final getter = _get;
    if (getter == null) {
      throw IntrospectionPartError(
        T,
        IntrospectionPart.read,
        "the value of property '$name' is read",
      );
    }
    return getter(bean as T);
  }

  /// Writes [value] into the property of [bean]. The value must already
  /// have the property's type (`BeanWrapper` converts first). Throws
  /// `StateError` for a read-only property.
  void setValue(Object bean, Object? value) {
    final setter = _set;
    if (setter == null) {
      throw StateError("Property '$name' of $T is read-only");
    }
    setter(bean as T, value);
  }

  // This property with what [earlier], the description of the same property
  // registered before it, has and this one lacks: its getter or setter.
  BeanProperty<T> _withEarlier(BeanProperty<T> earlier) {
    if (_get != null && _set != null) {
      return this;
    }
    return BeanProperty<T>(
      name,
      type: type,
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
  String toString() => 'BeanProperty<$T>($name: $type${nullable ? '?' : ''})';
}

/// The description of one public instance method of an introspected class
/// or bean, with a closure that calls it.
///
/// SpEL uses it to call methods on introspected objects, and frameworks
/// use the ones in `BeanDefinition.annotatedMethods` to call annotated
/// methods of beans (`@Scheduled`, request handlers). You write one by
/// hand only in a hand-written introspection.
///
/// ```dart
/// // Person.hello(String name), called by name from an expression.
/// final hello = BeanMethod<Person>(
///   'hello',
///   returnType: String,
///   parameterTypes: const [String],
///   invoke: (b, args) => b.hello(args.first! as String),
/// );
/// hello.invoke(person, ['Ann']);
/// ```
///
/// Spring (Java): `java.lang.reflect.Method`:
/// ```java
/// Method hello = Person.class.getMethod("hello", String.class);
/// hello.invoke(person, "Ann");
/// ```
final class BeanMethod<T extends Object> {
  /// Describes the method [name] of [T], called through `invoke` (and
  /// `invokeNamed` when it has named parameters).
  BeanMethod(
    this.name, {
    required this._invoke,
    this._invokeNamed,
    this.returnType,
    List<Type> parameterTypes = const [],
    List<BeanParameter> parameters = const [],
    this.returnTypeInfo,
    this.isFuture = false,
    this.isVoid = false,
    List<Object> annotations = const [],
  }) : parameterTypes = List.unmodifiable(parameterTypes),
       parameters = List.unmodifiable(parameters),
       annotations = List.unmodifiable(annotations);

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
  final List<BeanParameter> parameters;

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
  final Object? Function(T bean, List<Object?> arguments) _invoke;
  final Object? Function(
    T bean,
    List<Object?> positional,
    Map<Symbol, Object?> named,
  )?
  _invokeNamed;

  /// Calls the method on [bean] with positional [arguments] (already of
  /// the parameter types) and [namedArguments] (by [BeanParameter.symbol];
  /// an omitted optional one keeps its default value); returns its result
  /// (`null` for `void`). Throws `ArgumentError` when named arguments are
  /// given to a method described without them.
  Object? invoke(
    Object bean,
    List<Object?> arguments, [
    Map<Symbol, Object?> namedArguments = const {},
  ]) {
    if (namedArguments.isEmpty) {
      return _invoke(bean as T, arguments);
    }
    final invokeNamed = _invokeNamed;
    if (invokeNamed == null) {
      throw ArgumentError.value(
        namedArguments.keys.toList(),
        'namedArguments',
        '$T.$name takes no named parameters',
      );
    }
    return invokeNamed(bean as T, arguments, namedArguments);
  }

  /// The first annotation of type [A] on the method, or `null`.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  /// Whether [bean] can be passed to [invoke]: an instance of `T`. A proxy
  /// that implements only the bean's interfaces (`aop_proxies: interfaces`)
  /// is not; call the method on `AopUtils.getTarget(bean)` then.
  bool appliesTo(Object bean) => bean is T;

  @override
  String toString() => 'BeanMethod<$T>($name)';
}

/// The description of one parameter of a constructor or method: its name,
/// full type, whether it is named or required, and its annotations.
///
/// `ObjectMapper` reads those of a [BeanConstructor] to know which JSON
/// fields to pass; request binding reads those of a [BeanMethod] to know
/// what to bind (`@PathVariable()`, `@RequestParam()`). Written by the
/// generator.
///
/// ```dart
/// // Book({required this.isbn, this.tags = const []})
/// const isbn = BeanParameter('isbn', type: ClassType<String>(),
///     symbol: #isbn, isRequired: true);
/// const tags = BeanParameter('tags',
///     type: ListType<String>(ClassType<String>()), symbol: #tags,
///     hasDefaultValue: true, defaultValue: <String>[]);
/// ```
///
/// Spring (Java): `java.lang.reflect.Parameter` (with `-parameters`).
final class BeanParameter {
  /// Describes the parameter [name] of [type]. A named parameter carries
  /// its [symbol] (a const symbol literal, safe in minified builds).
  const BeanParameter(
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
  /// the parameters of a [BeanConstructor]; `false` elsewhere.
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
  String toString() => 'BeanParameter($name: $type)';
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
/// final constructor = BeanConstructor<Book>(
///   parameters: const [
///     BeanParameter('isbn', type: ClassType<String>(), symbol: #isbn,
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
final class BeanConstructor<T extends Object> {
  /// A constructor with [parameters], called through `create` with the
  /// positional and named arguments.
  BeanConstructor({
    required List<BeanParameter> parameters,
    required this._create,
  }) : parameters = List.unmodifiable(parameters);

  /// The parameters, in declaration order.
  final List<BeanParameter> parameters;

  final T Function(List<Object?> positional, Map<Symbol, Object?> named)
  _create;

  /// Calls the constructor with [positional] and [named] arguments;
  /// omitted optional parameters keep their default values.
  T newInstance(
    List<Object?> positional, [
    Map<Symbol, Object?> named = const {},
  ]) => _create(positional, named);

  @override
  String toString() => 'BeanConstructor<$T>(${parameters.join(', ')})';
}

/// Everything the generator knows about an introspected class: its
/// properties, methods, constructor and annotations, with closures to use
/// them.
///
/// It replaces reflection: `BeanWrapper`, data binding, validation, SpEL
/// and `ObjectMapper` read and create objects through it. The generator
/// writes one per `@Introspected` class and the module registers it in a
/// [BeanIntrospector]; you write one by hand only for a class the
/// generator cannot see. Micronaut's `BeanIntrospection` is the same idea.
///
/// ```dart
/// // A hand-written introspection of Address, then used by name.
/// final addressIntrospection = BeanIntrospection<Address>(
///   properties: [
///     BeanProperty<Address>(
///       'city',
///       type: String,
///       get: (b) => b.city,
///       set: (b, v) => b.city = v! as String,
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
final class BeanIntrospection<T extends Object> {
  /// The description of [T]. `instantiate` calls the no-argument
  /// constructor, if there is one; the other closures are written by the
  /// generator. [parts] lists what the description holds (the generator
  /// leaves out what the build saw nothing use); a hand-written one holds
  /// everything.
  BeanIntrospection({
    List<BeanProperty<T>> properties = const [],
    List<BeanMethod<T>> methods = const [],
    List<Object> annotations = const [],
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
    this._specialize,
  }) : _properties = {for (final p in properties) p.name: p},
       _methods = {for (final m in methods) m.name: m},
       annotations = List.unmodifiable(annotations);

  final Map<String, BeanProperty<T>> _properties;
  final Map<String, BeanMethod<T>> _methods;
  final T Function()? _instantiate;
  final T Function(Object? json)? _fromJson;
  final Object? Function(T bean)? _toJson;
  final String? _className;
  final BeanIntrospection<Object> Function(List<TypeInfo<Object?>> arguments)?
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

  /// Whether this describes a generic class with its type parameters
  /// erased (`Page<Object?>` for `Page<T>`) that can be [specialize]d.
  bool get isGeneric => _specialize != null;

  /// The introspection of this generic class with the type [arguments]
  /// (`Page<Book>` for `[ClassType<Book>()]`): constructor parameters and
  /// properties typed with them. Throws `StateError` when not [isGeneric].
  BeanIntrospection<Object> specialize(List<TypeInfo<Object?>> arguments) =>
      (_specialize ?? (throw StateError('$T is not generic')))(arguments);

  /// Whether [S] is a parameterization of the class this describes
  /// (`Page<Book>` for `Page<Object?>`).
  bool isRawTypeOf<S>() => <S>[] is List<T?>;

  /// The constructor to create instances from data (`ObjectMapper`), when
  /// the class has a usable one.
  final BeanConstructor<T>? constructor;

  /// Whether the class has its own `fromJson` constructor (e.g. from
  /// `json_serializable` or `freezed`), which `ObjectMapper` then uses.
  bool get hasFromJson => _fromJson != null;

  /// Whether the class has its own `toJson()` method.
  bool get hasToJson => _toJson != null;

  /// Calls the class's own `fromJson` with [json].
  T fromJson(Object? json) =>
      (_fromJson ?? (throw StateError('$T has no fromJson constructor')))(json);

  /// Calls the class's own `toJson()` on [bean].
  Object? toJson(Object bean) =>
      (_toJson ?? (throw StateError('$T has no toJson method')))(bean as T);

  /// Whether [S] is [T] or `T?`.
  bool describes<S>() => S == T || (<S>[] is List<T?> && <T?>[] is List<S>);

  /// The const annotations on the class.
  final List<Object> annotations;

  /// The introspected class.
  Type get beanType => T;

  /// Whether [value] is a [T] (or a subtype).
  bool isInstance(Object? value) => value is T;

  /// Whether [T] is a subtype of the class [other] describes.
  bool isSubtypeOf(BeanIntrospection<Object> other) =>
      other._isSupertypeOf<T>();

  bool _isSupertypeOf<S>() => <S>[] is List<T>;

  /// All properties, in declaration order.
  Iterable<BeanProperty<T>> get properties => _properties.values;

  /// All public instance methods, in declaration order.
  Iterable<BeanMethod<T>> get methods => _methods.values;

  /// The property named [name], or `null`.
  BeanProperty<T>? getProperty(String name) => _properties[name];

  /// The method named [name], or `null` (Dart has no overloads).
  BeanMethod<T>? getMethod(String name) => _methods[name];

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
  BeanIntrospection<T> _withEarlier(BeanIntrospection<Object> earlier) {
    final before = earlier as BeanIntrospection<T>;
    final properties = <String, BeanProperty<T>>{
      for (final MapEntry(:key, :value) in before._properties.entries)
        key: _properties[key]?._withEarlier(value) ?? value,
      for (final MapEntry(:key, :value) in _properties.entries)
        if (!before._properties.containsKey(key)) key: value,
    };
    final specialize = _specialize;
    final earlierSpecialize = before._specialize;
    return BeanIntrospection<T>(
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
  String toString() => 'BeanIntrospection<$T>';
}

/// The registry that finds the [BeanIntrospection] of a class or object.
///
/// Code that reads objects without reflection asks it for their
/// description. Each application context has its own introspector (the
/// bean `beanIntrospector`), filled from its modules, with [shared] as
/// parent; lookups that fail here go to the [parent]. Applications rarely
/// use it directly; `BeanWrapper` and `ObjectMapper` do. Micronaut's
/// `BeanIntrospector` is the same idea.
///
/// ```dart
/// // List the property names of any introspected object.
/// final introspector = BeanIntrospector(
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
class BeanIntrospector {
  /// Creates a registry holding [introspections], delegating misses to
  /// [parent].
  BeanIntrospector({
    Iterable<BeanIntrospection<Object>> introspections = const [],
    this.parent,
  }) {
    introspections.forEach(register);
  }

  /// The process-wide registry, the default of `BeanWrapper`; each context
  /// uses a child of it.
  static final BeanIntrospector shared = BeanIntrospector();

  /// The registry consulted when this one has no match.
  final BeanIntrospector? parent;
  final _byType = <Type, BeanIntrospection<Object>>{};
  final _enums = <Type, EnumType<Enum>>{};

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
  void register(BeanIntrospection<Object> introspection) {
    final existing = _byType[introspection.beanType];
    _byType[introspection.beanType] =
        existing == null ||
            identical(existing, introspection) ||
            introspection.parts.containsAll(existing.parts)
        ? introspection
        : introspection._withEarlier(existing);
    _specialized.clear();
    final registered = _byType[introspection.beanType]!;
    for (final property in registered.properties) {
      _collectEnums(property.typeInfo);
    }
    for (final parameter
        in registered.constructor?.parameters ?? const <BeanParameter>[]) {
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
  /// BeanIntrospector.shared.registerEnum(EnumType<Color>(Color.values));
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
  Iterable<BeanIntrospection<Object>> get introspections sync* {
    yield* _byType.values;
    if (parent case final parent?) {
      yield* parent.introspections;
    }
  }

  final _specialized = <Type, BeanIntrospection<Object>?>{};

  /// The introspection of the generic type [T] (`Page<Book>`): the generic
  /// introspection of its class specialized with the type [arguments];
  /// `null` when its class is not introspected (or not generic). Cached per
  /// type.
  BeanIntrospection<Object>? forGenericType<T>(
    List<TypeInfo<Object?>> arguments,
  ) {
    if (_specialized.containsKey(T)) {
      return _specialized[T];
    }
    BeanIntrospection<Object>? found;
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

  /// Adds every one of [introspections] (see [register]).
  void registerAll(Iterable<BeanIntrospection<Object>> introspections) =>
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
  BeanIntrospection<Object>? forType(Type type) =>
      _byType[type] ?? parent?.forType(type);

  /// The introspection of [T] (also when [T] is a nullable `Book?`), here
  /// or in the [parent]; `null` when there is none.
  BeanIntrospection<Object>? forTypeArgument<T>() {
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

  /// The introspection for [bean]: its exact runtime type (here or in a
  /// parent), else the most specific registered supertype (here, then in
  /// the parent).
  BeanIntrospection<Object>? findIntrospection(Object bean) =>
      _exact(bean.runtimeType) ?? _mostSpecific(bean);

  BeanIntrospection<Object>? _exact(Type type) =>
      _byType[type] ?? parent?._exact(type);

  // A linear scan with `is` checks, so subclasses of introspected classes
  // are handled too: the most specific match wins (a `Manager extends
  // Employee extends Person` instance uses Employee's metadata, not
  // Person's).
  BeanIntrospection<Object>? _mostSpecific(Object bean) {
    BeanIntrospection<Object>? best;
    for (final introspection in _byType.values) {
      if (introspection.isInstance(bean) &&
          (best == null || introspection.isSubtypeOf(best))) {
        best = introspection;
      }
    }
    return best ?? parent?._mostSpecific(bean);
  }

  /// Like [findIntrospection], but throws `ArgumentError` when [bean]'s
  /// class is not introspected (or its module is not registered).
  BeanIntrospection<Object> getIntrospection(Object bean) =>
      findIntrospection(bean) ??
      (throw ArgumentError.value(
        bean,
        'bean',
        '${bean.runtimeType} is not @Introspected (or its module is not '
            'registered)',
      ));
}
