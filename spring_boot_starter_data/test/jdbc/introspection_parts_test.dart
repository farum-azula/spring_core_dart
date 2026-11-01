// The JDBC helpers on classes described for only some of their parts: the
// row mapper creates and fills a class, the bean parameter source reads
// one. A part that was left out is named, with the fix.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

class Note {
  Note({this.title = ''});
  String title;
}

BeanIntrospection<Note> describe(Set<IntrospectionPart> parts) {
  final read = parts.contains(IntrospectionPart.read);
  final write = parts.contains(IntrospectionPart.write);
  return BeanIntrospection<Note>(
    parts: parts,
    properties: [
      BeanProperty<Note>(
        'title',
        type: String,
        typeInfo: const ClassType<String>(),
        get: read ? (n) => n.title : null,
        set: write ? (n, v) => n.title = v! as String : null,
      ),
    ],
    instantiate: write ? Note.new : null,
  );
}

BeanIntrospector introspector(Set<IntrospectionPart> parts) =>
    BeanIntrospector()..register(describe(parts));

void main() {
  test('rows are mapped to a class described for writing', () {
    final mapper = DataClassRowMapper<Note>(
      introspector: introspector({IntrospectionPart.write}),
    );
    expect(mapper(JdbcRow(['title'], ['Dune'])).title, 'Dune');
  });

  test('rows are not mapped to a class described without a constructor', () {
    final mapper = DataClassRowMapper<Note>(
      introspector: introspector({IntrospectionPart.read}),
    );
    expect(
      () => mapper(JdbcRow(['title'], ['Dune'])),
      throwsA(
        isA<IntrospectionPartError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Note is described without its constructor and setters'),
            contains('rows are mapped to it'),
            contains('@Introspected()'),
          ),
        ),
      ),
    );
  });

  test('a parameter reads a class described for reading', () {
    final source = BeanPropertySqlParameterSource(
      Note(title: 'Dune'),
      introspector: introspector({IntrospectionPart.read}),
    );
    expect(source.getValue('title'), 'Dune');
  });

  test('a parameter does not read a class described without getters', () {
    final source = BeanPropertySqlParameterSource(
      Note(title: 'Dune'),
      introspector: introspector({IntrospectionPart.write}),
    );
    expect(
      () => source.getValue('title'),
      throwsA(
        isA<IntrospectionPartError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('Note is described without its getters'),
            contains("the parameter ':title' reads the property"),
          ),
        ),
      ),
    );
  });
}
