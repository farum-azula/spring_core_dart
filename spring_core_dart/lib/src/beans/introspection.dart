/// Marks a class for compile-time introspection: the generator emits its
/// properties, methods and annotations, so data binding, validation and
/// SpEL can use it without reflection (like Micronaut's `@Introspected`).
///
/// ```dart
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
class Introspected {
  /// Marks the annotated class.
  const Introspected();
}

/// A property of an introspected class.
///
/// Normally generated for `@Introspected` classes; `get` and `set` are
/// closures over the field, so no reflection is needed.
///
/// ```dart
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
  /// Describes property [name] of [T] with declared [type]; omit `set`
  /// for a read-only property.
  BeanProperty(
    this.name, {
    required this.type,
    required this._get,
    this._set,
    this.nullable = false,
    List<Object> annotations = const [],
  }) : annotations = List.unmodifiable(annotations);

  /// The property (field or getter) name.
  final String name;

  /// Declared type without nullability.
  final Type type;

  /// Whether the declared type is nullable.
  final bool nullable;

  /// Const annotations on the field or getter (e.g. constraints).
  final List<Object> annotations;

  final Object? Function(T bean) _get;
  final void Function(T bean, Object? value)? _set;

  /// Whether the property has a setter.
  bool get isWritable => _set != null;

  /// Reads the property of [bean] (which must be a [T]).
  Object? getValue(Object bean) => _get(bean as T);

  /// Sets [value]; it must already have the property's type (use
  /// `BeanWrapper` for conversion). Throws `StateError` if read-only.
  void setValue(Object bean, Object? value) {
    final setter = _set;
    if (setter == null) {
      throw StateError("Property '$name' of $T is read-only");
    }
    setter(bean as T, value);
  }

  /// The annotations of type [A].
  Iterable<A> annotationsOf<A>() => annotations.whereType<A>();

  @override
  String toString() => 'BeanProperty<$T>($name: $type${nullable ? '?' : ''})';
}

/// A public instance method of an introspected class (positional
/// parameters only).
///
/// Used e.g. by SpEL method calls on introspected objects.
///
/// ```dart
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
  /// Describes method [name] of [T], called through `invoke`.
  BeanMethod(
    this.name, {
    required this._invoke,
    this.returnType,
    List<Type> parameterTypes = const [],
    List<Object> annotations = const [],
  }) : parameterTypes = List.unmodifiable(parameterTypes),
       annotations = List.unmodifiable(annotations);

  /// The method name.
  final String name;

  /// The declared return type; `null` for `void`.
  final Type? returnType;

  /// Declared types of the positional parameters.
  final List<Type> parameterTypes;

  /// Const annotations on the method.
  final List<Object> annotations;
  final Object? Function(T bean, List<Object?> arguments) _invoke;

  /// Calls the method on [bean] with positional [arguments] (already of
  /// the parameter types); returns its result (`null` for `void`).
  Object? invoke(Object bean, List<Object?> arguments) =>
      _invoke(bean as T, arguments);

  @override
  String toString() => 'BeanMethod<$T>($name)';
}

/// Compile-time metadata of a class, like Micronaut's `BeanIntrospection`.
///
/// Generated for `@Introspected` classes and registered in a
/// [BeanIntrospector]; `BeanWrapper`, data binding, validation and SpEL
/// read properties through it.
///
/// ```dart
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
  /// Metadata of [T]; `instantiate` is the no-argument constructor, if
  /// any.
  BeanIntrospection({
    List<BeanProperty<T>> properties = const [],
    List<BeanMethod<T>> methods = const [],
    List<Object> annotations = const [],
    this._instantiate,
  }) : _properties = {for (final p in properties) p.name: p},
       _methods = {for (final m in methods) m.name: m},
       annotations = List.unmodifiable(annotations);

  final Map<String, BeanProperty<T>> _properties;
  final Map<String, BeanMethod<T>> _methods;
  final T Function()? _instantiate;

  /// Const annotations on the class.
  final List<Object> annotations;

  /// The introspected class.
  Type get beanType => T;

  /// Whether [value] is a [T] (or a subtype).
  bool isInstance(Object? value) => value is T;

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
  /// `StateError` when [isInstantiable] is `false`.
  T instantiate() {
    final factory = _instantiate;
    if (factory == null) {
      throw StateError('$T has no no-argument constructor');
    }
    return factory();
  }

  @override
  String toString() => 'BeanIntrospection<$T>';
}

/// A registry of [BeanIntrospection]s, like Micronaut's
/// `BeanIntrospector`. Lookups fall back to [parent].
///
/// Each application context has its own introspector (bean
/// `beanIntrospector`) filled from its modules, with [shared] as parent.
///
/// ```dart
/// final introspector = BeanIntrospector(
///   introspections: [personIntrospection, addressIntrospection],
/// );
/// final meta = introspector.getIntrospection(person);
/// print(meta.properties.map((p) => p.name));
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

  /// A process-wide registry; contexts use their own child registries.
  static final BeanIntrospector shared = BeanIntrospector();

  /// Registry consulted when this one has no match.
  final BeanIntrospector? parent;
  final _byType = <Type, BeanIntrospection<Object>>{};

  /// Adds [introspection], replacing any for the same type.
  void register(BeanIntrospection<Object> introspection) =>
      _byType[introspection.beanType] = introspection;

  /// Adds every one of [introspections].
  void registerAll(Iterable<BeanIntrospection<Object>> introspections) =>
      introspections.forEach(register);

  /// The introspection registered for exactly [type].
  BeanIntrospection<Object>? forType(Type type) =>
      _byType[type] ?? parent?.forType(type);

  /// The introspection for [bean]: its exact runtime type, else the first
  /// registered supertype.
  BeanIntrospection<Object>? findIntrospection(Object bean) {
    // Exact runtime type first (fast); otherwise a linear scan with `is`
    // checks so subclasses of introspected classes are handled too. Local
    // registrations, including supertypes, win over the parent.
    final exact = _byType[bean.runtimeType];
    if (exact != null) {
      return exact;
    }
    for (final introspection in _byType.values) {
      if (introspection.isInstance(bean)) {
        return introspection;
      }
    }
    return parent?.findIntrospection(bean);
  }

  /// Like [findIntrospection], but throws when [bean] is not introspected.
  BeanIntrospection<Object> getIntrospection(Object bean) =>
      findIntrospection(bean) ??
      (throw ArgumentError.value(
        bean,
        'bean',
        '${bean.runtimeType} is not @Introspected (or its module is not '
            'registered)',
      ));
}
