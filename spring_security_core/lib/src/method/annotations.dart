// The documentation has Markdown table rows, which cannot be wrapped.
// ignore_for_file: lines_longer_than_80_chars

import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Checks a SpEL expression before the method runs, like Spring's
/// `@PreAuthorize`; the call fails with `AccessDeniedException` (403 in a
/// web application) unless it is `true`.
///
/// The expression sees the current user and the arguments:
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
/// | `@shop.isOpen()` | a bean |
///
/// ```dart
/// @Service()
/// class OrderService {
///   @PreAuthorize("hasRole('ADMIN') or #order.owner == principal.username")
///   Future<void> cancel(Order order) async { ... }
/// }
/// ```
///
/// On the class, it applies to every method without its own. It works
/// through the bean's proxy: a call from inside the bean (`this.cancel`)
/// is not checked, as in Spring. Classes of the bean's package used by the
/// method (`Order`) are readable in the expression without
/// `@Introspected`.
@BeanMethodAnnotation()
class PreAuthorize {
  /// Allows the call when [value] is `true`.
  const PreAuthorize(this.value);

  /// The SpEL expression.
  final String value;
}

/// Checks a SpEL expression after the method returned, with the result as
/// `returnObject`, like Spring's `@PostAuthorize`: the caller gets
/// `AccessDeniedException` instead of the result unless it is `true` (the
/// method has run: use it for reads).
///
/// ```dart
/// @PostAuthorize('returnObject.owner == principal.username')
/// Future<Order> find(String id) => orders.load(id);
/// ```
@BeanMethodAnnotation()
class PostAuthorize {
  /// Returns the result when [value] is `true`.
  const PostAuthorize(this.value);

  /// The SpEL expression.
  final String value;
}

/// Allows the call when the user has one of these authorities, like
/// Spring's `@Secured` (roles are written with their prefix).
///
/// ```dart
/// @Secured(['ROLE_ADMIN', 'ROLE_SUPPORT'])
/// void refund(String orderId) { ... }
/// ```
@BeanMethodAnnotation()
class Secured {
  /// Allows holders of any of [value].
  const Secured(this.value);

  /// The authorities.
  final List<String> value;
}

/// Removes from a collection argument the elements for which the
/// expression is `false` (`filterObject` is the element), like Spring's
/// `@PreFilter`; [filterTarget] names the argument when there are several.
///
/// ```dart
/// @PreFilter('filterObject.owner == principal.username')
/// Future<void> deleteAll(List<Order> orders) async { ... }
/// ```
@BeanMethodAnnotation()
class PreFilter {
  /// Keeps the elements for which [value] is `true`.
  const PreFilter(this.value, {this.filterTarget = ''});

  /// The SpEL expression.
  final String value;

  /// The name of the collection argument (needed with several).
  final String filterTarget;
}

/// Removes from the returned collection the elements for which the
/// expression is `false`, like Spring's `@PostFilter`.
///
/// ```dart
/// @PostFilter('filterObject.owner == principal.username')
/// Future<List<Order>> findAll() => orders.all();
/// ```
@BeanMethodAnnotation()
class PostFilter {
  /// Keeps the elements for which [value] is `true`.
  const PostFilter(this.value);

  /// The SpEL expression.
  final String value;
}
