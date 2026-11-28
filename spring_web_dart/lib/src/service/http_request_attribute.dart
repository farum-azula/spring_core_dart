/// The base of an annotation that sets a request attribute on the calls
/// of an HTTP service interface: on the interface, every method's call; on
/// a method, that method's. The generated call sets
/// `.attribute(attributeName, attributeValue)` on the `RestClient`
/// request, and the interceptors read it from `HttpRequest.attributes`.
///
/// A library's own annotation extends it with the name it reads: the
/// OAuth2 client's `@ClientRegistrationId('partner')` names the
/// registration whose token its interceptor sends.
///
/// ```dart
/// class Tenant extends HttpRequestAttribute {
///   const Tenant(String tenant) : super('tenant', tenant);
/// }
///
/// @HttpExchange('/orders')
/// @Tenant('neon')
/// abstract interface class OrderService {
///   @GetExchange()
///   Future<List<Order>> all();
/// }
/// ```
///
/// Spring (Java): no common base; an `HttpRequestValues.Processor` (as
/// Spring Security's `ClientRegistrationIdProcessor` for
/// `@ClientRegistrationId`) turns an annotation into an attribute.
abstract class HttpRequestAttribute {
  /// The attribute [attributeName] with [attributeValue].
  const HttpRequestAttribute(this.attributeName, this.attributeValue);

  /// The name of the attribute, the key of `HttpRequest.attributes`.
  final String attributeName;

  /// Its value.
  final Object attributeValue;
}

/// Makes a parameter of an HTTP service method a request attribute of the
/// call: `.attribute(name, value)` on the `RestClient` request, not sent,
/// read by the interceptors from `HttpRequest.attributes`. The value goes
/// as it is (no conversion); a `null` sets nothing. A
/// `Map<String, Object?>` parameter sets one attribute per entry, as in
/// Spring. Without a [name], the parameter's own name is the attribute's.
///
/// ```dart
/// @HttpExchange('/orders')
/// abstract interface class OrderService {
///   @GetExchange()
///   Future<List<Order>> all(@RequestAttribute('trace.tag') String tag);
/// }
/// ```
///
/// A value the same for every call is an annotation extending
/// [HttpRequestAttribute] instead. A server does not read request
/// attributes into handler parameters: the build accepts it only on a
/// method with an exchange annotation.
///
/// Spring (Java): `@RequestAttribute` on a parameter of an HTTP service
/// method (`RequestAttributeArgumentResolver`):
/// ```java
/// @GetExchange
/// List<Order> all(@RequestAttribute("trace.tag") String tag);
/// ```
class RequestAttribute {
  /// The attribute [name]; without one, the attribute named like the
  /// parameter.
  const RequestAttribute([this.name]);

  /// The attribute's name, or `null` to use the parameter's name.
  final String? name;
}
