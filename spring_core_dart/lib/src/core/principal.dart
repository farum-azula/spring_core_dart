/// Who acts: a user, a client, a service, like Java's
/// `java.security.Principal`. The web layer hands it to controllers and
/// WebSocket endpoints, Spring Security's `Authentication` is one; both use
/// this type without depending on each other.
abstract interface class Principal {
  /// The name of the user (or client).
  String get name;
}
