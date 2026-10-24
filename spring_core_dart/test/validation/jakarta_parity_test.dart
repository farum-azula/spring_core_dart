import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// One property `value` carrying the annotations under test.
class Box {
  Box(this.value);
  Object? value;
}

BeanIntrospection<Box> _box(List<Object> annotations) => BeanIntrospection<Box>(
  properties: [
    BeanProperty<Box>(
      'value',
      type: Object,
      nullable: true,
      get: (b) => b.value,
      set: (b, v) => b.value = v,
      annotations: annotations,
    ),
  ],
  instantiate: () => Box(null),
);

List<ConstraintViolation> _validate(
  Object? value,
  List<Object> annotations, {
  List<Type> groups = const [],
}) => BeanValidator(
  introspector: BeanIntrospector(
    introspections: [_box(annotations), addressIntrospection],
  ),
).validateObject(Box(value), groups: groups);

List<String> _paths(List<ConstraintViolation> violations) => [
  for (final v in violations) v.propertyPath,
];

abstract final class Expensive {}

abstract final class DriverChecks {}

abstract final class Complete {}

abstract final class Cyclic {}

class Order {
  String sku = '';
  String warehouse = '';
}

class _InStock extends Constraint {
  const _InStock({super.groups});
  @override
  String get name => 'InStock';
  @override
  String get defaultMessage => 'not in stock';
  @override
  bool isValid(Object? value) => value == 'main';
}

BeanIntrospection<Order> _order(List<Type> sequence) =>
    BeanIntrospection<Order>(
      annotations: [GroupSequence(sequence)],
      properties: [
        BeanProperty<Order>(
          'sku',
          type: String,
          get: (b) => b.sku,
          annotations: const [NotBlank()],
        ),
        BeanProperty<Order>(
          'warehouse',
          type: String,
          get: (b) => b.warehouse,
          annotations: const [
            _InStock(groups: [Expensive]),
          ],
        ),
      ],
    );

class Driver {
  String name = '';
  bool licensed = false;
}

class Car {
  Driver? driver = Driver();
}

final _driverIntrospection = BeanIntrospection<Driver>(
  properties: [
    BeanProperty<Driver>(
      'name',
      type: String,
      get: (b) => b.name,
      annotations: const [NotBlank()],
    ),
    BeanProperty<Driver>(
      'licensed',
      type: bool,
      get: (b) => b.licensed,
      annotations: const [
        AssertTrue(groups: [DriverChecks]),
      ],
    ),
  ],
);

BeanIntrospection<Car> _car(List<Object> annotations) => BeanIntrospection<Car>(
  properties: [
    BeanProperty<Car>(
      'driver',
      type: Driver,
      nullable: true,
      get: (b) => b.driver,
      annotations: annotations,
    ),
  ],
);

class Lottery {
  Set<Address> lucky = {};
}

final _lotteryIntrospection = BeanIntrospection<Lottery>(
  properties: [
    BeanProperty<Lottery>(
      'lucky',
      type: Set<Address>,
      get: (b) => b.lucky,
      annotations: const [Valid()],
    ),
  ],
);

class Survey {
  List<String> answers = [];
  Map<String, int> scores = {};
}

final _surveyIntrospection = BeanIntrospection<Survey>(
  properties: [
    BeanProperty<Survey>(
      'answers',
      type: List<String>,
      get: (b) => b.answers,
      set: (b, v) => b.answers = v! as List<String>,
      annotations: const [
        Each([NotBlank()]),
      ],
    ),
    BeanProperty<Survey>(
      'scores',
      type: Map<String, int>,
      get: (b) => b.scores,
      annotations: const [
        Each([Min(0)]),
        EachKey([Size(max: 4)]),
      ],
    ),
  ],
  instantiate: Survey.new,
);

