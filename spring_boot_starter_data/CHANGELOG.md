## Unreleased

- First version: Spring Data for Dart on Spring Data JDBC's model, with an in-memory store (SQLite and PostgreSQL come next).
  - Entities: `@Table`, `@Id`, `@Column`, `@Transient`, `@Version`, `@CreatedDate`, `@LastModifiedDate`, `@CreatedBy`, `@LastModifiedBy` (`@EnableDataAuditing`, `AuditorAware`), `@MappedCollection` children saved and deleted with their root, `AggregateReference` to other aggregates.
  - Repositories: an interface extending `DataRepository` (`CrudRepository`, `ListCrudRepository`, `PagingAndSortingRepository`, `ListPagingAndSortingRepository`) is implemented by the generator and is a bean, no annotation needed; `@UseStore` and `@UseDataSource` choose its store and database.
  - Derived queries (`findTop5ByTitleContainingIgnoreCaseOrderByYearDesc`), checked when the repository is created: a wrong property stops the start with the reason and a suggestion.
  - `Sort`, `SortOrder`, `Pageable`, `PageRequest`, `Page`, `Slice`.
  - Optimistic locking with `@Version`: `OptimisticLockingFailureException` on a conflict.
  - Spring's `DataAccessException` hierarchy.
  - Logs: statements at debug; values only at trace, with names that look secret (`password`, `token`, `secret`, `key`) masked.
