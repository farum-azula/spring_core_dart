/// The identity of whoever makes a request: a user, a client application
/// or another service, reduced to a name.
///
/// It exists so the web layer and the security packages can share one
/// type without depending on each other: an authentication filter (the
/// security starter's) stores a principal on the request, and a controller
/// or WebSocket handler parameter of type `Principal` receives it. An
/// application receives it; it rarely implements it (Spring Security's
/// `Authentication` is one).
///
/// ```dart
/// @RestController()
/// class MeController {
///   // Null while nobody is authenticated.
///   @GetMapping('/me')
///   String me(Principal? principal) => principal?.name ?? 'anonymous';
/// }
/// ```
///
/// Spring (Java): `java.security.Principal`.
/// ```java
/// @GetMapping("/me")
/// String me(Principal principal) { return principal.getName(); }
/// ```
abstract interface class Principal {
  /// The name that identifies the user or client, such as a user name or
  /// a client id.
  String get name;
}
