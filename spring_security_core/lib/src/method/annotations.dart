// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Allows a call of a bean method only when an expression about the
/// current user and the arguments is `true`; otherwise the method does
/// not run.
///
/// Put it on a method of a bean (a `@Service()`, a controller) to protect
/// the method wherever it is called from: a web request, another bean, a
/// scheduled task. The expression is in SpEL, the Spring Expression
/// Language, and is checked before every call:
///
/// - `false`: the call fails with an `AccessDeniedException` (a web
///   request gets 403, or is asked to log in when anonymous);
/// - no authentication in the security context at all: it fails with an
///   `AuthenticationCredentialsNotFoundException` (401) before the
///   expression runs;
/// - an expression that fails or does not give a `bool`: the call fails
///   with an [ArgumentError], and the method does not run.
///
/// A synchronous method throws; an `async` method returns a failed
/// `Future`. Every expression is parsed at startup, so a typo stops the
/// application instead of opening the method. The expression sees:
///
/// | In the expression | Is |
/// |---|---|
/// | `hasRole('ADMIN')`, `hasAnyRole('A', 'B')` | the user has `ROLE_ADMIN` / one of the roles (with the role hierarchy) |
/// | `hasAuthority('SCOPE_read')`, `hasAnyAuthority(...)` | the user has the authority |
/// | `isAuthenticated()`, `isFullyAuthenticated()`, `isAnonymous()` | how the user logged in |
/// | `permitAll`, `denyAll` | always / never |
/// | `principal`, `authentication` | the user (`principal.username`), the `Authentication` (`authentication.name`) |
/// | `#order`, `#p0`, `#a0` | the arguments, by name and by position |
/// | `hasPermission(#order, 'cancel')` | the `PermissionEvaluator` bean (denies without one) |
/// | `returnObject`, `filterObject` | the result (`@PostAuthorize`), the element (`@PreFilter`, `@PostFilter`) |
/// | `@shop.isOpen()` | a bean (its class `@Introspected`) |
///
/// ```dart
/// @Service()
/// class OrderService {
///   // Admins cancel any order, other users only their own.
///   @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
///   Future<void> cancel(Order order) async { ... }
/// }
/// ```
///
/// On the class, it applies to every method that has no security
/// annotation of its own (not to getters and setters). The check runs in
/// the bean's proxy: a call from inside the bean (`this.cancel(...)`) is
/// not checked, as in Spring, and a bean with security annotations that
/// cannot be proxied fails the startup. Classes of the bean's package used
/// by the method (`Order`) are readable in the expression without
/// `@Introspected`. The password of a `User` and the credentials of an
/// `Authentication` are not readable.
///
/// Spring (Java):
/// ```java
/// @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
/// public void cancel(Order order) { ... }
/// ```
///
/// Unlike Spring, nothing has to switch method security on
/// (`@EnableMethodSecurity`): the dependency is enough.
@BeanMethodAnnotation()
class PreAuthorize {
  /// Allows the call when the expression [value] is `true`.
  const PreAuthorize(this.value);

  /// The SpEL expression; it must give a `bool`.
  final String value;
}

/// Hands the result of a bean method to the caller only when an
/// expression about it is `true`; otherwise the caller gets an
/// `AccessDeniedException` instead.
///
/// Use it when whether the caller may see something depends on what was
/// loaded, such as its owner: the result is `returnObject` in the
/// expression, which sees everything `@PreAuthorize` sees. The method has
/// already run when the check fails, so use it for reads, not for changes.
/// For an `async` method the check runs on the value of the `Future`. The
/// failure rules are those of [PreAuthorize].
///
/// ```dart
/// // Users may only open their own orders.
/// @PostAuthorize('returnObject.owner == principal.username')
/// Future<Order> find(String id) => orders.load(id);
/// ```
///
/// Spring (Java):
/// ```java
/// @PostAuthorize("returnObject.owner == principal.username")
/// public Order find(String id) { return orders.load(id); }
/// ```
@BeanMethodAnnotation()
class PostAuthorize {
  /// Returns the result when the expression [value] is `true`.
  const PostAuthorize(this.value);

  /// The SpEL expression; it must give a `bool`.
  final String value;
}

/// Allows a call of a bean method only when the user has one of the
/// listed authorities; the simple form of [PreAuthorize].
///
/// Use it when a list of roles is the whole rule. Write roles with their
/// prefix (`ROLE_ADMIN`, not `ADMIN`). The role hierarchy applies. A
/// denied call fails with an `AccessDeniedException`, and a call with no
/// authentication at all with an
/// `AuthenticationCredentialsNotFoundException`, before the method runs.
///
/// ```dart
/// // Refunds are for admins and support staff.
/// @Secured(['ROLE_ADMIN', 'ROLE_SUPPORT'])
/// void refund(String orderId) { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @Secured({"ROLE_ADMIN", "ROLE_SUPPORT"})
/// public void refund(String orderId) { ... }
/// ```
@BeanMethodAnnotation()
class Secured {
  /// Allows users holding any of the authorities in [value].
  const Secured(this.value);

  /// The full authority names, such as `ROLE_ADMIN`.
  final List<String> value;
}

/// Before a bean method runs, removes from a collection argument the
/// elements the current user may not touch.
///
/// The expression runs once per element, which is `filterObject` in it.
/// Elements for which it is `false` are dropped, and the method gets the
/// rest; the call itself is not denied. A `List` or `Set` argument is
/// replaced by a filtered copy; a `Map` is filtered in place (each entry
/// is a `MapEntry`), and an unmodifiable `Map` fails with an
/// [ArgumentError]. A `null` argument stays `null`.
///
/// When the method has more than one `List`, `Set` or `Map` parameter,
/// [filterTarget] must name the one to filter; a missing or wrong name
/// fails the call with an [ArgumentError].
///
/// ```dart
/// // Deleting a batch silently skips other users' orders.
/// @PreFilter('filterObject.owner == principal.username')
/// Future<void> deleteAll(List<Order> orders) async { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @PreFilter("filterObject.owner == principal.username")
/// public void deleteAll(List<Order> orders) { ... }
/// ```
@BeanMethodAnnotation()
class PreFilter {
  /// Keeps the elements for which the expression [value] is `true`.
  const PreFilter(this.value, {this.filterTarget = ''});

  /// The SpEL expression, run once per element; it must give a `bool`.
  final String value;

  /// The name of the parameter to filter; `''` (the default) picks the
  /// only collection parameter.
  final String filterTarget;
}

/// After a bean method returned a collection, removes the elements the
/// current user may not see.
///
/// The expression runs once per element, which is `filterObject` in it.
/// Elements for which it is `false` are dropped from what the caller gets;
/// the call itself is not denied. A returned `List` or `Set` is replaced by
/// a filtered copy, a `Map` is filtered in place; any other result (such
/// as a `Stream`) fails the call with an [ArgumentError]. For an `async`
/// method the value of the `Future` is filtered. With [PostAuthorize] on
/// the same method, the filtering comes first.
///
/// The method loads everything before the filter runs: for large results,
/// filter in the query instead.
///
/// ```dart
/// // Each user sees only their own orders.
/// @PostFilter('filterObject.owner == principal.username')
/// Future<List<Order>> findAll() => orders.all();
/// ```
///
/// Spring (Java):
/// ```java
/// @PostFilter("filterObject.owner == principal.username")
/// public List<Order> findAll() { return orders.all(); }
/// ```
@BeanMethodAnnotation()
class PostFilter {
  /// Keeps the elements for which the expression [value] is `true`.
  const PostFilter(this.value);

  /// The SpEL expression, run once per element; it must give a `bool`.
  final String value;
}
