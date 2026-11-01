/// How a transactional method relates to a transaction already running
/// when it is called.
///
/// Spring (Java): `org.springframework.transaction.annotation.Propagation`.
enum Propagation {
  /// Joins the running transaction, or starts one when there is none. The
  /// default.
  required,

  /// Joins the running transaction, or runs without one.
  supports,

  /// Joins the running transaction; without one,
  /// `IllegalTransactionStateException`.
  mandatory,

  /// Always starts its own transaction; a running one is set aside (its
  /// work is neither seen nor committed by this one) until this one ends.
  requiresNew,

  /// Runs without a transaction; a running one is set aside until the
  /// method ends.
  notSupported,

  /// Runs without a transaction; with one running,
  /// `IllegalTransactionStateException`.
  never,

  /// Within a running transaction, runs in a savepoint: an exception rolls
  /// back to the savepoint only, the outer transaction goes on. Without
  /// one, as [required].
  nested,
}

/// How much one transaction sees of others running at the same time.
///
/// A store offers some of these levels; asking for one it does not offer
/// fails when the transaction starts (`InvalidIsolationLevelException`),
/// never silently a weaker one.
///
/// Spring (Java): `org.springframework.transaction.annotation.Isolation`.
enum Isolation {
  /// The store's default level (PostgreSQL: read committed; SQLite:
  /// serializable; in memory: read committed).
  defaultLevel,

  /// May see changes others have not committed (dirty reads).
  readUncommitted,

  /// Sees only committed changes; a row read twice may differ.
  readCommitted,

  /// A row read twice is the same; new rows may appear (phantoms), except
  /// in PostgreSQL.
  repeatableRead,

  /// As if the transactions ran one after the other; a conflict fails one
  /// of them (`CannotSerializeTransactionException`).
  serializable,
}

/// The settings of a transaction: [propagation], [isolation], [timeout],
/// [readOnly], and a [name] for logs.
///
/// Spring (Java): `org.springframework.transaction.TransactionDefinition`
/// with `DefaultTransactionDefinition`.
class TransactionDefinition {
  /// A definition; every setting has Spring's default.
  const TransactionDefinition({
    this.propagation = Propagation.required,
    this.isolation = Isolation.defaultLevel,
    this.timeout,
    this.readOnly = false,
    this.name,
  });

  /// The defaults: [Propagation.required], the store's isolation, no
  /// timeout, read-write.
  static const TransactionDefinition defaults = TransactionDefinition();

  /// How it relates to a running transaction.
  final Propagation propagation;

  /// The isolation level; applies only to a transaction that starts here.
  final Isolation isolation;

  /// The longest the transaction may run, from its start; null for none.
  /// Applies only to a transaction that starts here.
  final Duration? timeout;

  /// Whether the transaction only reads: a store that can (PostgreSQL,
  /// the in-memory store) refuses writes in it. Applies only to a
  /// transaction that starts here.
  final bool readOnly;

  /// The name in logs (by default the class and method:
  /// `Checkout.place`).
  final String? name;

  /// A copy with the given settings changed.
  TransactionDefinition copyWith({
    Propagation? propagation,
    Isolation? isolation,
    Duration? timeout,
    bool? readOnly,
    String? name,
  }) => TransactionDefinition(
    propagation: propagation ?? this.propagation,
    isolation: isolation ?? this.isolation,
    timeout: timeout ?? this.timeout,
    readOnly: readOnly ?? this.readOnly,
    name: name ?? this.name,
  );

  @override
  String toString() {
    final out = StringBuffer('PROPAGATION_${propagation.name}');
    if (isolation != Isolation.defaultLevel) {
      out.write(', ISOLATION_${isolation.name}');
    }
    if (timeout case final timeout?) {
      out.write(', timeout ${timeout.inMilliseconds} ms');
    }
    if (readOnly) {
      out.write(', readOnly');
    }
    return out.toString();
  }
}

/// Runs a bean method in a transaction: it commits when the method's
/// `Future` completes, and rolls back when it fails.
///
/// Every exception and error rolls back (Dart has no checked exceptions),
/// unless its type, or a supertype, is in [noRollbackFor] and not in
/// [rollbackFor]. The types are matched with subtypes: the generator
/// writes a test for each type written in an annotation.
///
/// On a class, it applies to each public method without its own
/// `@Transactional`. It works through the bean's generated proxy: a call
/// from another bean runs in the transaction, a call through `this` inside
/// the class does not (Spring's proxy rule). The method must return a
/// `Future` (the transaction covers it until it completes); a synchronous
/// method, or one returning a `Stream`, stops the start.
///
/// The transaction follows the method's `await`s (it lives in a `Zone`).
/// Work the method starts without awaiting it, still running after the
/// transaction ended, fails when it uses the database
/// (`IllegalTransactionStateException`) instead of running outside it.
///
/// [transactionManager] names the transaction manager bean (by name or
/// qualifier) when there are several: the one of a second data source is
/// qualified with the data source's name.
///
/// ```dart
/// @Service()
/// class Checkout {
///   Checkout(this.stock, this.orders);
///   final StockRepository stock;
///   final OrderRepository orders;
///
///   @Transactional()
///   Future<Order> place(String customer, int bookId) async {
///     final row = (await stock.findByBookId(bookId))!; // for update
///     row.available--;
///     await stock.save(row);
///     return orders.save(Order(customer: customer));
///   }
/// }
/// ```
///
/// Spring (Java):
/// `org.springframework.transaction.annotation.Transactional`. Spring's
/// positional `value` (the manager) is [transactionManager] here: Dart
/// cannot mix an optional positional parameter with named ones. Spring
/// rolls back only unchecked exceptions by default.
class Transactional {
  /// Runs the method in a transaction with these settings.
  const Transactional({
    this.transactionManager = '',
    this.propagation = Propagation.required,
    this.isolation = Isolation.defaultLevel,
    this.timeout,
    this.readOnly = false,
    this.rollbackFor = const [],
    this.noRollbackFor = const [],
    this.label = const [],
  });

  /// The transaction manager bean's name or qualifier; empty for the
  /// primary one.
  final String transactionManager;

  /// How it relates to a running transaction.
  final Propagation propagation;

  /// The isolation level of a transaction started here.
  final Isolation isolation;

  /// The timeout of a transaction started here; null for none.
  final Duration? timeout;

  /// Whether a transaction started here only reads.
  final bool readOnly;

  /// Exception types (and their subtypes) that roll back even when listed
  /// in [noRollbackFor].
  final List<Type> rollbackFor;

  /// Exception types (and their subtypes) after which the transaction
  /// commits.
  final List<Type> noRollbackFor;

  /// Labels for logs and tools; not interpreted.
  final List<String> label;

  /// The definition of a transaction started for a method named [name].
  TransactionDefinition definition(String name) => TransactionDefinition(
    propagation: propagation,
    isolation: isolation,
    timeout: timeout,
    readOnly: readOnly,
    name: name,
  );
}
