// What the expressions of the cache annotations reach: the classes their
// keys, conditions and unless read (the cache part, IntrospectionNeed).
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;

  setUpAll(() async {
    (output, _) = await generateNeeds(needsModels);
  });

  String shape(String name) => shapeOf(output, name);

  group('expressions', () {
    test('the expressions of @Caching are read too', () {
      expect(shape('NestedKey'), contains('methods'));
    });

    test('the bean itself is described when an expression names target', () {
      expect(shape('Orders'), contains('get prefix'));
      expect(shape('Orders'), contains('methods cancel'));
    });

    test('a result no expression looks at is not described', () {
      expect(introspectionOf(output, 'Hit'), isNull);
    });
  });
}
