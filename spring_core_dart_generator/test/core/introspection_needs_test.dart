// A class is described for what the application does with it, as far as
// the build can see (`IntrospectionNeed`): getters for what is written out,
// constructor and setters for what is read in, methods where an expression
// may call them. A class reached by several routes gets the union.
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;
  late final List<String> errors;

  setUpAll(() async {
    (output, errors) = await generateNeeds(needsModels);
  });

  String shape(String name) => shapeOf(output, name);

  test('the generated code compiles', () {
    expect(errors, isEmpty);
  });

  group('a client interface', () {
    test('reads in the answer', () {
      expect(
        shape('CatalogItem'),
        'set name,owner; instantiate; constructor; parts write',
      );
    });

    test('writes out the arguments', () {
      expect(shape('CatalogRequest'), 'get filter; parts read');
    });
  });

  group('direct calls of the ObjectMapper', () {
    test('a type argument is read in, a value written out', () {
      expect(
        shape('Loaded'),
        'set x; instantiate; constructor; parts write',
      );
      expect(shape('Saved'), 'get y; parts read');
    });

    test('convertValue writes out its value and reads in its type', () {
      expect(shape('Source'), 'get z; parts read');
      expect(
        shape('Copy'),
        'set w; instantiate; constructor; parts write',
      );
    });

    test('a value of type Object names no class', () {
      expect(introspectionOf(output, 'Unseen'), isNull);
    });
  });

  group('explicit', () {
    test('@Introspected describes everything, and so what it is made of', () {
      expect(shape('Everything'), contains('methods work'));
      expect(shape('Everything'), contains('instantiate'));
      expect(shape('Everything'), isNot(contains('parts')));
      expect(shape('Inner'), contains('methods touch'));
      expect(shape('Inner'), isNot(contains('parts')));
    });

    test('a class listed in @Introspected(classes:) is described entirely', () {
      expect(shape('Listed'), contains('methods act'));
      expect(shape('Listed'), isNot(contains('parts')));
    });

    test('@ConfigurationProperties binds: setters and getters, no methods', () {
      expect(
        shape('AppProperties'),
        'get name,limits; set name,limits; instantiate; constructor; '
        'parts read,write',
      );
      expect(
        shape('Limits'),
        'get max; set max; instantiate; constructor; parts read,write',
      );
    });
  });
}
