// Introspection metadata: `@Introspected` for JSON and the validation
// constraints.
import 'package:spring_core_dart_generator/src/core/bean_scanner.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

void main() {
  group('@Introspected for JSON', () {
    const source = """
enum Genre { fiction, science }

enum Stock {
  inStock('in_stock');

  const Stock(this.json);
  @JsonValue()
  final String json;
}

class Author {
  const Author(this.name, [this.born]);
  final String name;
  final int? born;
}

@Introspected()
class Book {
  const Book({
    required this.isbn,
    this.tags = const [],
    this.author,
    this.genre = Genre.fiction,
    this.stock = Stock.inStock,
    this.ratings = const {},
    this.extra = const {},
  });
  @JsonProperty('id')
  final String isbn;
  final List<String> tags;
  final Author? author;
  final Genre genre;
  final Stock stock;
  final Map<String, int> ratings;
  final Map<String, dynamic> extra;
}

class Money {
  Money(this.cents);
  @JsonCreator()
  Money.of({required int cents}) : this(cents);
  final int cents;
}

@Introspected(classes: [Money])
class Wallet {
  List<Money?> monies = [];
}

class Legacy {
  Legacy(this.v);
  factory Legacy.fromJson(Map<String, dynamic> json) => Legacy(json['v'] as String);
  final String v;
  Map<String, dynamic> toJson() => {'v': v};
}

@Introspected()
class Holder {
  Legacy? legacy;
}
""";

    test('types, constructors, JSON hints and used classes', () async {
      final output = await generateModule(source);
      // Its type comes from the typeInfo.
      expect(
        output,
        hasCode(
          "BeanProperty<Book>(r'tags', "
          'typeInfo: const ListType<String>(ClassType<String>()),',
        ),
      );
      expect(
        output,
        hasCode('typeInfo: const ClassType<Author>(nullable: true)'),
      );
      expect(
        output,
        hasCode(
          'typeInfo: EnumType<Stock>(Stock.values, '
          'jsonValue: (value) => value.json)',
        ),
      );
      expect(output, hasCode('typeInfo: const EnumType<Genre>(Genre.values)'));
      expect(
        output,
        hasCode(
          'typeInfo: const MapType<String, dynamic>( '
          'ClassType<String>(), DynamicType())',
        ),
      );
      // The constructor, with symbols for named parameters.
      expect(
        output,
        hasCode(
          "BeanParameter(r'isbn', type: const ClassType<String>(), "
          'symbol: #isbn, isRequired: true)',
        ),
      );
      // Called directly; an absent optional argument gets its default.
      expect(
        output,
        hasCode(
          '(List<Object?> positional, Map<Symbol, Object?> named) => '
          'Book(isbn: (named[#isbn] as String), '
          'tags: named.argumentOr(#tags, const <String>[]),',
        ),
      );
      // Author (used by Book, same package) is introspected automatically,
      // with positional parameters.
      expect(output, hasCode('BeanIntrospection<Author>('));
      expect(
        output,
        hasCode(
          "BeanParameter(r'born', type: ClassType<int>(nullable: true))",
        ),
      );
      // @Introspected(classes:) and @JsonCreator.
      // Wallet's description is a constant: no `const` inside it.
      expect(
        output,
        hasCode(
          'typeInfo: ListType<Money?>( '
          'ClassType<Money>(nullable: true))',
        ),
      );
      expect(output, hasCode('=> Money.of(cents: (named[#cents] as int));'));
      // A class with its own fromJson / toJson.
      expect(
        output,
        hasCode(
          '(Object? json) => '
          'Legacy.fromJson((json as Map<String, dynamic>));',
        ),
      );
      expect(output, hasCode('(Legacy bean) => bean.toJson();'));
      expect(
        output,
        matches(RegExp(r'fromJson:_\$fromJson\d+,toJson:_\$toJson\d+')),
      );
      // Enums are described by EnumType, not introspected.
      expect(output, isNot(contains('BeanIntrospection<Genre>')));
    });

    test('the generated code compiles', () async {
      expect(await compileErrors({'lib/src/service.dart': source}), isEmpty);
    });
  });

  group('validation', () {
    // 17 builds: about 2:35 alone, past dart_test.yaml's 3:00 under load.
    test('constraints on unsupported types fail the build', () async {
      final cases = <String, (String, String)>{
        'Size on int': (
          '@Introspected() class Form { @Size(max: 3) int age = 0; }',
          '@Size on Form.age: it validates String, Iterable, Map values, not '
              'int',
        ),
        'NotBlank on a list': (
          '@Introspected() class Form { @NotBlank() List<String> tags = []; }',
          '@NotBlank on Form.tags',
        ),
        'Past on a string': (
          '@Introspected() class Form { @Past() String? day; }',
          '@Past on Form.day: it validates DateTime values, not String',
        ),
        'AssertTrue on an int': (
          '@Introspected() class Form { @AssertTrue() int? ok; }',
          '@AssertTrue on Form.ok',
        ),
        'Min on an Object': (
          '@Introspected() class Form { @Min(1) Object? any; }',
          '@Min on Form.any',
        ),
        'constructor parameter': (
          '@Introspected() class Form { Form(@Email() this.id); final int id; '
              '}',
          '@Email on Form(id)',
        ),
        'method parameter': (
          '@Service() @Validated() class Users { '
              'void save(@NotBlank() int id) {} }',
          '@NotBlank on Users.save(id)',
        ),
        'return value': (
          '@Service() @Validated() class Users { '
              '@Size(max: 2) int count() => 1; }',
          '@Size on Users.count (return value)',
        ),
        'negative Size min': (
          '@Introspected() class Form { @Size(min: -1) String name = ""; }',
          'Invalid @Size on Form.name: the min parameter cannot be negative',
        ),
        'Size min > max': (
          '@Introspected() class Form { @Size(min: 5, max: 2) String name = '
              '""; }',
          'Invalid @Size on Form.name: min (5) is greater than max (2)',
        ),
        'negative Digits': (
          '@Introspected() class Form { '
              '@Digits(integer: -1, fraction: 0) int n = 0; }',
          'the length of the integer part cannot be negative',
        ),
        'malformed DecimalMin': (
          '@Introspected() class Form { @DecimalMin("1,5") double n = 0; }',
          'Invalid @DecimalMin on Form.n: "1,5" is not a decimal number',
        ),
        'malformed pattern': (
          '@Introspected() class Form { @Matches("[a-") String s = ""; }',
          'invalid regular expression "[a-"',
        ),
        'Each element type': (
          '@Introspected() class Form { '
              '@Each([NotBlank()]) List<int> ids = []; }',
          '@NotBlank on Form.ids (element): it validates String values, not '
              'int',
        ),
        'EachKey key type': (
          '@Introspected() class Form { '
              '@EachKey([AssertTrue()]) Map<String, int> m = {}; }',
          '@AssertTrue on Form.m (key): it validates bool values, not String',
        ),
        'Each on a non-container': (
          '@Introspected() class Form { @Each([NotBlank()]) String s = ""; }',
          '@Each on Form.s: it constrains the elements of an Iterable or the '
              'values of a Map, not String',
        ),
        'EachKey on a list': (
          '@Introspected() class Form { '
              '@EachKey([NotBlank()]) List<String> s = []; }',
          '@EachKey on Form.s: it constrains the keys of a Map',
        ),
      };
      for (final MapEntry(key: name, value: (source, message))
          in cases.entries) {
        final result = await buildPackage({
          'lib/src/beans.dart': scanRoot,
          'lib/src/service.dart': '$coreImport$source',
        }, proxyMode: ProxyMode.all);
        expect(result.succeeded, isFalse, reason: name);
        expect(result.errors.join('\n'), contains(message), reason: name);
      }
    }, timeout: const Timeout(Duration(minutes: 6)));

    test('supported types build', () async {
      final output = await generateModule('''
@Introspected()
class Form {
  @NotBlank() @Matches('[a-z]+') @Email() String? name;
  @Size(max: 3) @NotEmpty() Map<String, int> scores = {};
  @Size(max: 3) Set<int> ids = {};
  @Min(1) @Digits(integer: 3, fraction: 0) int age = 1;
  @DecimalMax('9.5') double rate = 0;
  @Positive() BigInt big = BigInt.one;
  @Max(10) String numeric = '1';
  @FutureOrPresent() DateTime? start;
  @AssertFalse() bool locked = false;
  @NotNull() Object? any;
  @Size(max: 1) dynamic loose;
  @Each([NotBlank(), Size(max: 3)]) List<String> names = [];
  @Each([Min(0)]) @EachKey([Size(min: 1, max: 5)]) Map<String, int> counts = {};
  @Each([NotNull()]) Set<Object?> anything = {};
}

@Service()
@Validated()
class Users {
  @NotBlank()
  Future<String> find(@Min(1) int id) async => 'x';
}
''', proxyMode: ProxyMode.all);
      expect(output, contains('Form'));
    });

    test('proxy signatures carry the parameter annotations', () async {
      final output = await generateModule('''
@Service()
@Validated()
class Users {
  @NotBlank()
  String register(@NotBlank() @Email() String email, int age, {@Valid() Object? extra}) => email;
}
''', proxyMode: ProxyMode.all);
      expect(
        output,
        hasCode(
          'parameterAnnotations: [[NotBlank(), Email()], [], '
          '[Valid()]]',
        ),
      );
    });

    test('the generated code compiles', () async {
      expect(
        await compileErrors({
          'lib/src/service.dart': '''
abstract interface class Registration {
  String register(@NotBlank() String email, {@Min(18) int age = 18});
}

@Service()
@Validated()
class DefaultRegistration implements Registration {
  @override
  @Size(max: 20)
  String register(String email, {int age = 18}) => email;
}
''',
        }),
        isEmpty,
      );
    });
  });
}