void main() {
  group('DataBinder.allowedFields', () {
    test('an empty list allows every field (Spring: no patterns)', () {
      final binder = DataBinder(
        Address(),
        introspector: BeanIntrospector(introspections: [addressIntrospection]),
      )..allowedFields = [];
      binder.bind({'city': 'Kyiv', 'zip': '01001'});
      final address = binder.target! as Address;
      expect(address.city, 'Kyiv');
      expect(address.zip, '01001');
    });

    test('a non-empty list still restricts', () {
      final binder = DataBinder(
        Address(),
        introspector: BeanIntrospector(introspections: [addressIntrospection]),
      )..allowedFields = ['city'];
      binder.bind({'city': 'Kyiv', 'zip': '01001'});
      expect((binder.target! as Address).zip, isNull);
    });
  });

  group('invalid constraint parameters (Hibernate Validator)', () {
    final cases = <String, (Constraint, String)>{
      'Size(min: -1)': (
        const Size(min: -1),
        'The min parameter cannot be negative.',
      ),
      'Size(max: -1)': (
        const Size(max: -1),
        'The max parameter cannot be negative.',
      ),
      'Size(min: 5, max: 2)': (
        const Size(min: 5, max: 2),
        'The length cannot be negative.',
      ),
      'Digits(integer: -1)': (
        const Digits(integer: -1, fraction: 0),
        'The length of the integer part cannot be negative.',
      ),
      'Digits(fraction: -1)': (
        const Digits(integer: 1, fraction: -1),
        'The length of the fraction part cannot be negative.',
      ),
      "DecimalMin('1,5')": (
        const DecimalMin('1,5'),
        '1,5 does not represent a valid BigDecimal format.',
      ),
      "DecimalMax('x')": (
        const DecimalMax('x'),
        'x does not represent a valid BigDecimal format.',
      ),
      'Min(double.nan)': (const Min(double.nan), 'NaN is not a finite number.'),
      "Matches('[a-')": (const Matches('[a-'), 'Invalid regular expression'),
      "Email(regexp: '(')": (
        const Email(regexp: '('),
        'Invalid regular expression',
      ),
    };
    for (final MapEntry(key: name, value: (constraint, message))
        in cases.entries) {
      test('$name is rejected when validating, even for null', () {
        expect(
          () => _validate(null, [constraint]),
          throwsA(
            isA<ConstraintDeclarationException>()
                .having((e) => e, 'is a', isA<ValidationException>())
                .having((e) => e.message, 'message', contains(message)),
          ),
        );
        expect(constraint.checkParameters, throwsA(isA<ValidationException>()));
      });
    }

    test('valid parameters pass', () {
      expect(_validate('ab', const [Size(min: 2, max: 2)]), isEmpty);
      expect(
        _validate(1, const [Digits(integer: 0, fraction: 0)]),
        hasLength(1),
      );
      expect(_validate(null, const [DecimalMin(' 1.5e3 ')]), isEmpty);
    });
  });

  group('UnexpectedTypeException', () {
    test('a built-in constraint on a value it does not support throws', () {
      final cases = <Constraint, Object>{
        const Size(max: 3): 42,
        const NotBlank(): ['a'],
        const NotEmpty(): 1,
        const Min(1): true,
        const Past(): '2020-01-01',
        const AssertTrue(): 1,
        const Email(): 1,
      };
      for (final MapEntry(key: constraint, :value) in cases.entries) {
        expect(
          () => _validate(value, [constraint]),
          throwsA(
            isA<UnexpectedTypeException>().having(
              (e) => e.message,
              'message',
              "No validator could be found for constraint '${constraint.name}' "
                  "validating type '${value.runtimeType}'. Check "
                  "configuration for 'value'",
            ),
          ),
          reason: '$constraint',
        );
      }
    });

    test('null values, supported types and custom constraints pass', () {
      expect(_validate(null, const [Size(max: 3), Past()]), isEmpty);
      expect(_validate([1, 2], const [Size(max: 3), NotEmpty()]), isEmpty);
      expect(
        _validate('12', const [Min(1), Digits(integer: 2, fraction: 0)]),
        isEmpty,
      );
      expect(_validate(BigInt.two, const [Positive()]), isEmpty);
      expect(_validate(42, const [NotNull()]), isEmpty);
      expect(_validate(Object(), const [_InStock()]), hasLength(1));
    });
  });

  group('@Valid on a Set', () {
    final introspector = BeanIntrospector(
      introspections: [_lotteryIntrospection, addressIntrospection],
    );

    test('elements are reported as lucky[].city', () {
      final lottery = Lottery()..lucky = {Address('Kyiv'), Address()};
      final violations = BeanValidator(introspector: introspector)
          .validateObject(lottery);
      expect(_paths(violations), ['lucky[].city']);
    });

    test('Spring keeps the field, the invalid value and the codes', () {
      final lottery = Lottery()..lucky = {Address()};
      final binder =
          DataBinder(lottery, objectName: 'lottery', introspector: introspector)
            ..validators.add(BeanValidator(introspector: introspector))
            ..validate();
      final error = binder.bindingResult.fieldError('lucky[].city')!;
      expect(error.rejectedValue, '');
      expect(
        error.codes,
        containsAllInOrder([
          'NotBlank.lottery.lucky[].city',
          'NotBlank.lottery.lucky.city',
          'NotBlank.lucky[].city',
          'NotBlank.lucky.city',
        ]),
      );
      expect(error.codes.last, 'NotBlank');
    });

    test('lists keep their index', () {
      final person = Person()..previous = [Address('Lviv'), Address()];
      final violations =
          BeanValidator(
            introspector: BeanIntrospector(
              introspections: [personIntrospection, addressIntrospection],
            ),
          ).validateObject(
            person
              ..name = 'Ada'
              ..age = 30,
          );
      expect(_paths(violations), ['previous[1].city']);
    });
  });

  group('container element constraints (@Each, @EachKey)', () {
    final introspector = BeanIntrospector(
      introspections: [_surveyIntrospection],
    );

    test('Hibernate Validator paths', () {
      final survey = Survey()
        ..answers = ['yes', ' ', '']
        ..scores = {'math': -1, 'history': 3, 'art': 2};
      final violations = BeanValidator(introspector: introspector)
          .validateObject(survey);
      expect(_paths(violations), [
        'answers[1].<list element>',
        'answers[2].<list element>',
        'scores[math].<map value>',
        'scores<K>[history].<map key>',
      ]);
      expect(violations.first.invalidValue, ' ');
      expect(violations.first.leafBean, same(survey));
      expect(violations[2].invalidValue, -1);
      expect(violations[3].invalidValue, 'history');
    });

    test('sets use [] and null elements are validated', () {
      expect(
        _paths(
          _validate(
            {'a', null},
            const [
              Each([NotNull()]),
            ],
          ),
        ),
        ['value[].<iterable element>'],
      );
    });

    test('Spring fields end at the element: answers[1]', () {
      final survey = Survey()
        ..answers = ['yes', '']
        ..scores = {'chemistry': 1};
      final binder =
          DataBinder(survey, objectName: 'survey', introspector: introspector)
            ..validators.add(BeanValidator(introspector: introspector))
            ..validate();
      final result = binder.bindingResult;
      expect(
        [for (final e in result.fieldErrors()) e.field],
        ['answers[1]', 'scores[chemistry]'],
      );
      expect(result.fieldError('answers[1]')!.rejectedValue, '');
      expect(result.fieldError('answers[1]')!.code, 'NotBlank');
    });

    test('element constraints have groups', () {
      const annotations = [
        Each([
          NotBlank(groups: [Expensive]),
        ]),
      ];
      expect(_validate([''], annotations), isEmpty);
      expect(_validate([''], annotations, groups: [Expensive]), hasLength(1));
    });

    test('on a value that is no container: ConstraintDeclarationException', () {
      expect(
        () => _validate('text', const [
          Each([NotBlank()]),
        ]),
        throwsA(isA<ConstraintDeclarationException>()),
      );
      expect(
        () => _validate(
          ['a'],
          const [
            EachKey([NotBlank()]),
          ],
        ),
        throwsA(isA<ConstraintDeclarationException>()),
      );
    });

    test('element constraint types are checked too', () {
      expect(
        () => _validate(
          [1],
          const [
            Each([NotBlank()]),
          ],
        ),
        throwsA(isA<UnexpectedTypeException>()),
      );
    });
  });

  group('@GroupSequence on a class redefines Default', () {
    BeanValidator validator(List<Type> sequence) => BeanValidator(
      introspector: BeanIntrospector(introspections: [_order(sequence)]),
    );

    test('later groups run only when the earlier ones pass', () {
      final v = validator([Order, Expensive]);
      expect(_paths(v.validateObject(Order())), ['sku']);
      expect(_paths(v.validateObject(Order()..sku = 'A-1')), ['warehouse']);
      expect(
        v.validateObject(
          Order()
            ..sku = 'A-1'
            ..warehouse = 'main',
        ),
        isEmpty,
      );
    });

    test('the order of the sequence counts', () {
      final v = validator([Expensive, Order]);
      expect(_paths(v.validateObject(Order())), ['warehouse']);
    });

    test('other requested groups are validated as usual', () {
      final v = validator([Order, Expensive]);
      expect(_paths(v.validateObject(Order(), groups: [Expensive])), [
        'warehouse',
      ]);
    });

    test('validateProperty runs the sequence on that property only', () {
      // Like Hibernate Validator: the blank sku is not part of it.
      final v = validator([Order, Expensive]);
      expect(_paths(v.validateProperty(Order(), 'warehouse')), ['warehouse']);
      expect(_paths(v.validateProperty(Order(), 'sku')), ['sku']);
    });

    test('Default in it or the class missing: GroupDefinitionException', () {
      expect(
        () => validator([Default, Expensive]).validateObject(Order()),
        throwsA(isA<GroupDefinitionException>()),
      );
      expect(
        () => validator([Expensive]).validateObject(Order()),
        throwsA(
          isA<GroupDefinitionException>().having(
            (e) => e.message,
            'message',
            'Order must be part of the redefined default group sequence.',
          ),
        ),
      );
    });
  });

  group('group sequences', () {
    final introspector = BeanIntrospector(
      introspections: [personIntrospection, addressIntrospection],
    );

    test('a sequence group stops at the first group with a violation', () {
      final validator = BeanValidator(
        introspector: introspector,
        groupSequences: {
          Complete: [Default, Strict],
        },
      );
      // Default fails (blank name): Strict (age <= 150) is not checked.
      final person = Person()..age = 200;
      expect(_paths(validator.validateObject(person, groups: [Complete])), [
        'name',
        'name',
      ]);
      person.name = 'Ada';
      expect(_paths(validator.validateObject(person, groups: [Complete])), [
        'age',
      ]);
    });

    test('nested sequences are expanded; cycles are rejected', () {
      final validator = BeanValidator(
        introspector: introspector,
        groupSequences: {
          Complete: [Cyclic],
          Cyclic: [Complete],
        },
      );
      expect(
        () => validator.validateObject(Person(), groups: [Complete]),
        throwsA(isA<GroupDefinitionException>()),
      );
    });
  });

  group('@ConvertGroup', () {
    BeanValidator validator(List<Object> annotations) => BeanValidator(
      introspector: BeanIntrospector(
        introspections: [_car(annotations), _driverIntrospection],
      ),
    );

    test('Default becomes DriverChecks in the cascaded driver', () {
      final car = Car();
      expect(
        _paths(
          validator(const [Valid(), ConvertGroup(to: DriverChecks)])
              .validateObject(car),
        ),
        ['driver.licensed'],
      );
      expect(_paths(validator(const [Valid()]).validateObject(car)), [
        'driver.name',
      ]);
    });

    test('only the from group is converted', () {
      expect(
        _paths(
          validator(const [
            Valid(),
            ConvertGroup(from: Expensive, to: DriverChecks),
          ]).validateObject(Car()),
        ),
        ['driver.name'],
      );
    });

    test('without @Valid, or converting a group twice, is a declaration '
        'error', () {
      expect(
        () =>
            validator(const [ConvertGroup(to: DriverChecks)])
                .validateObject(Car()),
        throwsA(isA<ConstraintDeclarationException>()),
      );
      expect(
        () => validator(const [
          Valid(),
          ConvertGroup(to: DriverChecks),
          ConvertGroup(to: Expensive),
        ]).validateObject(Car()),
        throwsA(isA<ConstraintDeclarationException>()),
      );
    });
  });

  group(r'${validatedValue} in messages', () {
    test('the expression is replaced by the invalid value', () {
      final violations = _validate('too long', const [
        Size(max: 3, message: r'"${validatedValue}" is longer than {max}'),
      ]);
      expect(violations.single.message, '"too long" is longer than 3');
      expect(
        violations.single.messageTemplate,
        r'"${validatedValue}" is longer than {max}',
      );
    });

    test(r'${attribute} works like {attribute}; unknown ones are kept', () {
      final violations = _validate(5, const [
        Max(3, message: r'${validatedValue} > ${value} ${unknown}'),
      ]);
      expect(violations.single.message, r'5 > 3 ${unknown}');
    });

    test('a null value is written as null', () {
      expect(
        _validate(null, const [
          NotNull(message: r'got ${validatedValue}'),
        ]).single.message,
        'got null',
      );
    });
  });
}
