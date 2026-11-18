// The line an application sees at start when its repositories keep their
// data in memory: said once per store, at the first repository given it,
// and not at all for a repository of another store.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import '../mapping/support.dart';
import '../repository/support/plain_store.dart';

void main() {
  late List<SpringLogRecord> records;
  late void Function() stop;

  setUp(() {
    records = [];
    stop = SpringLog.listen(records.add);
  });
  tearDown(() => stop());

  List<String> starts() => [
    for (final record in records)
      if (record.message.contains('Starting...')) record.message,
  ];

  test('the first repository of the in-memory store says it, once', () {
    final converter = EntityConverter();
    RepositoryFactory(mappingContext: testContext(), converter: converter)
      ..operations<Book, int>('Books')
      ..operations<Book, int>('MoreBooks');
    const line =
        'memory - Starting... (in memory: the data lives until the '
        'application stops)';
    expect(starts(), [line]);
    expect(
      records.singleWhere((r) => r.message.contains('Starting...')).level,
      SpringLogLevel.info,
    );
  });

  test('a repository of another store says nothing of memory', () {
    final converter = EntityConverter();
    final store = PlainStore(InMemoryDataStore(converter: converter));
    RepositoryFactory(
      mappingContext: testContext(),
      converter: converter,
      stores: [store],
    ).operations<Book, int>('Books', annotations: [UseStore(store.name)]);
    expect(starts(), isEmpty);
  });
}
