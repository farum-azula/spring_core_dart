// Any object may be thrown in Dart; the tests throw plain objects on purpose.
// ignore_for_file: only_throw_errors
// An application whose services use repositories under @Transactional: the
// generator writes the proxies and the repositories
// (integration_app.spring.dart, from `dart run build_runner build`), the
// tests start it with the starters' auto-configurations on the real
// in-memory store.
import 'dart:async';

import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import 'integration_app.spring.dart';

// --- Aggregates ------------------------------------------------------------

/// A versioned row: two writers that read it both cannot both save.
@Table('items')
class Item {
  Item({required this.name, this.count = 0, this.id, this.version});

  @Id()
  int? id;

  String name;
  int count;

  @Version()
  int? version;

  @override
  String toString() => 'Item($id, $name, $count, v$version)';
}

/// What is on the shelf; sold under a pessimistic lock.
@Table('stock')
class Stock {
  Stock({required this.sku, required this.quantity, this.id});

  @Id()
  int? id;

  String sku;
  int quantity;
}

/// A unit of work of a queue.
@Table('jobs')
class Job {
  Job({required this.name, this.done = false, this.id});

  @Id()
  int? id;

  String name;
  bool done;
}

/// An audit line.
@Table('audit_lines')
class AuditLine {
  AuditLine({required this.text, this.id});

  @Id()
  int? id;

  String text;
}

/// A label with the id the application gives it: saving the same name twice
/// is a duplicate key.
@Table('labels')
class Label {
  const Label(this.name, {this.version = 0});

  @Id()
  final String name;

  @Version()
  final int version;
}

/// An aggregate with children.
@Table('shipments')
class Shipment {
  Shipment({required this.destination, this.parcels = const [], this.id});

  @Id()
  int? id;

  String destination;

  @MappedCollection()
  List<Parcel> parcels;
}

/// A child of [Shipment].
@Table('parcels')
class Parcel {
  Parcel({required this.label});

  String label;
}

/// A row of the `archive` data source: a store of its own.
@Table('archived')
class Archived {
  Archived({required this.title, this.id});

  @Id()
  int? id;

  String title;
}

// --- Repositories ----------------------------------------------------------

abstract interface class ItemRepository
    implements ListCrudRepository<Item, int> {
  Future<Page<Item>> findByCountGreaterThan(int count, Pageable pageable);
}

abstract interface class StockRepository
    implements ListCrudRepository<Stock, int> {
  /// The row is locked until the transaction ends.
  @Lock(LockMode.pessimisticWrite)
  Future<Stock?> findBySku(String sku);

  /// With a lock that waits at most 50 ms.
  @Lock(LockMode.pessimisticWrite, timeout: Duration(milliseconds: 50))
  Future<Stock?> findOneBySku(String sku);
}

abstract interface class JobRepository implements ListCrudRepository<Job, int> {
  /// The first job nobody holds: locked rows are left out.
  @Lock(LockMode.pessimisticWrite, skipLocked: true)
  Future<Job?> findFirstByDoneFalseOrderById();
}

abstract interface class AuditRepository
    implements ListCrudRepository<AuditLine, int> {}

abstract interface class LabelRepository
    implements CrudRepository<Label, String> {}

abstract interface class ShipmentRepository
    implements ListCrudRepository<Shipment, int> {}

/// On the in-memory store of the data source `archive`.
@UseStore('memory')
@UseDataSource('archive')
abstract interface class ArchiveRepository
    implements ListCrudRepository<Archived, int> {}

// --- Errors ----------------------------------------------------------------

/// A failure that rolls back (any error does, by default).
class Oops implements Exception {}

/// A failure the transaction survives: `noRollbackFor`.
class Soft implements Exception {}

/// There is not enough on the shelf.
class OutOfStock implements Exception {}

// --- Hooks of the tests ----------------------------------------------------

/// Lets a test stop a transaction at a chosen point, to order races:
/// [once] sets what the next call of [pause] does.
@Component()
class Gate {
  Future<void> Function()? _next;

  /// What the next [pause] does, if anything; set it to make it stop.
  Future<void> Function()? get once => _next;

  /// The next [pause] calls [action] (once) and waits for its result.
  set once(Future<void> Function() action) => _next = action;

  /// Stops here when a test asked for it.
  Future<void> pause() async {
    final action = _next;
    _next = null;
    await action?.call();
  }
}

// --- Services --------------------------------------------------------------

/// Writes lines of the audit; its own transaction.
@Service()
class Auditor {
  Auditor(this.lines);

  final AuditRepository lines;

  /// Committed whatever happens to the caller's transaction.
  @Transactional(propagation: Propagation.requiresNew)
  Future<void> record(String text) async {
    await lines.save(AuditLine(text: text));
  }

  /// Runs in a savepoint of the caller's transaction.
  @Transactional(propagation: Propagation.nested)
  Future<void> nested(String text, bool fail) async {
    await lines.save(AuditLine(text: text));
    if (fail) {
      throw Oops();
    }
  }

  @Transactional(propagation: Propagation.mandatory)
  Future<void> mandatory(String text) async {
    await lines.save(AuditLine(text: text));
  }

  @Transactional(propagation: Propagation.never)
  Future<int> never() => lines.count();
}

/// The services of the tests.
@Service()
class Warehouse {
  Warehouse(
    this.items,
    this.stock,
    this.jobs,
    this.labels,
    this.shipments,
    this.archive,
    this.auditor,
    this.audit,
    this.gate,
  );

