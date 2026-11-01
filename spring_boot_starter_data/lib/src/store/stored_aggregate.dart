/// The row of an aggregate (a root or a child) and the rows of its
/// children, by the name of the mapped property.
///
/// Internal to the in-memory store and its transactions: a row is never
/// changed once it is stored; a write makes a new one.
final class StoredAggregate {
  /// A row with its [values] (by column) and its [children].
  StoredAggregate(this.values, this.children);

  /// The columns of the row.
  final Map<String, Object?> values;

  /// The child rows, by the name of the mapped property.
  final Map<String, List<StoredChild>> children;
}

/// A child row with its position in a list (an int), its key in a map, or
/// null in a set.
final class StoredChild {
  /// A child row [stored] at [key].
  StoredChild(this.key, this.stored);

  /// The position, the key, or null.
  final Object? key;

  /// The row.
  final StoredAggregate stored;
}
