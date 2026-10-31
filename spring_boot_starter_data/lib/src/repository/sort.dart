/// How a query orders its results: a list of [SortOrder]s, each a property and
/// a direction, applied in turn.
///
/// A `Sort` is given to a repository method that takes one, or built into a
/// `Pageable`. The property names are the entity's Dart property names (the
/// generator maps them to columns); a name no property has is a build error
/// where the method is generated, never a run-time surprise.
///
/// Spring (Java): `org.springframework.data.domain.Sort`.
final class Sort {
  const Sort._(this.orders);

  /// Orders by [orders], in turn.
  factory Sort.byOrders(List<SortOrder> orders) =>
      orders.isEmpty ? unsorted : Sort._(List.unmodifiable(orders));

  /// Orders by each of [properties] ascending.
  factory Sort.by(List<String> properties) => Sort.byOrders([
    for (final property in properties) SortOrder.asc(property),
  ]);

  /// No ordering; the store decides the order (as in Spring: `Sort.unsorted`).
  static const Sort unsorted = Sort._([]);

  /// The orders applied in turn; empty when [isUnsorted].
  final List<SortOrder> orders;

  /// Whether any ordering is asked.
  bool get isSorted => orders.isNotEmpty;

  /// Whether no ordering is asked.
  bool get isUnsorted => orders.isEmpty;

  /// This sort followed by [other]'s orders.
  Sort and(Sort other) => Sort.byOrders([...orders, ...other.orders]);

  /// This sort with every order's direction set to descending.
  Sort descending() =>
      Sort.byOrders([for (final o in orders) o.with_(Direction.desc)]);

  /// This sort with every order's direction set to ascending.
  Sort ascending() =>
      Sort.byOrders([for (final o in orders) o.with_(Direction.asc)]);

  @override
  bool operator ==(Object other) =>
      other is Sort &&
      other.orders.length == orders.length &&
      _listEquals(other.orders, orders);

  @override
  int get hashCode => Object.hashAll(orders);

  @override
  String toString() => isUnsorted ? 'UNSORTED' : orders.join(', ');
}

/// One step of a [Sort]: a [property] ordered in a [direction], with how
/// nulls are placed and whether the comparison ignores case.
///
/// Spring (Java): `org.springframework.data.domain.Sort.Order`; named
/// `SortOrder` here, since `Order` is the ordering annotation of beans.
final class SortOrder {
  /// Orders [property] in [direction], placing nulls as [nullHandling] says
  /// and comparing case-sensitively unless [ignoreCase].
  const SortOrder(
    this.property, {
    this.direction = Direction.asc,
    this.nullHandling = NullHandling.native,
    this.ignoreCase = false,
  });

  /// [property] ascending.
  const SortOrder.asc(this.property)
    : direction = Direction.asc,
      nullHandling = NullHandling.native,
      ignoreCase = false;

  /// [property] descending.
  const SortOrder.desc(this.property)
    : direction = Direction.desc,
      nullHandling = NullHandling.native,
      ignoreCase = false;

  /// The entity property to order by.
  final String property;

  /// Ascending or descending.
  final Direction direction;

  /// Where nulls go.
  final NullHandling nullHandling;

  /// Whether the comparison is case-insensitive (lower-cased on both sides).
  final bool ignoreCase;

  /// Whether this order is ascending.
  bool get isAscending => direction == Direction.asc;

  /// Whether this order is descending.
  bool get isDescending => direction == Direction.desc;

  /// A copy ordered in [direction].
  SortOrder with_(Direction direction) => SortOrder(
    property,
    direction: direction,
    nullHandling: nullHandling,
    ignoreCase: ignoreCase,
  );

  /// A copy whose comparison ignores case.
  SortOrder ignoringCase() => SortOrder(
    property,
    direction: direction,
    nullHandling: nullHandling,
    ignoreCase: true,
  );

  /// A copy placing nulls as [nullHandling] says.
  SortOrder withNullHandling(NullHandling nullHandling) => SortOrder(
    property,
    direction: direction,
    nullHandling: nullHandling,
    ignoreCase: ignoreCase,
  );

  @override
  bool operator ==(Object other) =>
      other is SortOrder &&
      other.property == property &&
      other.direction == direction &&
      other.nullHandling == nullHandling &&
      other.ignoreCase == ignoreCase;

  @override
  int get hashCode =>
      Object.hash(property, direction, nullHandling, ignoreCase);

  @override
  String toString() {
    final out = StringBuffer(property)
      ..write(': ')
      ..write(direction.name);
    if (ignoreCase) {
      out.write(', ignoring case');
    }
    if (nullHandling != NullHandling.native) {
      out
        ..write(', ')
        ..write(nullHandling.name);
    }
    return out.toString();
  }
}

/// The direction of an [SortOrder].
///
/// Spring (Java): `org.springframework.data.domain.Sort.Direction`.
enum Direction {
  /// Smallest first.
  asc,

  /// Largest first.
  desc;

  /// The direction whose name is [value] (`asc`/`desc`, any case); throws
  /// an [ArgumentError] otherwise, as Spring's `Direction.fromString`.
  static Direction fromString(String value) => switch (value.toLowerCase()) {
    'asc' => Direction.asc,
    'desc' => Direction.desc,
    _ => throw ArgumentError.value(
      value,
      'value',
      "Invalid value; must be 'asc' or 'desc'",
    ),
  };
}

/// Where nulls are placed when a property is ordered.
///
/// Spring (Java): `org.springframework.data.domain.Sort.NullHandling`.
enum NullHandling {
  /// The store's own placement (no `NULLS FIRST`/`LAST` added).
  native,

  /// Nulls before non-nulls.
  nullsFirst,

  /// Nulls after non-nulls.
  nullsLast,
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
