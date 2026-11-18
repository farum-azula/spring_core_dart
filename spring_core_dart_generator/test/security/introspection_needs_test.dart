// What the expressions of the security annotations reach: the arguments
// and results @PreAuthorize and @PostAuthorize read, nothing for roles
// (the security part, IntrospectionNeed). Two tests check a cache
// annotation's class next to a security one's.
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;

  setUpAll(() async {
    (output, _) = await generateNeeds(needsModels);
  });

  String shape(String name) => shapeOf(output, name);

  group('expressions', () {
    test('an argument they name is read and its methods called', () {
      expect(shape('Order'), contains('get owner'));
      expect(shape('Order'), contains('methods cancel'));
      expect(shape('SearchQuery'), contains('methods'));
      expect(shape('SearchQuery'), isNot(contains('instantiate')));
      expect(shape('SearchQuery'), isNot(contains('set ')));
    });

    test('so is a result they look at', () {
      expect(shape('Invoice'), contains('methods'));
      expect(shape('Stored'), contains('methods'));
    });

    test('an expression that reads no value describes nothing', () {
      // `hasRole('ADMIN')` and `@Secured` name no argument.
      expect(introspectionOf(output, 'Untouched'), isNull);
    });
  });
}
