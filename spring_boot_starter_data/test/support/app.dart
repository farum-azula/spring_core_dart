// The example application, started the way an application's tests start it:
// its generated module and the starter's auto-configuration in an
// ApplicationContextRunner.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_auto_configuration.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

import '../../example/example.dart';
import '../../example/example.spring.dart';

export '../../example/example.dart';

/// The runner of the example: its beans and the Data auto-configuration.
ApplicationContextRunner get exampleRunner => const ApplicationContextRunner()
    .withUserConfiguration($application)
    .withAutoConfiguration(springBootStarterDataAutoConfiguration);

/// Starts the example (a runner with more beans when [runner] is given) and
/// calls [body] with the started context, which must not have failed.
Future<void> withExample(
  FutureOr<void> Function(Example example) body, {
  ApplicationContextRunner? runner,
}) => (runner ?? exampleRunner).runAsync((context) async {
  if (context.startupFailure case final failure?) {
    throw StateError('The example did not start: $failure');
  }
  await body(Example(context));
});

/// What the tests reach in the started example.
final class Example {
  Example(this.context);

  final AssertableApplicationContext context;

  BookRepository get books => context.getBean<BookRepository>();
  AuthorRepository get authors => context.getBean<AuthorRepository>();
  PurchaseOrderRepository get orders =>
      context.getBean<PurchaseOrderRepository>();
  AccountRepository get accounts => context.getBean<AccountRepository>();
  TicketRepository get tickets => context.getBean<TicketRepository>();
  InMemoryDataStore get store => context.getBean<InMemoryDataStore>();
  RelationalMappingContext get mapping =>
      context.getBean<RelationalMappingContext>();

  PersistentEntity<T> entity<T extends Object>() =>
      mapping.getRequiredPersistentEntity<T>();
}

AggregateReference<Author, int> author(int id) =>
    AggregateReference<Author, int>(id);

/// The books the query tests run on, saved in this order (ids 1 to 8).
Future<void> seedBooks(BookRepository books) async {
  await books.saveAll([
    Book(title: 'Dune', year: 1965, author: author(1)),
    Book(
      title: 'Dune Messiah',
      year: 1969,
      subtitle: 'sequel',
      author: author(1),
    ),
    Book(
      title: 'Neuromancer',
      year: 1984,
      subtitle: 'cyber',
      inStock: false,
      author: author(2),
    ),
    Book(title: 'Snow Crash', year: 1992, author: author(2)),
    Book(
      title: 'Cryptonomicon',
      year: 1999,
      subtitle: 'huge',
      inStock: false,
      author: author(2),
    ),
    Book(title: '100% Pure', year: 2001),
    Book(title: 'a_b', year: 2002),
    Book(title: 'axb', year: 2003),
  ]);
}

List<int?> ids(Iterable<Book> books) => [for (final b in books) b.id];
