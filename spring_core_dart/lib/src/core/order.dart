/// Ordering contract, like Spring's `Ordered`.
///
/// Lower values have higher priority. Used to sort injected collections,
/// post-processors, event listeners and lifecycle beans.
///
/// ```dart
/// class AuditListener implements Ordered {
///   @override
///   int get order => Ordered.highestPrecedence + 10;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class AuditListener implements Ordered {
///   @Override
///   public int getOrder() {
///     return Ordered.HIGHEST_PRECEDENCE + 10;
///   }
/// }
/// ```
abstract interface class Ordered {
  /// Highest precedence (runs first).
  ///
  /// Same value as Spring's `Ordered.HIGHEST_PRECEDENCE`
  /// (`Integer.MIN_VALUE`); 32-bit so it also compiles to JavaScript.
  static const int highestPrecedence = -0x80000000;

  /// Lowest precedence (runs last). The default for unordered objects.
  ///
  /// Same value as Spring's `Ordered.LOWEST_PRECEDENCE`
  /// (`Integer.MAX_VALUE`); 32-bit so it also compiles to JavaScript.
  static const int lowestPrecedence = 0x7FFFFFFF;

  /// The order value of this object; lower values sort first.
  int get order;
}

/// Ordered objects that run before all plain [Ordered] ones, like Spring's
/// `PriorityOrdered`.
///
/// Among themselves, priority-ordered objects are sorted by [order].
///
/// ```dart
/// class EarlyPostProcessor extends BeanPostProcessor
///     implements PriorityOrdered {
///   @override
///   int get order => 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class EarlyPostProcessor implements BeanPostProcessor, PriorityOrdered {
///   @Override
///   public int getOrder() { return 0; }
/// }
/// ```
abstract interface class PriorityOrdered implements Ordered {}

/// Declares the order of a bean, like Spring's `@Order`.
///
/// When the bean also implements [Ordered], the interface value wins.
///
/// ```dart
/// @Component()
/// @Order(1)
/// class FirstHandler implements Handler {}
///
/// // Injected `List<Handler>` has FirstHandler before unordered handlers.
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// @Order(1)
/// class FirstHandler implements Handler {}
/// ```
class Order {
  /// Creates the annotation with the given order [value]; defaults to
  /// [Ordered.lowestPrecedence] like Spring's `@Order`.
  const Order([this.value = Ordered.lowestPrecedence]);

  /// The order value; lower values sort first.
  final int value;
}

/// Sorts objects: [PriorityOrdered] first, then by order value; equal
/// values keep their original order (stable).
///
/// The `fallback` callback supplies the order of objects that do not
/// implement [Ordered] (for example from an `@Order` annotation recorded in
/// a bean definition).
///
/// ```dart
/// final sorted = OrderComparator.sort(
///   handlers,
///   (handler) => handler is FirstHandler ? 1 : null,
/// );
/// final order = OrderComparator.orderOf(handler); // lowest if unordered
/// ```
///
/// Spring (Java):
/// ```java
/// List<Handler> sorted = new ArrayList<>(handlers);
/// AnnotationAwareOrderComparator.sort(sorted);
/// ```
///
/// Unlike Spring's `OrderComparator`, annotations are not read at runtime
/// (no reflection); pass their values through `fallback`.
abstract final class OrderComparator {
  /// Order value of [object]: [Ordered.order] or [fallback] or lowest.
  ///
  /// ```dart
  /// OrderComparator.orderOf(plainObject, 5); // 5
  /// ```
  static int orderOf(Object object, [int? fallback]) => switch (object) {
    Ordered(:final order) => order,
    _ => fallback ?? Ordered.lowestPrecedence,
  };

  /// Returns a new list sorted by order; stable for equal orders.
  ///
  /// [items] is not modified. [fallback] returns the order of an item that
  /// does not implement [Ordered] (or `null` for lowest precedence).
  static List<T> sort<T extends Object>(
    Iterable<T> items, [
    int? Function(T item)? fallback,
  ]) {
    // Dart's List.sort is not guaranteed stable, so the original index is
    // used as the final tie-breaker.
    final indexed = items.indexed.toList();
    int key(T item) => orderOf(item, fallback?.call(item));
    indexed.sort((a, b) {
      final aPriority = a.$2 is PriorityOrdered;
      final bPriority = b.$2 is PriorityOrdered;
      if (aPriority != bPriority) {
        return aPriority ? -1 : 1;
      }
      final byOrder = key(a.$2).compareTo(key(b.$2));
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final (_, item) in indexed) item];
  }
}
