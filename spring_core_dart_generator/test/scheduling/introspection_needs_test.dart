// A @Scheduled method reads and writes none of its values: the scheduling
// part describes nothing for it (IntrospectionNeed).
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;

  setUpAll(() async {
    (output, _) = await generateNeeds(needsModels);
  });

  group('a controller', () {
    test('a scheduled method describes nothing', () {
      expect(introspectionOf(output, 'Tick'), isNull);
    });
  });
}
