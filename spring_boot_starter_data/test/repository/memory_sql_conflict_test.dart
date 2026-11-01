import 'package:test/test.dart';

import '../support/app.dart';

void main() {
  test(
    "a name both a SQL database and a memory repository's stops the start",
    () async {
      Object? failure;
      await exampleRunner
          .withPropertyValues([
            'spring.datasources.catalog.url=sqlite::memory:',
          ])
          .runAsync<void>((context) => failure = context.startupFailure);
      expect('$failure', contains("'catalog' is configured as a SQL database"));
      expect('$failure', contains("drop @UseStore('memory')"));
    },
  );
}
