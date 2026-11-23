// A request's sort the REST API cannot run is the caller's mistake (a 400 in
// the web glue), not a server error (S1): an unknown property is a
// PropertyReferenceException, an order that ignores case an
// InvalidDataArgumentException.
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app_support.dart';

void main() {
  test('unknown or case-ignoring sort from a request is a 400 kind', () async {
    final transport = MockHttpTransport();
    transport
        .when(HttpMethod.get, '/rest/v1/todos')
        .respond(200, json: [], headers: {'Content-Range': '*/0'});
    await appRunner(transport).runAsync((context) async {
      final todos = context.getBean<Todos>();
      const paging = WebPaging();
      await expectLater(
        todos.findByListId(
          'l1',
          paging.pageable({
            'sort': ['nope'],
          }),
        ),
        throwsA(isA<PropertyReferenceException>()),
      );
      await expectLater(
        todos.findByListId(
          'l1',
          paging.pageable({
            'sort': ['title,ignorecase'],
          }),
        ),
        throwsA(isA<InvalidDataArgumentException>()),
      );
    });
  });
}
