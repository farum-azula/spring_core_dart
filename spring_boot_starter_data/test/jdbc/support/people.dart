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
