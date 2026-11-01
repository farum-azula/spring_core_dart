# data_reference

The Spring side of the data starter's verification
([roadmap/spring_boot_starter_data.md](../../roadmap/spring_boot_starter_data.md),
step 4): a Spring Boot application (Spring Boot 4.1, Spring Data JDBC, Java 21,
Maven) with the same schema and the same transaction scenarios as
`spring_boot_starter_data/test/transaction_matrix`, run against the same
PostgreSQL and printing the same normalized outcomes as JSON.

```sh
cd tool/data_reference
mvn -q -DskipTests package
docker run --rm -d --name spring-matrix-pg -e POSTGRES_PASSWORD=test \
  -p 55433:5432 postgres:17
docker exec spring-matrix-pg psql -U postgres -c 'create database refdb'
java -jar target/data-reference-0.0.0.jar \
  --spring.datasource.url=jdbc:postgresql://localhost:55433/refdb \
  --spring.datasource.username=postgres --spring.datasource.password=test \
  --out=/tmp/spring_outcomes.json [--only=isolation/]
```

`spring_boot_starter_data/test/transaction_matrix/differential_test.dart`
(tag `differential`) starts the jar on a database of its own, runs the same
scenarios in the starter on another, and compares outcome by outcome:

```sh
(cd tool/data_reference && mvn -q -DskipTests package)
cd spring_boot_starter_data
SPRING_TEST_POSTGRES_URL=postgresql://postgres:test@localhost:55433/postgres \
  dart test -t differential
```

## The scenarios

`Scenarios` has them with their ids (`propagation/<outer>/<inner>/<variant>`,
`propagation-lock/<inner>`, `rules/*`, `template/*`, `readonly/*`,
`isolation/<anomaly>/<level>`, `lock/*`, `version/*`, `timeout/*`); the Dart
side has the same ids and keys (`scenarios.dart`).

- `Services` has the two `@Transactional` beans of the propagation matrix
  (`Outer` calls `Inner`, one method per propagation), `Methods` the other
  settings (rollback rules, read only, timeouts); a scenario's code only
  calls them.
- Two transactions side by side are `Session`s, each on a thread of its own,
  driven step by step. A statement that must wait for a lock is started
  without waiting, then `Env.awaitBlocked` polls `pg_stat_activity` until a
  backend waits for a lock (no sleeps), then the other transaction ends.
- `StockRepository` (`@Lock`) and `AccountRepository` (`@Version`) are Spring
  Data JDBC repositories; `NOWAIT`, `SKIP LOCKED` and `lock_timeout` are plain
  SQL (Spring Data has no annotation for them).
- An outcome is numbers, strings and lists; an error is `!ClassName[SQLSTATE]`.

## What the comparison found

The starter and Spring agree on every scenario but a few listed in
`spring_boot_starter_data/test/transaction_matrix/comparison.dart`, each with
its reason (the starter's README, "Compared with Spring"):

- Spring commits after a checked exception; Dart has none, every exception
  rolls back unless `noRollbackFor` lists it.
- A `@Lock` query outside a transaction runs in autocommit in Spring and
  fails in the starter.
- Spring 7's `JdbcTemplate` translates PostgreSQL errors by SQL state alone
  (`SQLExceptionSubclassTranslator`): `40001` is a
  `CannotAcquireLockException`, `40P01` a `PessimisticLockingFailureException`,
  `55P03` and `25006` an `UncategorizedSQLException`. The starter keeps the
  finer classes of Spring's PostgreSQL error-code table
  (`CannotSerializeTransactionException`,
  `DeadlockLoserDataAccessException`, `CannotAcquireLockException`,
  `InvalidDataAccessResourceUsageException`); the comparison treats them as
  equal (`equivalentKinds`).

Fixed in the starter, found by the comparison: a transaction that timed out
was not rollback-only (Spring marks it: the commit is an
`UnexpectedRollbackException`); a commit PostgreSQL refused came wrapped in a
`TransactionSystemException` (Spring throws the translated exception as it is);
`ConcurrencyFailureException` was missing from the hierarchy.
