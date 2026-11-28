// An application whose beans retry @Transactional methods: the generator
// writes the proxies (resilience_app.spring.dart, from
// `dart run build_runner build`) with spring.resilience.enabled: true.
import 'dart:async';

import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

import '../../spring_gen/resilience/app/resilience_app.spring.dart';
import '../../transaction/support/recording_transaction_manager.dart';

const _quick = Duration(milliseconds: 1);

/// The transaction manager.
@Configuration()
class Managers {
  @Bean()
  RecordingTransactionManager transactionManager() =>
      RecordingTransactionManager();
}

/// Retried methods with transactions of their own, or joining one.
@Service()
class Bookings {
  Bookings(this.manager);

  final RecordingTransactionManager manager;

  /// The transaction of each attempt.
  final transactions = <int?>[];

  /// Fails twice, in a new transaction each time.
  @Retryable(delay: _quick)
  @Transactional()
  Future<int?> book() async {
    transactions.add(manager.currentId);
    if (transactions.length < 3) {
      throw TimeoutException('busy');
    }
    return manager.currentId;
  }

  /// Fails; it has no transaction of its own.
  @Retryable(delay: _quick)
  Future<void> joining() async {
    transactions.add(manager.currentId);
    throw TimeoutException('busy');
  }

  /// Fails once, in a transaction of its own.
  @Retryable(delay: _quick)
  @Transactional(propagation: Propagation.requiresNew)
  Future<int?> onItsOwn() async {
    transactions.add(manager.currentId);
    if (transactions.length < 2) {
      throw TimeoutException('busy');
    }
    return manager.currentId;
  }

  /// A commit that failed is never retried.
  @Retryable(delay: _quick)
  Future<void> unknownOutcome() async {
    transactions.add(manager.currentId);
    throw TransactionSystemException('the commit failed');
  }
}

/// Opens the transactions [Bookings] joins.
@Service()
class Agency {
  Agency(this.bookings);

  final Bookings bookings;

  @Transactional()
  Future<void> joined() => bookings.joining();

  @Transactional()
  Future<int?> separate() => bookings.onItsOwn();
}

@SpringBootApplication()
Future<void> main(List<String> args) async {
  final context = await springApplication.runAsync(args);
  context.close();
}
