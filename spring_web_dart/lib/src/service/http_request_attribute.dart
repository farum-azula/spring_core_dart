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
