import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// Declared as: zeta, beta, id (a JSON name `a_first`), alpha.
class Plain {
  String zeta = 'z';
  String beta = 'b';
  String hidden = 'h';
  String alpha = 'a';
}

class Listed extends Plain {}

class Sorted extends Plain {}

class Unknown extends Plain {}

// Constructor parameters (zip, city) and other properties (note, abc).
class Address {
  const Address({required this.zip, required this.city});
  final String zip;
  final String city;
  String get note => 'n';
  String get abc => 'x';
}

BeanProperty<T> _property<T extends Object>(
  String name,
  String Function(T) get, {
  List<Object> annotations = const [],
}) => BeanProperty<T>(
  name,
  type: String,
  typeInfo: const ClassType<String>(),
  get: get,
  annotations: annotations,
);

List<BeanProperty<T>> _plainProperties<T extends Plain>() => [
  _property<T>('zeta', (b) => b.zeta),
  _property<T>('beta', (b) => b.beta),
  _property<T>(
    'hidden',
    (b) => b.hidden,
    annotations: const [JsonProperty('a_first')],
  ),
  _property<T>('alpha', (b) => b.alpha),
];

final _introspector = BeanIntrospector(
  introspections: [
    BeanIntrospection<Plain>(
      properties: _plainProperties<Plain>(),
      instantiate: Plain.new,
    ),
    BeanIntrospection<Listed>(
      annotations: const [
        JsonPropertyOrder(['alpha', 'hidden', 'nothing']),
      ],
      properties: _plainProperties<Listed>(),
      instantiate: Listed.new,
    ),
    BeanIntrospection<Sorted>(
      annotations: const [
        JsonPropertyOrder.alphabetic(value: ['beta']),
      ],
      properties: _plainProperties<Sorted>(),
      instantiate: Sorted.new,
    ),
    BeanIntrospection<Unknown>(
      annotations: const [
        // The Dart name of a renamed property works too.
        JsonPropertyOrder(['hidden']),
      ],
      properties: _plainProperties<Unknown>(),
      instantiate: Unknown.new,
    ),
    BeanIntrospection<Address>(
      properties: [
        _property<Address>('zip', (b) => b.zip),
        _property<Address>('note', (b) => b.note),
        _property<Address>('city', (b) => b.city),
        _property<Address>('abc', (b) => b.abc),
      ],
      constructor: BeanConstructor<Address>(
        parameters: const [
          BeanParameter(
            'zip',
            type: ClassType<String>(),
            symbol: #zip,
            isRequired: true,
          ),
          BeanParameter(
            'city',
            type: ClassType<String>(),
            symbol: #city,
            isRequired: true,
          ),
        ],
        create: (positional, named) =>
            Function.apply(Address.new, positional, named) as Address,
      ),
    ),
  ],
);

List<String> _keys(ObjectMapper mapper, Object value) =>
    (mapper.valueToTree(value)! as Map<String, Object?>).keys.toList();

void main() {
  final sorted = ObjectMapper(introspector: _introspector);
  final declared = ObjectMapper(
    introspector: _introspector,
    sortPropertiesAlphabetically: false,
  );

  test('properties are sorted by JSON name by default (Jackson 3)', () {
    expect(_keys(sorted, Plain()), ['a_first', 'alpha', 'beta', 'zeta']);
    expect(
      sorted.writeValueAsString(Plain()),
      '{"a_first":"h","alpha":"a","beta":"b","zeta":"z"}',
    );
  });

  test('sortPropertiesAlphabetically: false keeps the declaration order', () {
    expect(_keys(declared, Plain()), ['zeta', 'beta', 'a_first', 'alpha']);
  });

  test('sorting follows the naming strategy', () {
    final snake = ObjectMapper(
      introspector: _introspector,
      namingStrategy: PropertyNamingStrategy.upperCamelCase,
    );
    expect(_keys(snake, Plain()), ['Alpha', 'Beta', 'Zeta', 'a_first']);
  });

  test('@JsonPropertyOrder lists names first, the rest follow', () {
    // Names that are not properties are skipped; the rest is sorted ...
    expect(_keys(sorted, Listed()), ['alpha', 'a_first', 'beta', 'zeta']);
    // ... or stays in declaration order when the mapper does not sort.
    expect(_keys(declared, Listed()), ['alpha', 'a_first', 'zeta', 'beta']);
  });

  test('@JsonPropertyOrder accepts the Dart name of a property', () {
    expect(_keys(sorted, Unknown()), ['a_first', 'alpha', 'beta', 'zeta']);
    expect(_keys(declared, Unknown()), ['a_first', 'zeta', 'beta', 'alpha']);
  });

  test('@JsonPropertyOrder.alphabetic sorts although the mapper does not', () {
    expect(_keys(declared, Sorted()), ['beta', 'a_first', 'alpha', 'zeta']);
    expect(_keys(sorted, Sorted()), ['beta', 'a_first', 'alpha', 'zeta']);
  });

  test('constructor parameters come first, each group sorted', () {
    expect(_keys(sorted, const Address(zip: '1', city: 'c')), [
      'city',
      'zip',
      'abc',
      'note',
    ]);
    // Without sorting nothing moves (the previous behaviour).
    expect(_keys(declared, const Address(zip: '1', city: 'c')), [
      'zip',
      'note',
      'city',
      'abc',
    ]);
  });

  test('reading does not depend on the order', () {
    final address = sorted.readValue<Address>(
      '{"note":"ignored","zip":"9","city":"Oslo"}',
    );
    expect((address.zip, address.city), ('9', 'Oslo'));
  });
}
