import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';

/// Marks an annotation class: an abstract class (an interface) carrying
/// such an annotation becomes a bean whose implementation the generator
/// writes. Every method of the implementation hands the call to an
/// [InvocationHandler], with the method's metadata ([ProxyMethod]).
///
/// The handler comes from an [InvocationHandlerFactory] bean that supports
/// the interface — a starter provides it. This is how Feign clients
/// (`@FeignClient`) get their implementation, without reflection.
///
/// ```dart
/// @InterfaceProxy(primary: true)
/// class FeignClient {
///   const FeignClient(this.name, {this.url});
///   final String name;
///   final String? url;
/// }
///
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
/// }
/// // The generator writes `class _$CatalogClientImpl implements
/// // CatalogClient` and registers it as the bean `catalogClient`.
/// ```
///
/// Spring (Java): JDK dynamic proxies (`java.lang.reflect.Proxy`) created
/// at runtime, e.g. by Spring Cloud OpenFeign's `FeignClientFactoryBean`.
class InterfaceProxy {
  /// Marks an annotation; with [primary] the generated beans are
  /// `@Primary` (so a fallback implementing the same interface does not
  /// make injection ambiguous).
  const InterfaceProxy({this.primary = false});

  /// Whether the generated beans are primary.
  final bool primary;
}

/// One method of an interface proxy: its name, parameters, return type and
/// annotations, written by the generator.
///
/// ```dart
/// // Future<Book> find(@PathVariable() String isbn)
/// ProxyMethod(
///   'find',
///   parameters: const [
///     BeanParameter('isbn', type: ClassType<String>(), isRequired: true,
///         annotations: [PathVariable()]),
///   ],
///   returnType: const ClassType<Book>(),
///   isFuture: true,
///   annotations: const [GetMapping('/books/{isbn}')],
///   call: (target, arguments) =>
///       (target as CatalogClient).find(arguments[0] as String),
/// );
/// ```
///
/// Spring (Java): the `java.lang.reflect.Method` passed to
/// `InvocationHandler.invoke`.
final class ProxyMethod {
  /// Describes method [name]; [call] invokes it on any implementation of
  /// the interface (e.g. a fallback bean).
  ProxyMethod(
    this.name, {
    required this.returnType,
    required this._call,
    List<BeanParameter> parameters = const [],
    this.isFuture = false,
    this.isVoid = false,
    List<Object> annotations = const [],
  }) : parameters = List.unmodifiable(parameters),
       annotations = List.unmodifiable(annotations);

  /// The method name.
  final String name;

  /// Its parameters (positional first, then named), in the order of the
  /// `arguments` passed to [InvocationHandler.invoke].
  final List<BeanParameter> parameters;

  /// The result type; for `Future<T>` the type of `T`.
  final TypeInfo<Object?> returnType;

  /// Whether the method returns a `Future` (whose value is [returnType]).
  final bool isFuture;

  /// Whether the result is `void` (or `Future<void>`).
  final bool isVoid;

  /// Const annotations on the method.
  final List<Object> annotations;

  final Object? Function(Object target, List<Object?> arguments) _call;

  /// Calls this method on [target], an implementation of the interface,
  /// with [arguments] in the order of [parameters].
  Object? callOn(Object target, List<Object?> arguments) =>
      _call(target, arguments);

  /// The first annotation of type [A], or `null`.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  @override
  String toString() => 'ProxyMethod($name)';
}

/// Everything known about an interface proxy: the interface, its
/// annotations and methods. Given to [InvocationHandlerFactory.create].
///
/// ```dart
/// final client = metadata.annotation<FeignClient>()!;
/// for (final method in metadata.methods) {
///   print('${metadata.typeName}.${method.name}');
/// }
/// ```
///
/// Spring (Java): the interface `Class` and its reflected methods.
final class InterfaceMetadata<T extends Object> {
  /// Metadata of interface [T], named [typeName] (kept as a string so it
  /// survives minification).
  InterfaceMetadata({
    required this.typeName,
    required List<ProxyMethod> methods,
    List<Object> annotations = const [],
  }) : methods = List.unmodifiable(methods),
       annotations = List.unmodifiable(annotations);

  /// The interface name, e.g. `CatalogClient`.
  final String typeName;

  /// Its methods.
  final List<ProxyMethod> methods;

  /// Const annotations on the interface.
  final List<Object> annotations;

  /// The interface type.
  Type get type => T;

  /// Whether [value] implements the interface.
  bool isImplementedBy(Object? value) => value is T;

  /// The first annotation of type [A], or `null`.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  @override
  String toString() => 'InterfaceMetadata($typeName)';
}

/// Handles the calls of an interface proxy, like Java's
/// `InvocationHandler`.
///
/// ```dart
/// final class LoggingHandler implements InvocationHandler {
///   @override
///   Object? invoke(ProxyMethod method, List<Object?> arguments) {
///     print('${method.name}($arguments)');
///     return null;
///   }
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// InvocationHandler handler = (proxy, method, args) -> { ... };
/// ```
abstract interface class InvocationHandler {
  /// The result of calling [method] with [arguments]: a `Future` of the
  /// value for methods that return one ([ProxyMethod.isFuture]).
  Object? invoke(ProxyMethod method, List<Object?> arguments);
}

/// Creates the [InvocationHandler] of interface proxies it supports (e.g.
/// those annotated `@FeignClient`). Declared as a bean by a starter; the
/// generated proxies look up the first factory that supports them.
///
/// ```dart
/// final class FeignHandlers implements InvocationHandlerFactory {
///   @override
///   bool supports(InterfaceMetadata<Object> metadata) =>
///       metadata.annotation<FeignClient>() != null;
///
///   @override
///   InvocationHandler create(InterfaceMetadata<Object> metadata) =>
///       FeignHandler(metadata, ...);
/// }
/// ```
///
/// Spring (Java): a `FactoryBean` creating the proxy, e.g. Spring Cloud
/// OpenFeign's `FeignClientFactoryBean`.
abstract interface class InvocationHandlerFactory {
  /// Whether this factory handles the interface of [metadata].
  bool supports(InterfaceMetadata<Object> metadata);

  /// The handler for the interface of [metadata] (called once, when the
  /// bean is created).
  InvocationHandler create(InterfaceMetadata<Object> metadata);
}

/// Used by generated code to find the handler of an interface proxy.
abstract final class InterfaceProxies {
  /// The handler for [metadata] from the first [InvocationHandlerFactory]
  /// bean that supports it.
  ///
  /// Throws a `StateError` naming the interface when no factory does
  /// (usually: the starter providing it is missing).
  static InvocationHandler handlerFor(
    DependencyResolver resolver,
    InterfaceMetadata<Object> metadata,
  ) {
    final factories =
        resolver.optionalDependencyList<InvocationHandlerFactory>() ??
        const <InvocationHandlerFactory>[];
    for (final factory in factories) {
      if (factory.supports(metadata)) {
        return factory.create(metadata);
      }
    }
    final annotations = [
      for (final annotation in metadata.annotations)
        '@${annotation.runtimeType}',
    ].join(', ');
    throw StateError(
      'No InvocationHandlerFactory bean supports ${metadata.typeName}'
      '${annotations.isEmpty ? '' : ' ($annotations)'}: add the starter '
      'that implements it (e.g. spring_boot_starter_feign for @FeignClient).',
    );
  }
}
