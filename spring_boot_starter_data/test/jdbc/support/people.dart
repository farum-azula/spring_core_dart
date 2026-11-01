// A class with a hand-written introspection for the row mapper tests.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';

enum Status { active, closed }

class Person {
  Person({
    required this.firstName,
    required this.lastName,
    this.age,
    this.status,
    this.joined,
    this.active = false,
  });

  final String firstName;
  final String lastName;
  final int? age;
  final Status? status;
  final DateTime? joined;
  final bool active;

  /// Set after construction (not a constructor parameter).
  String? nickname;

  @override
  String toString() => 'Person($firstName $lastName)';
}

const _s = ClassType<String>();
const _sn = ClassType<String>(nullable: true);
const _in = ClassType<int>(nullable: true);
const _st = EnumType<Status>(Status.values, nullable: true);
const _dn = ClassType<DateTime>(nullable: true);
const _b = ClassType<bool>();

BeanProperty<Person> _p(
  String n,
  Type t,
  TypeInfo<Object?> i,
  Object? Function(Person) g, [
  void Function(Person, Object?)? s,
]) => BeanProperty<Person>(
  n,
  type: t,
  typeInfo: i,
  nullable: i.nullable,
  get: g,
  set: s,
);

BeanParameter _a(String n, TypeInfo<Object?> i, {bool required = false}) =>
    BeanParameter(n, type: i, symbol: Symbol(n), isRequired: required);

BeanIntrospection<Person> personIntrospection() => BeanIntrospection<Person>(
  className: 'Person',
  properties: [
    _p('firstName', String, _s, (p) => p.firstName),
    _p('lastName', String, _s, (p) => p.lastName),
    _p('age', int, _in, (p) => p.age),
    _p('status', Status, _st, (p) => p.status),
    _p('joined', DateTime, _dn, (p) => p.joined),
    _p('active', bool, _b, (p) => p.active),
    _p(
      'nickname',
      String,
      _sn,
      (p) => p.nickname,
      (p, v) => p.nickname = v as String?,
    ),
  ],
  constructor: BeanConstructor<Person>(
    parameters: [
      _a('firstName', _s, required: true),
      _a('lastName', _s, required: true),
      _a('age', _in),
      _a('status', _st),
      _a('joined', _dn),
      _a('active', _b),
    ],
    create: (positional, named) =>
        Function.apply(Person.new, positional, named) as Person,
  ),
);

BeanIntrospector peopleIntrospector() =>
    BeanIntrospector(introspections: [personIntrospection()]);

/// The same class described as the build describes a class a `@Query`
/// returns.
EntityIntrospection<Person> personEntityIntrospection() =>
    EntityIntrospection<Person>(
      'Person',
      const [
        EntityProperty('firstName', _s, parameter: true),
        EntityProperty('lastName', _s, parameter: true),
        EntityProperty('age', _in, parameter: true),
        EntityProperty('status', _st, parameter: true),
        EntityProperty('joined', _dn, parameter: true),
        EntityProperty(
          'active',
          _b,
          parameter: true,
          hasDefaultValue: true,
          defaultValue: false,
        ),
        EntityProperty('nickname', _sn, writable: true),
      ],
      get: (p, i) => switch (i) {
        0 => p.firstName,
        1 => p.lastName,
        2 => p.age,
        3 => p.status,
        4 => p.joined,
        5 => p.active,
        _ => p.nickname,
      },
      create: (v) => Person(
        firstName: v[0]! as String,
        lastName: v[1]! as String,
        age: v[2] as int?,
        status: v[3] as Status?,
        joined: v[4] as DateTime?,
        active: v[5]! as bool,
      ),
      write: (p, i, v) => p.nickname = v as String?,
    );
