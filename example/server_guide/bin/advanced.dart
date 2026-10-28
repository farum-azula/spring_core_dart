// The advanced chapter, runnable: the application's beans with the
// `advanced` profile (and no web server), then contexts built by hand.
//
//   dart run bin/advanced.dart

import 'package:neon_books_server/src/advanced/alarm_registrar.dart';
import 'package:neon_books_server/src/advanced/bean_init_timer.dart';
import 'package:neon_books_server/src/advanced/demos.dart';
import 'package:neon_books_server/src/advanced/import_batch.dart';
import 'package:neon_books_server/src/advanced/lifecycle_probe.dart';
import 'package:neon_books_server/src/advanced/stock_report_printer.dart';
import 'package:neon_books_server/src/catalog/book.dart';
import 'package:neon_books_server/src/catalog/catalog_service.dart';
import 'package:neon_books_server/src/stock/stock_feed.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

import 'main.spring.dart';

/// The tool's output goes through a logger, not `print`; `main` raises its
/// level to info below, while the application's own loggers stay quiet.
const _log = SpringLog('advanced');

Future<void> main(List<String> args) async {
  // These start applications of their own, which set the log levels again:
  // run them before this tool sets its levels, show them at the end.
  final reports = failureReports();

  final context = await runApplicationAsync([
    '--spring.profiles.active=dev,advanced',
    '--spring.main.web-application-type=none',
    '--spring.main.register-shutdown-hook=false',
    '--spring.main.banner-mode=off',
    '--logging.level.root=warn',
    '--logging.level.shop=warn',
    '--logging.level.advanced=info',
    ...args,
  ]);
  void show(String label, Object? value) => _log.info('  $label: $value');

  _log.info('BeanPostProcessor: the slowest bean initializations');
  for (final MapEntry(:key, :value) in context.getBean<BeanInitTimer>().slowest(
    3,
  )) {
    show(key, value);
  }

  _log.info('Lifecycle callbacks of a bean, in order (closing comes below)');
  lifecycleEvents.map((e) => '  $e').forEach(_log.info);
  lifecycleEvents.clear();

  _log.info('Lifecycle: stop() and start() the running beans');
  final feed = context.getBean<StockFeed>();
  context.stop();
  show('stock feed running after stop()', feed.isRunning);
  context.start();
  show('after start()', feed.isRunning);

  _log.info('Custom scope (registered by a BeanFactoryPostProcessor)');
  final importer = context.getBean<CatalogImporter>();
  final first = importer.import(const [
    NewBook(
      isbn: '9780062316097',
      title: 'Sapiens',
      author: 'Yuval Noah Harari',
      price: 14.99,
      year: 2011,
      tags: ['history'],
    ),
    NewBook(
      isbn: '9780141439518',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      price: 5.99,
    ),
  ]);
  show('first batch', '${first.isbns} imported, ${first.rejected} rejected');
  final second = importer.import(const []);
  show('second batch (a new one)', '${second.isbns}, same: ${first == second}');

  _log.info('Bean definition registered by hand (registry post-processor)');
  show('lowStockAlarm', context.getBean<LowStockAlarm>().ringing());

  _log.info('@Configurable + autowireBean');
  final printer = StockReportPrinter();
  context.autowireCapableBeanFactory.autowireBean(printer);
  show('report', printer.print());

  final introspector = context.getBean<BeanIntrospector>();
  final books = context.getBean<Catalog>().all();
  _log.info('Parent and child contexts');
  final (child, heard) = parentAndChild();
  show('child', child);
  show('events heard by the parent', heard);

  _log.info('SpEL');
  spel(books, introspector).forEach(show);

  _log.info('DataBinder and BeanWrapper');
  final (settings, errors) = bindShopSettings({
    'name': 'Ignored',
    'opensAt': '22',
    'closesAt': '20',
    'maxBasketSize': 'many',
  }, introspector);
  show('bound', 'opens ${settings.opensAt}, closes ${settings.closesAt}');
  errors.forEach(_log.info);

  _log.info('Startup failure reports');
  reports.forEach((label, report) => _log.info('--- $label\n$report'));

  // Last, so that every line above is logged by the running application's
  // logging (it ends with the context).
  await context.closeAsync();
  _log.info('Closing: the destroy callbacks');
  lifecycleEvents.map((e) => '  $e').forEach(_log.info);
}
