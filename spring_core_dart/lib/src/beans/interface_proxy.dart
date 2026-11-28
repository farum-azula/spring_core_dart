import 'package:spring_core_dart/src/beans/bean_factory.dart';
import 'package:spring_core_dart/src/beans/introspection.dart';
import 'package:spring_core_dart/src/beans/type_info.dart';

/// Marks an annotation class whose interfaces become beans implemented by
/// generated code: each call is handed to an [InvocationHandler].
///
/// Some libraries let the user declare only an interface and supply the
/// behaviour themselves, such as a WebSocket client where each method is
/// a stream of messages or a message sent. Java does this with runtime
/// proxies; Dart has none, so the generator writes the class. An abstract
/// class (an interface) carrying an annotation marked `@InterfaceProxy()`
/// becomes a bean whose every method passes the call, with the method's
/// metadata ([ProxyMethod]), to a handler. The handler comes from an
/// [InvocationHandlerFactory] bean that supports the interface, which the
/// library's starter provides.
/// This is how WebSocket clients (`@WebSocketClient`) get their
/// implementation.
/// Only library authors define such annotations; applications just use
/// them.
///
/// ```dart
/// // The WebSocket starter's annotation, and an application's client.
/// @InterfaceProxy(primary: true)
/// class WebSocketClient {
///   const WebSocketClient(this.name, {this.url});
///   final String name;
///   final String? url;
/// }
///
/// @WebSocketClient('chat', url: r'${chat.url}')
/// abstract interface class ChatSocket {
///   @SendMessage()
///   Future<void> send(ChatMessage message);
/// }
/// // The generator writes `class _$ChatSocketImpl implements ChatSocket`
/// // and registers it as the bean `chatSocket`.
/// ```
///
/// Spring (Java): JDK dynamic proxies (`java.lang.reflect.Proxy`) created
/// at runtime, e.g. by `HttpServiceProxyFactory` for HTTP service
/// interfaces.
class InterfaceProxy {
  /// Marks the annotation class; with [primary] the generated beans are
  /// `@Primary`, so a fallback bean implementing the same interface does
  /// not make injection ambiguous.
  const InterfaceProxy({this.primary = false});

  /// Whether the generated beans are primary.
  final bool primary;
}

/// The description of one method of an interface proxy: its name,
/// parameters, return type and annotations, and a way to call it.
///
/// The generator writes one per method; an [InvocationHandler] reads it to
/// know what a call means (for a WebSocket client: whether it sends a
/// message or listens to them), and [callOn] lets it forward the call to
/// a real implementation such as a fallback bean.
///
/// ```dart
/// // Future<void> send(ChatMessage message)
/// ProxyMethod(
///   'send',
///   parameters: const [
///     IntrospectedParameter('message', type: ClassType<ChatMessage>(),
///         isRequired: true),
///   ],
///   returnType: const ClassType<void>(),
///   isFuture: true,
///   isVoid: true,
///   annotations: const [SendMessage()],
///   call: (target, arguments) =>
///       (target as ChatSocket).send(arguments[0] as ChatMessage),
/// );
/// ```
///
/// Spring (Java): the `java.lang.reflect.Method` passed to
/// `InvocationHandler.invoke`.
final class ProxyMethod {
  /// Describes the method [name]; `call` invokes it on any implementation
  /// of the interface (e.g. a fallback bean). The generator leaves `call`
  /// out where there is no other implementation to call.
  ProxyMethod(
    this.name, {
    required this.returnType,
    this._call,
    List<IntrospectedParameter> parameters = const [],
    this.isFuture = false,
    this.isVoid = false,
    List<Object> annotations = const [],
  }) : parameters = List.unmodifiable(parameters),
       annotations = List.unmodifiable(annotations);

  /// The method's name.
  final String name;

  /// Its parameters (positional first, then named), in the order of the
  /// `arguments` passed to [InvocationHandler.invoke].
  final List<IntrospectedParameter> parameters;

  /// The result type; for `Future<T>` the type of `T`.
  final TypeInfo<Object?> returnType;

  /// Whether the method returns a `Future` (whose value is [returnType]).
  final bool isFuture;

  /// Whether the result is `void` (or `Future<void>`).
  final bool isVoid;

  /// The const annotations on the method.
  final List<Object> annotations;

