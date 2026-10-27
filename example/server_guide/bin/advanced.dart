// The advanced chapter, runnable: the application's beans with the
// `advanced` profile (and no web server), then contexts built by hand.
//
//   dart run bin/advanced.dart

// A command line tool: the results go to the console.
// ignore_for_file: avoid_print
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

Future<void> main(List<String> args) async {
  final context = await runApplicationAsync([
    '--spring.profiles.active=dev,advanced',
    '--spring.main.web-application-type=none',
    '--spring.main.register-shutdown-hook=false',
    '--spring.main.banner-mode=off',
    '--logging.level.root=warn',
    '--logging.level.shop=warn',
    ...args,
  ]);
  void show(String label, Object? value) => print('  $label: $value');

  print('BeanPostProcessor: the slowest bean initializations');
  for (final MapEntry(:key, :value) in context.getBean<BeanInitTimer>().slowest(
    3,
  )) {
    show(key, value);
  }

  print('Lifecycle callbacks of a bean, in order (closing comes below)');
  lifecycleEvents.map((e) => '  $e').forEach(print);
  lifecycleEvents.clear();

  print('Lifecycle: stop() and start() the running beans');
  final feed = context.getBean<StockFeed>();
  context.stop();
  show('stock feed running after stop()', feed.isRunning);
  context.start();
  show('after start()', feed.isRunning);

  print('Custom scope (registered by a BeanFactoryPostProcessor)');
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

  print('Bean definition registered by hand (registry post-processor)');
  show('lowStockAlarm', context.getBean<LowStockAlarm>().ringing());

  print('@Configurable + autowireBean');
  final printer = StockReportPrinter();
  context.autowireCapableBeanFactory.autowireBean(printer);
  show('report', printer.print());

  final introspector = context.getBean<BeanIntrospector>();
  final books = context.getBean<Catalog>().all();
  await context.closeAsync();
  print('Closing: the destroy callbacks');
  lifecycleEvents.map((e) => '  $e').forEach(print);

  print('Parent and child contexts');
  final (child, heard) = parentAndChild();
  show('child', child);
  show('events heard by the parent', heard);

  print('SpEL');
  spel(books, introspector).forEach(show);

  print('DataBinder and BeanWrapper');
  final (settings, errors) = bindShopSettings({
    'name': 'Ignored',
    'opensAt': '22',
    'closesAt': '20',
    'maxBasketSize': 'many',
  }, introspector);
  show('bound', 'opens ${settings.opensAt}, closes ${settings.closesAt}');
  errors.forEach(print);

  print('Startup failure reports');
  failureReports().forEach((label, report) => print('--- $label\n$report'));
}