  final ItemRepository items;
  final StockRepository stock;
  final JobRepository jobs;
  final LabelRepository labels;
  final ShipmentRepository shipments;
  final ArchiveRepository archive;
  final Auditor auditor;
  final AuditRepository audit;
  final Gate gate;

  /// Saves an item, then fails with [error] when it is given.
  @Transactional()
  Future<void> addItem(String name, [Object? error]) async {
    await items.save(Item(name: name));
    if (error != null) {
      throw error;
    }
  }

  /// [Soft] commits, anything else rolls back.
  @Transactional(noRollbackFor: [Soft])
  Future<void> addItemTolerant(String name, Object error) async {
    await items.save(Item(name: name));
    throw error;
  }

  /// Audits in a transaction of its own between two writes; then fails when
  /// [fail], else returns.
  @Transactional()
  Future<void> addWithAudit(String name, {required bool fail}) async {
    await items.save(Item(name: '$name 1'));
    await auditor.record('added $name 1');
    await items.save(Item(name: '$name 2'));
    if (fail) {
      throw Oops();
    }
  }

  /// A nested part that may fail; the outer catches it and goes on.
  @Transactional()
  Future<void> addWithNested({required bool failNested}) async {
    await items.save(Item(name: 'outer'));
    try {
      await auditor.nested('nested', failNested);
    } on Oops {
      // The savepoint is rolled back; the transaction goes on.
    }
    await items.save(Item(name: 'outer after'));
  }

  /// Joins the transaction of the caller; fails when it has none.
  @Transactional()
  Future<void> callMandatory() => auditor.mandatory('mandatory');

  /// Calls a method that refuses a transaction.
  @Transactional()
  Future<int> callNever() => auditor.never();

  @Transactional(readOnly: true)
  Future<void> writeReadOnly() async {
    await items.save(Item(name: 'read only'));
  }

  @Transactional(readOnly: true)
  Future<int> countReadOnly() => items.count();

  /// Saves a shipment with its parcels, then fails when [fail].
  @Transactional()
  Future<void> ship({required bool fail}) async {
    await shipments.save(
      Shipment(
        destination: 'Oslo',
        parcels: [
          Parcel(label: 'a'),
          Parcel(label: 'b'),
        ],
      ),
    );
    if (fail) {
      throw Oops();
    }
  }

  /// Sells one [amount] of [sku] under a lock; returns the quantity seen
  /// after the lock was had. [Gate.pause] stops it holding the lock.
  @Transactional()
  Future<int> sell(String sku, int amount) async {
    final row = (await stock.findBySku(sku))!;
    final seen = row.quantity;
    await gate.pause();
    if (seen < amount) {
      throw OutOfStock();
    }
    row.quantity = seen - amount;
    await stock.save(row);
    return seen;
  }

  /// Reads the row with a lock that waits 50 ms only.
  @Transactional()
  Future<int?> peekWithTimeout(String sku) async =>
      (await stock.findOneBySku(sku))?.quantity;

  /// Takes the next job nobody holds and marks it done.
  @Transactional()
  Future<String?> takeJob() async {
    final job = await jobs.findFirstByDoneFalseOrderById();
    if (job == null) {
      return null;
    }
    await gate.pause();
    job.done = true;
    await jobs.save(job);
    return job.name;
  }

  /// Reads the item, stops, then saves a new name: a lost update when
  /// another transaction saved it meanwhile.
  @Transactional()
  Future<void> rename(int id, String name) async {
    final item = (await items.findById(id))!;
    await gate.pause();
    item.name = name;
    await items.save(item);
  }

  /// A locking read in a transaction of another store.
  @Transactional(transactionManager: 'archive')
  Future<Stock?> lockFromOtherStore(String sku) => stock.findBySku(sku);

  /// Starts a repository call that waits for [release] and runs after the
  /// transaction ended, without awaiting it; what it ends with (the saved
  /// item or the error) goes to the returned completer.
  @Transactional()
  Future<Completer<Object?>> forgetsASave(Future<void> release) async {
    final result = Completer<Object?>();
    unawaited(
      Future<void>(() async {
        await release;
        try {
          result.complete(await items.save(Item(name: 'too late')));
        } on Object catch (error) {
          result.complete(error);
        }
      }),
    );
    return result;
  }

  /// Archives in the transaction of the `archive` data source.
  @Transactional(transactionManager: 'archive')
  Future<void> archiveTitles(List<String> titles, {required bool fail}) async {
    for (final title in titles) {
      await archive.save(Archived(title: title));
    }
    if (fail) {
      throw Oops();
    }
  }

  /// Writes to the archive store from the default store's transaction: the
  /// two stores' transactions are independent.
  @Transactional()
  Future<void> addItemAndArchive(String name, {required bool fail}) async {
    await items.save(Item(name: name));
    await archive.save(Archived(title: name));
    if (fail) {
      throw Oops();
    }
  }
}

/// A cache over a repository-backed page.
@Service()
class Catalog {
  Catalog(this.items);

  final ItemRepository items;

  /// How many times the body ran: the misses.
  int calls = 0;

  @Cacheable('items')
  Future<Page<Item>> page(int count, Pageable pageable) {
    calls++;
    return items.findByCountGreaterThan(count, pageable);
  }
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
