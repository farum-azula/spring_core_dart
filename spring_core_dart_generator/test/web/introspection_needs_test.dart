// What a controller's mappings and exception handlers need of the classes
// they read and write (the web part, IntrospectionNeed).
import 'package:test/test.dart';

import '../support/introspection_needs.dart';

void main() {
  late final String output;

  setUpAll(() async {
    (output, _) = await generateNeeds(needsModels);
  });

  String shape(String name) => shapeOf(output, name);

  group('a controller', () {
    test('writes out what it returns, and a test reads it back', () {
      // `mapper.readValue<BookView>(res.body)` in test/, which is not
      // scanned: the getters and the constructor and setters.
      expect(
        shape('BookView'),
        'get title,author; set title,author; instantiate; constructor; '
        'parts read,write',
      );
    });

    test('a class its answer is made of is written out too', () {
      expect(shape('Author'), contains('get name'));
      expect(shape('Page<dynamic>'), contains('get items,total'));
      expect(shape('Page<dynamic>'), isNot(contains('methods')));
      expect(shape('PageItem'), 'get title; constructor; parts read,write');
    });

    test('an exception handler answer is written out and read back', () {
      expect(shape('Problem'), 'get message; constructor; parts read,write');
    });

    test('reads in a body: constructor and setters only', () {
      expect(
        shape('NewBook'),
        'set title,author; instantiate; constructor; parts write',
      );
    });

    test('a validated body also gets the getters of its constraints', () {
      expect(
        shape('CheckedBook'),
        'get title; set title,note; instantiate; constructor; parts write',
      );
    });

    test('a class reached by several routes gets the union', () {
      // Written out (BookView, Page) and read in (NewBook): both.
      expect(
        shape('Author'),
        'get name; set name; instantiate; constructor; parts read,write',
      );
      // An expression's argument that is also a body.
      expect(
        shape('Order'),
        'get owner; set owner; instantiate; constructor; '
        'methods cancel',
      );
    });

    test('a class that is read and written gets both, no methods', () {
      expect(
        shape('Echo'),
        'get text; set text; instantiate; constructor; parts read,write',
      );
    });

    test('a class that compares with a new instance also has one', () {
      expect(
        shape('Counter'),
        'get count; set count; instantiate; constructor; parts read,write',
      );
    });

    test('a JSON annotation keeps the method it marks', () {
      expect(
        shape('Tag'),
        'get label; constructor; methods asText; parts read,write',
      );
      expect(shape('Bag'), contains('methods put'));
      expect(shape('Bag'), isNot(contains('other')));
    });

    test('the subtypes of a base take its need, a view class none', () {
      expect(shape('Animal'), contains('parts read,write'));
      expect(shape('Dog'), 'get name; constructor; parts read,write');
      expect(shape('Public'), 'parts');
    });
  });
}
