// @Cacheable over a repository-backed Page method: the key is the call's
// arguments (a PageRequest compares by value), the cached Page keeps what
// the repository returned.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  Future<void> seed(App app) => app.items.saveAll([
    for (var i = 1; i <= 45; i++) Item(name: 'item $i', count: i),
  ]);

  test(
    'an equal PageRequest hits the cache, another page misses',
    () => withApp((app) async {
      await seed(app);
      final catalog = app.catalog;

      final first = await catalog.page(0, PageRequest.of(0, 20));
      expect(catalog.calls, 1);
      expect(first.content, hasLength(20));
      expect(first.number, 0);
      expect(first.size, 20);
      expect(first.totalElements, 45);
      expect(first.totalPages, 3);

      // A new PageRequest, equal by value: the repository is not asked.
      final again = await catalog.page(0, PageRequest.of(0, 20));
      expect(catalog.calls, 1);
      expect(again, same(first));
      expect(again.number, 0);
      expect(again.size, 20);
      expect(again.totalElements, 45);
      expect([for (final i in again.content) i.name].first, 'item 1');

      // Another page, another size and another argument are other keys.
      final second = await catalog.page(0, PageRequest.of(1, 20));
      expect(catalog.calls, 2);
      expect(second.number, 1);
      expect(second.content.first.name, 'item 21');
      expect(second.totalElements, 45);

      final last = await catalog.page(0, PageRequest.of(2, 20));
      expect(catalog.calls, 3);
      expect(last.content, hasLength(5));
      expect(last.hasNext, isFalse);

      await catalog.page(0, PageRequest.of(0, 10));
      expect(catalog.calls, 4);
      await catalog.page(10, PageRequest.of(0, 20));
      expect(catalog.calls, 5);

      // Known caveat: the cache keeps the instances the repository
      // returned, not copies. Everyone who gets the cached page shares
      // its entities, so a change made to one is seen by all the others
      // (and the store is not changed by it).
      first.content.first.name = 'changed';
      final shared = await catalog.page(0, PageRequest.of(0, 20));
      expect(shared.content.first.name, 'changed');
      expect(identical(shared.content.first, first.content.first), isTrue);
      expect((await app.items.findById(1))!.name, 'item 1');
    }),
  );
}
