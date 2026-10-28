/// An object that says where it goes when several objects of its kind
/// are run or listed in turn; lower numbers come first.
///
/// When the framework holds many beans of one type, the order can matter:
/// which listener sees an event first, which runner starts first, the
/// order of an injected `List<Handler>`. Post-processors, event listeners,
/// runners, lifecycle beans and injected lists (not sets or maps) are
/// sorted this way.
/// Usually the `@Order(n)` annotation says it; implement this interface
/// instead when the order is computed at run time or the object is not a
/// bean declared with annotations. An object with no order goes last
/// ([lowestPrecedence]).
///
/// ```dart
/// // Audits before the other listeners, but leaves room for ones that
/// // must be even earlier.
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
  /// The smallest order value, for objects that must come first.
  ///
  /// Same value as Spring's `Ordered.HIGHEST_PRECEDENCE`
  /// (`Integer.MIN_VALUE`); 32-bit so it also compiles to JavaScript.
  static const int highestPrecedence = -0x80000000;

  /// The largest order value, for objects that must come last; also the
  /// order of objects that declare none.
  ///
  /// Same value as Spring's `Ordered.LOWEST_PRECEDENCE`
  /// (`Integer.MAX_VALUE`); 32-bit so it also compiles to JavaScript.
  static const int lowestPrecedence = 0x7FFFFFFF;

  /// Where this object goes: lower values come first. Values are usually
  /// small numbers, or offsets from [highestPrecedence] and
  /// [lowestPrecedence].
  int get order;
}

/// An [Ordered] object that goes before every plain [Ordered] one,
/// whatever the numbers.
///
/// Infrastructure that other processors depend on uses it, for example a
/// post-processor that must have run before the application's own
/// post-processors are even created. Among themselves, priority-ordered
/// objects are sorted by [order]. Applications almost never need it;
/// [Ordered] or `@Order` is enough.
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

/// An annotation that gives a bean (or a `@Bean` method, an event listener
/// method) its place when several are run or injected in turn; lower
/// values come first.
///
/// It is the usual way to order: listeners, runners and the elements of
/// an injected `List<T>` follow it, and beans without any order (no
/// `@Order`, [Ordered] or jakarta `@Priority`) go last. When
/// the bean's class also implements [Ordered], the interface value wins
/// over an `@Order` on the class; an `@Order` on a `@Bean` method wins
/// over both.
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
  /// Gives the order [value]; [Ordered.lowestPrecedence] when left out,
  /// like Spring's `@Order`.
  const Order([this.value = Ordered.lowestPrecedence]);

  /// The order value; lower values come first.
  final int value;
}

/// Sorts objects the way the framework does: [PriorityOrdered] first,
/// then by order value, objects with equal values keeping their original
/// order.
///
/// Use it when your own code holds a list of objects that should run in
/// the same order the framework would use, such as plug-ins collected
/// from beans. Dart reads no annotations at run time, so `@Order` values
/// must be passed through the `fallback` callback (the container keeps
/// them in the bean definitions).
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
/// Unlike Spring's `OrderComparator`, annotations are not read at run time
/// (there is no reflection); pass their values through `fallback`.
abstract final class OrderComparator {
  /// The order of [object]: its [Ordered.order] when it implements
  /// [Ordered], otherwise [fallback], otherwise
  /// [Ordered.lowestPrecedence].
  ///
  /// ```dart
  /// OrderComparator.orderOf(plainObject, 5); // 5
  /// ```
  static int orderOf(Object object, [int? fallback]) => switch (object) {
    Ordered(:final order) => order,
    _ => fallback ?? Ordered.lowestPrecedence,
  };

  /// Returns [items] as a new sorted list; [items] itself is not changed.
  /// Items with equal orders keep their original order.
  ///
  /// [fallback] gives the order of an item that does not implement
  /// [Ordered], or `null` for [Ordered.lowestPrecedence].
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
