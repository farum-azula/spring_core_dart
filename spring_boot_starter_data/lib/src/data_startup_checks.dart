import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_data/src/data_failure_analyzer.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_interceptor.dart';
import 'package:spring_boot_starter_data/src/transaction/transaction_validator.dart';

const _dataSource = 'package:spring_boot_starter_data#DataAutoConfiguration';

/// The startup checks of the starter, in the build by
/// `spring.main.startup-checks.enabled` (by default in debug builds only,
/// so a profile or a release build ships none of their code):
///
/// - `transactionValidator` — fails the startup for a `@Transactional`
///   method that is not async, or a transaction manager it names that does
///   not exist (see [TransactionValidator]); without it the mistake fails
///   the method's first call;
/// - `dataFailureAnalyzer` — explains the startup failures of a database
///   (see [DataFailureAnalyzer]); without it the failure is reported as it
///   was thrown.
///
/// The validator only with a [TransactionInterceptor] (the main module's,
/// unless that is excluded). No other bean depends on them. They keep the
/// sources of the auto-configurations they came from
/// (`DataAutoConfiguration`, `DataSourceAutoConfiguration`), so excluding
/// one of those by name leaves its check out too.
final dataStartupChecks = <BeanDefinition<Object>>[
  BeanDefinition<TransactionValidator>(
    name: 'transactionValidator',
    types: const [TransactionValidator, BeanPostProcessor, BeanFactoryAware],
    source: _dataSource,
    conditions: const [
      ConditionGroup('$_dataSource.transactionValidator', [
        startupChecksEnabled,
        ConditionalOnBean(TransactionInterceptor),
      ]),
    ],
    create: (_) => TransactionValidator(),
  ),
  BeanDefinition<DataFailureAnalyzer>(
    name: 'dataFailureAnalyzer',
    types: const [DataFailureAnalyzer, FailureAnalyzer],
    source: 'package:spring_boot_starter_data#DataSourceAutoConfiguration',
    conditions: const [startupChecksEnabled],
    create: (_) => const DataFailureAnalyzer(),
  ),
];
