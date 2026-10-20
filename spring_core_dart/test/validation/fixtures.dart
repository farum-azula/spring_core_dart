import 'package:spring_core_dart/spring_core_dart.dart';

class Address {
  Address([this.city = '']);
  String city;
  String? zip;
}

class Person {
  String name = '';
  int age = 0;
  double? score;
  Address? address;
  List<Address> previous = [];
  Map<String, Address> byLabel = {};
  List<String> tags = [];
  Map<String, int> counts = {};
  Set<int> lucky = {1, 2};
  final String id = 'p1';
  String hello(String other) => 'hello $other from $name';
}

final addressIntrospection = BeanIntrospection<Address>(
  properties: [
    BeanProperty<Address>(
      'city',
      type: String,
      get: (b) => b.city,
      set: (b, v) => b.city = v! as String,
      annotations: const [NotBlank()],
    ),
    BeanProperty<Address>(
      'zip',
      type: String,
      nullable: true,
      get: (b) => b.zip,
      set: (b, v) => b.zip = v as String?,
      annotations: const [Matches(r'\d{5}')],
    ),
  ],
  instantiate: Address.new,
);

class Adult extends Constraint {
  const Adult();
  @override
  String get name => 'Adult';
  @override
  String get defaultMessage => 'person must be an adult';
  @override
  bool isValid(Object? value) => value is! Person || value.age >= 18;
}

abstract final class Strict {}

final personIntrospection = BeanIntrospection<Person>(
  annotations: const [Adult()],
  properties: [
    BeanProperty<Person>(
      'name',
      type: String,
      get: (b) => b.name,
      set: (b, v) => b.name = v! as String,
      annotations: const [NotBlank(), Size(min: 2, max: 10)],
    ),
    BeanProperty<Person>(
      'age',
      type: int,
      get: (b) => b.age,
      set: (b, v) => b.age = v! as int,
      annotations: const [
        Min(0),
        Max(150, groups: [Strict]),
      ],
    ),
    BeanProperty<Person>(
      'score',
      type: double,
      nullable: true,
      get: (b) => b.score,
      set: (b, v) => b.score = v as double?,
    ),
    BeanProperty<Person>(
      'address',
      type: Address,
      nullable: true,
      get: (b) => b.address,
      set: (b, v) => b.address = v as Address?,
      annotations: const [Valid()],
    ),
    BeanProperty<Person>(
      'previous',
      type: List<Address>,
      get: (b) => b.previous,
      set: (b, v) => b.previous = v! as List<Address>,
      annotations: const [Valid()],
    ),
    BeanProperty<Person>(
      'byLabel',
      type: Map<String, Address>,
      get: (b) => b.byLabel,
      annotations: const [Valid()],
    ),
    BeanProperty<Person>(
      'tags',
      type: List<String>,
      get: (b) => b.tags,
      set: (b, v) => b.tags = v! as List<String>,
    ),
    BeanProperty<Person>(
      'counts',
      type: Map<String, int>,
      get: (b) => b.counts,
    ),
    BeanProperty<Person>('lucky', type: Set<int>, get: (b) => b.lucky),
    BeanProperty<Person>('id', type: String, get: (b) => b.id),
  ],
  methods: [
    BeanMethod<Person>(
      'hello',
      returnType: String,
      parameterTypes: const [String],
      invoke: (b, args) => b.hello(args.first! as String),
    ),
  ],
  instantiate: Person.new,
);

BeanIntrospector introspector() => BeanIntrospector(
  introspections: [personIntrospection, addressIntrospection],
);
