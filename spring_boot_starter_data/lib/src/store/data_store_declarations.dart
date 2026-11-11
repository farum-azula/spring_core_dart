import 'package:spring_boot_starter_data/src/store/data_store_capabilities.dart';
import 'package:spring_boot_starter_data/src/store/data_store_descriptor.dart';

// The stores of the Data starter as the build knows them: found by the
// generator through `lib/spring_auto_configuration.dart`, which exports
// this library, the way the store of any other package is.

/// The in-memory store, as the build knows it: transactions, locks and
/// the changes of its rows. The build cannot tell when it is the default
/// (a `DataSource` bean declared in code makes the SQL store the default),
/// so a repository without `@UseStore` is checked against it only with
/// `spring.data.store=memory`.
@DataStoreDeclaration()
const memoryStore = DataStoreDescriptor(
  'memory',
  capabilities: DataStoreCapabilities(
    transactions: true,
    locks: true,
    changes: true,
  ),
);

/// The SQL store, as the build knows it: transactions, locks, the SQL of
/// `@Query`, and functions (PostgreSQL has them; the store says at startup
/// whether its database does). The default with `spring.datasource.url`,
/// unless `spring.data.store` names another. A `Map`, `Set` or `List`
/// property needs `@Json` (or `@MappedCollection`) there: a column holds
/// no collection, but an array of simple values in PostgreSQL.
@DataStoreDeclaration()
const jdbcStore = DataStoreDescriptor(
  'jdbc',
  capabilities: DataStoreCapabilities(
    transactions: true,
    locks: true,
    queries: true,
    functions: true,
  ),
  defaultWhen: DataStoreDefault(
    whenProperty: ['spring.datasource.url'],
    unlessProperty: ['spring.data.store'],
  ),
  collectionsNeedJson: true,
);
