## Unreleased

- Transactions (step 2):
  - `@Transactional` on bean methods (through the generated proxies) with Spring's seven propagations, isolation, timeout, read-only, `rollbackFor` / `noRollbackFor` matching subtypes (every exception rolls back by default: Dart has no checked exceptions); `TransactionTemplate`; `PlatformTransactionManager`, `AbstractPlatformTransactionManager`, `TransactionSynchronization`.
  - The current transaction lives in a `Zone`: it follows `await`, two concurrent requests never share one, `requiresNew` / `notSupported` set aside only their own store's transaction, and work started without `await` that outlives its transaction fails instead of running outside it.
  - The in-memory store has transactions: read committed, row locks with deadlock detection and a lock timeout (`spring.data.memory.lock-timeout`, 10s), savepoints (`nested`), read-only transactions refusing writes; `InMemoryTransactionManager` is the default `transactionManager`, one more per `@UseDataSource` name.
  - `@Lock(LockMode.pessimisticWrite / pessimisticRead, timeout:, skipLocked:)` on derived `find` methods and `findById`, only inside a transaction.
  - Repository writes (`save`, `saveAll`, deletes) run in a transaction: `saveAll` and an aggregate with its children are atomic; inside an outer transaction they join it.
  - A `@Transactional` method must return a `Future`: a synchronous or `Stream` method, an unknown or ambiguous transaction manager stop the start.
- First version: Spring Data for Dart on Spring Data JDBC's model, with an in-memory store (SQLite and PostgreSQL come next).
  - Entities: `@Table`, `@Id`, `@Column`, `@Transient`, `@Version`, `@CreatedDate`, `@LastModifiedDate`, `@CreatedBy`, `@LastModifiedBy` (`@EnableDataAuditing`, `AuditorAware`), `@MappedCollection` children saved and deleted with their root, `AggregateReference` to other aggregates.
  - Repositories: an interface extending `DataRepository` (`CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`, `ListPagingAndSortingRepository`) is implemented by the generator and is a bean, no annotation needed; `@UseStore` and `@UseDataSource` choose its store and database.
  - Derived queries (`findTop5ByTitleContainingIgnoreCaseOrderByYearDesc`), checked when the repository is created: a wrong property stops the start with the reason and a suggestion.
  - `Sort`, `SortOrder`, `Pageable`, `PageRequest`, `Page`, `Slice`.
  - Optimistic locking with `@Version`: `OptimisticLockingFailureException` on a conflict.
  - Spring's `DataAccessException` hierarchy.
  - Logs: statements at debug; values only at trace, with names that look secret (`password`, `token`, `secret`, `key`) masked.