  final Object? Function(Object target, List<Object?> arguments)? _call;

  /// Calls this method on [target], an implementation of the interface,
  /// with [arguments] in the order of [parameters]. Throws a [StateError]
  /// when the method was described without a `call`.
  Object? callOn(Object target, List<Object?> arguments) {
    final call =
        _call ??
        (throw StateError(
          '$name was generated without a call: its interface has no '
          'implementation to call',
        ));
    return call(target, arguments);
  }

  /// The first annotation of type [A], or `null`.
  A? annotation<A>() => annotations.whereType<A>().firstOrNull;

  @override
  String toString() => 'ProxyMethod($name)';
}

/// The description of an interface that is implemented by a proxy: its
/// name, its annotations and its methods.
///
/// The generator writes it; an [InvocationHandlerFactory] receives it to
/// decide whether it handles the interface and to build the handler (read
/// the base URL from the annotation, prepare each method).
///
/// ```dart
/// // In a handler factory: read the client annotation and the methods.
/// final client = metadata.annotation<WebSocketClient>()!;
/// for (final method in metadata.methods) {
///   log.debug('${metadata.typeName}.${method.name}');
/// }
/// ```
///
/// Spring (Java): the interface `Class` and its reflected methods.
final class InterfaceMetadata<T extends Object> {
  /// The description of the interface [T], named [typeName] (kept as a
  /// string so it survives minification).
  InterfaceMetadata({
    required this.typeName,
    required List<ProxyMethod> methods,
    List<Object> annotations = const [],
  }) : methods = List.unmodifiable(methods),
       annotations = List.unmodifiable(annotations);

  /// The interface name, e.g. `CatalogClient`.
  final String typeName;

  /// Its methods, each with its metadata.
  final List<ProxyMethod> methods;

  /// The const annotations on the interface.
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

/// The object that does the work of an interface proxy: every call of the
/// generated implementation ends up in [invoke].
///
/// A library implements it for its kind of interface (for a WebSocket
/// client, turning the call into a message sent or a stream of those
/// received) and creates it in an
/// [InvocationHandlerFactory]. Applications do not implement it.
///
/// ```dart
/// // A handler that only logs the calls.
/// final class LoggingHandler implements InvocationHandler {
///   @override
///   Object? invoke(ProxyMethod method, List<Object?> arguments) {
///     log.info('${method.name}($arguments)');
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
  /// Handles a call of [method] with [arguments] and returns its result:
  /// a `Future` of the value for methods that return one
  /// ([ProxyMethod.isFuture]). What it throws reaches the caller.
  Object? invoke(ProxyMethod method, List<Object?> arguments);
}

/// A bean that provides the [InvocationHandler] for the interface proxies
/// it supports, for example those annotated `@WebSocketClient`.
///
/// A starter declares one; when a generated proxy bean is created, it asks
/// the factory beans in order and takes the handler of the first that
/// supports its interface. Applications do not implement it.
///
/// ```dart
/// // The WebSocket starter's factory.
/// final class WebSocketHandlers implements InvocationHandlerFactory {
///   @override
///   bool supports(InterfaceMetadata<Object> metadata) =>
///       metadata.annotation<WebSocketClient>() != null;
///
///   @override
///   InvocationHandler create(InterfaceMetadata<Object> metadata) =>
///       WebSocketHandler(metadata, ...);
/// }
/// ```
///
/// Spring (Java): a `FactoryBean` creating the proxy, e.g. Spring Data's
/// `RepositoryFactoryBeanSupport`.
abstract interface class InvocationHandlerFactory {
  /// Whether this factory handles the interface of [metadata], typically
  /// judged from its annotation.
  bool supports(InterfaceMetadata<Object> metadata);

  /// The handler for the interface of [metadata] (called once, when the
  /// bean is created).
  InvocationHandler create(InterfaceMetadata<Object> metadata);
}

/// The lookup that generated proxy code uses to get its handler; not
/// meant for other code.
abstract final class InterfaceProxies {
  /// The handler for [metadata] from the first [InvocationHandlerFactory]
  /// bean (in `@Order`) that supports it.
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
      'that implements it (e.g. spring_boot_starter_websocket for '
      '@WebSocketClient).',
    );
  }
}
