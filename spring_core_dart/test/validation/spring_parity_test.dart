// Regression tests for validation, data binding and message behaviour
// that follows Spring / Jakarta Bean Validation (Hibernate Validator).
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

// ---- generated ----

class Line {
  String sku = '';
  int qty = 0;
}

class Cart {
  List<Line> lines = [];
  List<int> numbers = [];
  List<String> tags = [];
  Map<int, double> prices = {};
  Map<String, Line> byCode = {};
  Line? main;
}

final _lineIntrospection = BeanIntrospection<Line>(
  properties: [
    BeanProperty<Line>(
      'sku',
      type: String,
      typeInfo: const ClassType<String>(),
      get: (b) => b.sku,
      set: (b, v) => b.sku = v! as String,
      annotations: const [NotBlank()],
    ),
    BeanProperty<Line>(
      'qty',
      type: int,
      typeInfo: const ClassType<int>(),
      get: (b) => b.qty,
      set: (b, v) => b.qty = v! as int,
      annotations: const [Min(1)],
    ),
  ],
  instantiate: Line.new,
);

final _cartIntrospection = BeanIntrospection<Cart>(
  properties: [
    BeanProperty<Cart>(
      'lines',
      type: List<Line>,
      typeInfo: const ListType<Line>(ClassType<Line>()),
      get: (b) => b.lines,
      set: (b, v) => b.lines = v! as List<Line>,
      annotations: const [Valid()],
    ),
    BeanProperty<Cart>(
      'numbers',
      type: List<int>,
      typeInfo: const ListType<int>(ClassType<int>()),
      get: (b) => b.numbers,
      set: (b, v) => b.numbers = v! as List<int>,
    ),
    BeanProperty<Cart>(
      'tags',
      type: List<String>,
      typeInfo: const ListType<String>(ClassType<String>()),
      get: (b) => b.tags,
      set: (b, v) => b.tags = v! as List<String>,
    ),
    BeanProperty<Cart>(
      'prices',
      type: Map<int, double>,
      typeInfo: const MapType<int, double>(
        ClassType<int>(),
        ClassType<double>(),
      ),
      get: (b) => b.prices,
      set: (b, v) => b.prices = v! as Map<int, double>,
    ),
    BeanProperty<Cart>(
      'byCode',
      type: Map<String, Line>,
      typeInfo: const MapType<String, Line>(
        ClassType<String>(),
        ClassType<Line>(),
      ),
      get: (b) => b.byCode,
      set: (b, v) => b.byCode = v! as Map<String, Line>,
      annotations: const [Valid()],
    ),
    BeanProperty<Cart>(
      'main',
      type: Line,
      nullable: true,
      typeInfo: const ClassType<Line>(nullable: true),
      get: (b) => b.main,
      set: (b, v) => b.main = v as Line?,
      annotations: const [Valid()],
    ),
  ],
  instantiate: Cart.new,
);

class Author {
  const Author(this.name, {this.born});
  final String name;
  final int? born;
}

class Book {
  const Book({
    required this.isbn,
    required this.title,
    this.pages = 100,
    this.tags = const [],
    this.author,
    this.prices = const {},
  });
  final String isbn;
  final String title;
  final int pages;
  final List<String> tags;
  final Author? author;
  final Map<String, double> prices;
}

final _authorIntrospection = BeanIntrospection<Author>(
  properties: [
    BeanProperty<Author>('name', type: String, get: (b) => b.name),
    BeanProperty<Author>('born', type: int, nullable: true, get: (b) => b.born),
  ],
  constructor: BeanConstructor<Author>(
    parameters: const [
      BeanParameter('name', type: ClassType<String>(), isRequired: true),
      BeanParameter(
        'born',
        type: ClassType<int>(nullable: true),
        symbol: #born,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Author.new, positional, named) as Author,
  ),
);

final _bookIntrospection = BeanIntrospection<Book>(
  properties: [
    BeanProperty<Book>(
      'isbn',
      type: String,
      get: (b) => b.isbn,
      annotations: const [NotBlank()],
    ),
    BeanProperty<Book>('title', type: String, get: (b) => b.title),
    BeanProperty<Book>('pages', type: int, get: (b) => b.pages),
  ],
  constructor: BeanConstructor<Book>(
    parameters: const [
      BeanParameter(
        'isbn',
        type: ClassType<String>(),
        symbol: #isbn,
        isRequired: true,
      ),
      BeanParameter(
        'title',
        type: ClassType<String>(),
        symbol: #title,
        isRequired: true,
      ),
      BeanParameter('pages', type: ClassType<int>(), symbol: #pages),
      BeanParameter(
        'tags',
        type: ListType<String>(ClassType<String>()),
        symbol: #tags,
      ),
      BeanParameter(
        'author',
        type: ClassType<Author>(nullable: true),
        symbol: #author,
      ),
      BeanParameter(
        'prices',
        type: MapType<String, double>(ClassType<String>(), ClassType<double>()),
        symbol: #prices,
      ),
    ],
    create: (positional, named) =>
        Function.apply(Book.new, positional, named) as Book,
  ),
);

/// Class-level constraint reporting on the `confirm` property.
class PasswordsMatch extends Constraint {
  const PasswordsMatch({super.message});

  @override
  String get name => 'PasswordsMatch';

  @override
  String get defaultMessage => 'passwords must match';

  @override
  bool isValid(Object? value) =>
      value is! Signup || value.password == value.confirm;

  @override
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) {
    if (isValid(value)) {
      return true;
    }
    context
      ..disableDefaultConstraintViolation()
      ..buildConstraintViolationWithTemplate(
        context.defaultConstraintMessageTemplate,
      ).addPropertyNode('confirm').addConstraintViolation();
    return false;
  }
}

class Signup {
  String password = '';
  String confirm = '';
  String? nick;
  DateTime? birthday;
  DateTime? start;
}

final _signupIntrospection = BeanIntrospection<Signup>(
  annotations: const [PasswordsMatch()],
  properties: [
    BeanProperty<Signup>(
      'password',
      type: String,
      get: (b) => b.password,
      set: (b, v) => b.password = v! as String,
    ),
    BeanProperty<Signup>(
      'confirm',
      type: String,
      get: (b) => b.confirm,
      set: (b, v) => b.confirm = v! as String,
    ),
    BeanProperty<Signup>(
      'nick',
      type: String,
      nullable: true,
      get: (b) => b.nick,
      set: (b, v) => b.nick = v as String?,
      annotations: const [Size(min: 3, message: '{nick.size}')],
    ),
    BeanProperty<Signup>(
      'birthday',
      type: DateTime,
      nullable: true,
      get: (b) => b.birthday,
      set: (b, v) => b.birthday = v as DateTime?,
      annotations: const [Past()],
    ),
    BeanProperty<Signup>(
      'start',
      type: DateTime,
      nullable: true,
      get: (b) => b.start,
      set: (b, v) => b.start = v as DateTime?,
      annotations: const [FutureOrPresent()],
    ),
  ],
  instantiate: Signup.new,
);

class Employee extends Person {
  String badge = '';
}

class Manager extends Employee {}

final _employeeIntrospection = BeanIntrospection<Employee>(
  properties: [
    BeanProperty<Employee>(
      'badge',
      type: String,
      get: (b) => b.badge,
      set: (b, v) => b.badge = v! as String,
      annotations: const [NotBlank()],
    ),
  ],
  instantiate: Employee.new,
);

// ---- end generated ----

final class _FixedClock implements ClockProvider {
  const _FixedClock(this.time);
  final DateTime time;
  @override
  DateTime now() => time;
}

BeanIntrospector _introspector() => BeanIntrospector(
  introspections: [
    personIntrospection,
    addressIntrospection,
    _lineIntrospection,
    _cartIntrospection,
    _authorIntrospection,
    _bookIntrospection,
    _signupIntrospection,
    _employeeIntrospection,
  ],
);

void main() {
  group('binding and validation', () {
    test('no constraint error on top of a binding failure', () {
      final line = Line();
      final binder =
          DataBinder(line, objectName: 'line', introspector: _introspector())
            ..validators.add(BeanValidator(introspector: _introspector()))
            ..bind({'qty': 'many', 'sku': ''})
            ..validate();
      final errors = binder.bindingResult;
      expect(errors.fieldErrors('qty').map((e) => e.code), ['typeMismatch']);
      expect(errors.fieldErrors('sku').map((e) => e.code), ['NotBlank']);
    });

    test('typeMismatch and required carry Spring arguments', () {
      final binder =
          DataBinder(
              Person(),
              objectName: 'person',
              introspector: _introspector(),
            )
            ..requiredFields = ['name']
            ..bind({'age': 'x', 'name': '  '});
      final mismatch = binder.bindingResult.fieldError('age')!;
      final field = mismatch.arguments.single! as MessageSourceResolvable;
      expect(field.codes, ['person.age', 'age']);
      final messages = StaticMessageSource()
        ..addMessage('typeMismatch', '', '{0} must be a number')
        ..addMessage('required', '', '{0} is required');
      expect(
        messages.getMessageFromResolvable(mismatch),
        'age must be a number',
      );
      final required = binder.bindingResult.fieldError('name')!;
      expect(required.rejectedValue, '');
      expect(messages.getMessageFromResolvable(required), 'name is required');
    });

    test('getFieldValue returns the rejected value of a validation error', () {
      final line = Line()..qty = 0;
      final errors = BeanPropertyBindingResult(
        line,
        'line',
        introspector: _introspector(),
      );
      BeanValidator(introspector: _introspector()).validate(line, errors);
      line.qty = 5; // changed after validation
      expect(errors.fieldError('qty')!.rejectedValue, 0);
      expect(errors.getFieldValue('qty'), 0);
      expect(errors.getRawFieldValue('qty'), 5);
    });
  });

  group('DefaultMessageCodesResolver and arguments', () {
    test('the last path segment is a code; keys are removed one by one', () {
      const resolver = DefaultMessageCodesResolver();
      expect(
        resolver.resolveFieldMessageCodes(
          'NotBlank',
          'person',
          'address.city',
          String,
        ),
        [
          'NotBlank.person.address.city',
          'NotBlank.address.city',
          'NotBlank.city',
          'NotBlank.String',
          'NotBlank',
        ],
      );
      expect(resolver.resolveFieldMessageCodes('c', 'o', 'a[0][1].b', null), [
        'c.o.a[0][1].b',
        'c.o.a[0].b',
        'c.o.a.b',
        'c.a[0][1].b',
        'c.a[0].b',
        'c.a.b',
        'c.b',
        'c',
      ]);
      expect(resolver.resolveFieldMessageCodes('c', 'o', 'x.items[2]', null), [
        'c.o.x.items[2]',
        'c.o.x.items',
        'c.x.items[2]',
        'c.x.items',
        'c.items[2]',
        'c.items',
        'c',
      ]);
    });

    test('a nested violation resolves NotBlank.city from a MessageSource', () {
      final person = Person()
        ..name = 'Ada'
        ..age = 30
        ..address = Address();
      final errors = BeanPropertyBindingResult(
        person,
        'person',
        introspector: _introspector(),
      );
      BeanValidator(introspector: _introspector()).validate(person, errors);
      final messages = StaticMessageSource()
        ..addMessage('NotBlank.city', '', 'Enter a city');
      expect(
        messages.getMessageFromResolvable(errors.fieldError('address.city')!),
        'Enter a city',
      );
    });

    test('Pattern and Email arguments are [field, flags, regexp]', () {
      const pattern = Matches(r'\d{5}', flags: [PatternFlag.multiline]);
      expect(pattern.attributes.keys, ['flags', 'regexp']);
      final address = Address('Oslo')..zip = 'x';
      final errors = BeanPropertyBindingResult(
        address,
        'address',
        introspector: _introspector(),
      );
      BeanValidator(introspector: _introspector()).validate(address, errors);
      final args = errors.fieldError('zip')!.arguments;
      expect(args[1], const <PatternFlag>[]);
      expect(args[2], const ResolvableAttribute(r'\d{5}'));
      final messages = StaticMessageSource()
        ..addMessage('Pattern', '', '{0} must match {2}');
      expect(
        messages.getMessageFromResolvable(errors.fieldError('zip')!),
        r'zip must match \d{5}',
      );
      expect(const Email().attributes, {
        'flags': const <PatternFlag>[],
        'regexp': '.*',
      });
    });
  });

  group('constraints like Hibernate Validator', () {
    test('BigInt and numeric strings in numeric constraints', () {
      final huge = BigInt.parse('123456789012345678901234567890');
      final cases = <(Constraint, Object?, bool)>[
        (const Min(5), BigInt.from(4), false),
        (const Min(5), huge, true),
        (const Max(5), huge, false),
        (const Min(5), '5', true),
        (const Min(5), '4.9999', false),
        (const Min(5), 'abc', false),
        (const Max(10), '1e1', true),
        (const Max(10), '10.0001', false),
        (const Positive(), '0.0001', true),
        (const Positive(), BigInt.zero, false),
        (const PositiveOrZero(), '-0', true),
        (const Negative(), BigInt.from(-1), true),
        (const NegativeOrZero(), '1', false),
        (const Min(1), double.nan, false),
        (const Max(1), double.nan, false),
        (const Min(1), double.infinity, true),
        (const Max(1), double.negativeInfinity, true),
        // Beyond 2^53 (parsed: the literal is not exact in JavaScript).
        (Max(int.parse('9007199254740993')), 9007199254740992, true),
        (const Min(1), true, true),
      ];
      for (final (constraint, value, valid) in cases) {
        expect(constraint.isValid(value), valid, reason: '$constraint $value');
      }
    });

    test('DecimalMin and DecimalMax', () {
      const min = DecimalMin('0.01');
      const exclusiveMax = DecimalMax('100', inclusive: false);
      expect(min.isValid(0.01), isTrue);
      expect(min.isValid('0.009'), isFalse);
      expect(min.isValid(null), isTrue);
      expect(exclusiveMax.isValid(100), isFalse);
      expect(exclusiveMax.isValid('99.999'), isTrue);
      expect(exclusiveMax.isValid(BigInt.from(101)), isFalse);
      expect(min.name, 'DecimalMin');
      expect(min.attributes, {'inclusive': true, 'value': '0.01'});
      expect(
        min.interpolatedMessage(),
        'must be greater than or equal to 0.01',
      );
      expect(exclusiveMax.interpolatedMessage(), 'must be less than 100');
    });

    test('Digits counts like BigDecimal', () {
      const digits = Digits(integer: 3, fraction: 1);
      final cases = <(Object?, bool)>[
        (1.50, true), // a number: trailing zeros are not significant
        ('1.50', false), // a string: as written
        ('007.5', true), // leading zeros are not digits (BigDecimal 7.5)
        ('1234', false),
        (1000, false),
        (999.9, true),
        (BigInt.from(999), true),
        (0.05, false),
        (1e21, false),
        ('abc', false),
        (double.nan, false),
        (null, true),
      ];
      for (final (value, valid) in cases) {
        expect(digits.isValid(value), valid, reason: '$value');
      }
    });

    test("Email accepts and rejects what Hibernate's does", () {
      const email = Email();
      for (final valid in [
        'user@localhost',
        'first.last@sub.example.com',
        '"john doe"@example.com',
        'user@[192.168.0.1]',
        'user@[IPv6:2001:db8::1]',
        'üser@exämple.de',
        'a_b@my_host.org',
        'x@a--b.com',
      ]) {
        expect(email.isValid(valid), isTrue, reason: valid);
      }
      for (final invalid in [
        'plain',
        'a..b@x.com',
        '.a@x.com',
        'a@x.com.',
        'a@-x.com',
        'a@x-.com',
        'a@',
        '${'a' * 65}@x.com',
        'a@${'b' * 64}.com',
        'a b@x.com',
      ]) {
        expect(email.isValid(invalid), isFalse, reason: invalid);
      }
      const company = Email(regexp: r'.+@example\.com');
      expect(company.isValid('a@example.com'), isTrue);
      expect(company.isValid('a@other.com'), isFalse);
      const caseInsensitive = Email(
        regexp: r'.+@example\.com',
        flags: [PatternFlag.caseInsensitive],
      );
      expect(caseInsensitive.isValid('a@EXAMPLE.com'), isTrue);
    });

    test('NotBlank trims like Java (characters up to U+0020)', () {
      expect(const NotBlank().isValid(' '), isTrue);
      expect(const NotBlank().isValid(' '), isTrue);
      expect(const NotBlank().isValid(' \t\n\u0001'), isFalse);
    });

    test('Matches flags and whole-input matching', () {
      expect(
        const Matches('a.b', flags: [PatternFlag.dotall]).isValid('a\nb'),
        isTrue,
      );
      expect(const Matches('a.b').isValid('a\nb'), isFalse);
      expect(
        const Matches('b', flags: [PatternFlag.multiline]).isValid('a\nb'),
        isFalse,
        reason: 'the whole value must match, also in multiline mode',
      );
      expect(const Matches('a|ab').isValid('ab'), isTrue);
    });
  });

  group('date constraints', () {
    final noon = DateTime(2026, 5, 10, 12);

    bool valid(Constraint constraint, Object? value) =>
        constraint.isValidWithContext(
          value,
          ConstraintValidatorContext(
            defaultConstraintMessageTemplate: '',
            clockProvider: _FixedClock(noon),
          ),
        );

    test('dates without a time of day are compared by day', () {
      final today = DateTime(2026, 5, 10);
      final yesterday = DateTime(2026, 5, 9);
      final tomorrow = DateTime(2026, 5, 11);
      expect(valid(const Past(), today), isFalse);
      expect(valid(const Past(), yesterday), isTrue);
      expect(valid(const PastOrPresent(), today), isTrue);
      expect(valid(const FutureDate(), today), isFalse);
      expect(valid(const FutureDate(), tomorrow), isTrue);
      expect(valid(const FutureOrPresent(), today), isTrue);
      expect(valid(const FutureOrPresent(), yesterday), isFalse);
      expect(valid(const FutureOrPresent(), DateTime.utc(2026, 5, 10)), isTrue);
    });

    test('date-times are compared as instants with the injected clock', () {
      expect(valid(const Past(), noon), isFalse);
      expect(valid(const PastOrPresent(), noon), isTrue);
      expect(valid(const FutureOrPresent(), noon), isTrue);
      expect(
        valid(const FutureDate(), noon.add(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        valid(
          const FutureOrPresent(),
          noon.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });

    test('BeanValidator passes its clock provider', () {
      final validator = BeanValidator(
        introspector: _introspector(),
        clockProvider: _FixedClock(DateTime(2000)),
      );
      final signup = Signup()
        ..birthday = DateTime(2001)
        ..start = DateTime(1999, 12, 31);
      expect(
        validator.validateObject(signup).map((v) => v.propertyPath),
        unorderedEquals(['birthday', 'start']),
      );
    });
  });

  group('BeanValidator', () {
    test('class-level violations reported on a property', () {
      final signup = Signup()
        ..password = 'a'
        ..confirm = 'b';
      final validator = BeanValidator(introspector: _introspector());
      final violation = validator.validateObject(signup).single;
      expect(violation.propertyPath, 'confirm');
      expect(violation.message, 'passwords must match');
      final errors = BeanPropertyBindingResult(
        signup,
        'signup',
        introspector: _introspector(),
      );
      validator.validate(signup, errors);
      final error = errors.fieldError('confirm')!;
      expect(error.codes.first, 'PasswordsMatch.signup.confirm');
      expect(error.rejectedValue, 'b', reason: "the property's value");
      expect(errors.hasGlobalErrors, isFalse);
    });

    test('{key} messages come from the validation message source', () {
      final messages = StaticMessageSource()
        ..addMessage('nick.size', '', 'at least {min} letters ({app.name})')
        ..addMessage('app.name', '', 'Shop')
        ..addMessage(
          'jakarta.validation.constraints.NotBlank.message',
          '',
          'please fill in',
        );
      final validator = BeanValidator(
        introspector: _introspector(),
        validationMessageSource: messages,
      );
      final nick = validator.validateObject(Signup()..nick = 'ab').single;
      expect(nick.message, 'at least 3 letters (Shop)');
      expect(nick.messageTemplate, '{nick.size}');
      final blank = validator.validateObject(Line()..qty = 1).single;
      expect(blank.message, 'please fill in');
      expect(
        BeanValidator(introspector: _introspector())
            .validateObject(Signup()..nick = 'ab')
            .single
            .message,
        '{nick.size}',
        reason: 'no message source: the key stays',
      );
    });

    test('@Valid validates a shared object on every path', () {
      final shared = Line();
      final cart = Cart()
        ..lines = [
          shared,
          Line()
            ..sku = 'ok'
            ..qty = 1,
          shared,
        ]
        ..main = shared;
      final paths = BeanValidator(introspector: _introspector())
          .validateObject(cart)
          .map((v) => v.propertyPath);
      expect(
        paths,
        unorderedEquals([
          'lines[0].sku',
          'lines[0].qty',
          'lines[2].sku',
          'lines[2].qty',
          'main.sku',
          'main.qty',
        ]),
      );
    });

    test('the most specific introspection of a subclass is used', () {
      // Person is registered before Employee; a Manager (not
      // introspected) is validated with Employee's metadata.
      final manager = Manager()
        ..name = 'Ada'
        ..age = 40;
      final violations = BeanValidator(introspector: _introspector())
          .validateObject(manager);
      expect(violations.map((v) => v.propertyPath), ['badge']);
      expect(_introspector().findIntrospection(manager)!.beanType, Employee);
    });
  });

  group('BeanWrapper with generated TypeInfo', () {
    test('auto-grows lists and maps, converts elements and keys', () {
      final cart = Cart();
      BeanWrapper(
          cart,
          introspector: _introspector(),
          autoGrowNestedPaths: true,
        )
        ..setPropertyValue('lines[2].sku', 'c')
        ..setPropertyValue('lines[0].qty', '3')
        ..setPropertyValue('numbers[0]', '7')
        ..setPropertyValue('prices[42]', '9.5')
        ..setPropertyValue('byCode[x].sku', 'x1')
        ..setPropertyValue('main.sku', 'm');
      expect(cart.lines.map((l) => l.sku), ['', '', 'c']);
      expect(cart.lines.first.qty, 3);
      expect(cart.numbers, [7]);
      expect(cart.prices, {42: 9.5});
      expect(cart.byCode['x']!.sku, 'x1');
      expect(cart.main!.sku, 'm');
      final wrapper = BeanWrapper(cart, introspector: _introspector());
      expect(wrapper.getPropertyValue('prices[42]'), 9.5);
      expect(wrapper.getPropertyType('prices[42]'), double);
      expect(wrapper.getPropertyType('lines[0]'), Line);
    });

    test("a gap in a List<String> is padded with empty strings (Spring's "
        'new String()); other non-nullable elements fail', () {
      const gap =
          "Invalid property 'numbers[2]' of Cart: Cannot set element with "
          'index 2 in List of size 0, accessed using property path '
          "'numbers[2]': List does not support filling up gaps with null "
          'elements';
      final cart = Cart();
      final growing = BeanWrapper(
        cart,
        introspector: _introspector(),
        autoGrowNestedPaths: true,
      )..setPropertyValue('tags[2]', 'z');
      expect(cart.tags, ['', '', 'z']);
      expect(
        () => growing.setPropertyValue('numbers[2]', '7'),
        throwsA(
          isA<NotWritablePropertyException>().having(
            (e) => e.message,
            'message',
            gap,
          ),
        ),
      );
      expect(cart.numbers, isEmpty);
      // Without auto-grow a list that cannot hold null is not padded.
      expect(
        () => BeanWrapper(
          Cart(),
          introspector: _introspector(),
        ).setPropertyValue('tags[1]', 'z'),
        throwsA(isA<NotWritablePropertyException>()),
      );
    });

    test('DataBinder pads a List<String> and never rejects the bound value '
        'for a gap', () {
      final cart = Cart();
      final binder = DataBinder(
        cart,
        objectName: 'cart',
        introspector: _introspector(),
      )..bind({'tags[2]': 'z'});
      expect(binder.bindingResult.hasErrors, isFalse);
      expect(cart.tags, ['', '', 'z']);
      // `List<int>` cannot be padded: the write fails like Spring's
      // InvalidPropertyException, not as a type mismatch of `7`.
      binder.bind({'numbers[2]': '7'});
      expect(binder.bindingResult.hasErrors, isFalse);
      expect(cart.numbers, isEmpty);
      expect(
        () => (DataBinder(
          Cart(),
          objectName: 'cart',
          introspector: _introspector(),
        )..ignoreUnknownFields = false).bind({'numbers[2]': '7'}),
        throwsA(isA<NotWritablePropertyException>()),
      );
    });

    test('conversion failures of elements and keys are type mismatches', () {
      final wrapper = BeanWrapper(
        Cart(),
        introspector: _introspector(),
        autoGrowNestedPaths: true,
      );
      expect(
        () => wrapper.setPropertyValue('numbers[0]', 'x'),
        throwsA(isA<TypeMismatchException>()),
      );
      expect(
        () => wrapper.setPropertyValue('prices[k]', '1'),
        throwsA(isA<TypeMismatchException>()),
      );
    });

    test('the auto-grow limit and reads that never grow', () {
      final cart = Cart();
      final binder = DataBinder(
        cart,
        objectName: 'cart',
        introspector: _introspector(),
      )..autoGrowCollectionLimit = 2;
      expect(
        () => binder.bind({'lines[5].sku': 'x'}),
        throwsA(isA<NotReadablePropertyException>()),
      );
      binder.bind({'lines[1].sku': 'b'});
      expect(cart.lines, hasLength(2));
      final wrapper = BeanWrapper(
        cart,
        introspector: _introspector(),
        autoGrowNestedPaths: true,
      );
      expect(
        () => wrapper.getPropertyValue('lines[3].sku'),
        throwsA(isA<NotReadablePropertyException>()),
      );
      expect(cart.lines, hasLength(2));
    });
  });

  group('DataBinder.construct', () {
    DataBinder binder() =>
        DataBinder(null, objectName: 'book', introspector: _introspector())
          ..targetType = Book;

    test('creates an immutable target with nested values', () {
      final dataBinder = binder()
        ..construct(
          const MapValueResolver({
            'isbn': '978-0',
            'title': 'Dune',
            'pages': '412',
            'tags[0]': 'sf',
            'tags[1]': 'classic',
            'author.name': 'Herbert',
            'author.born': '1920',
            'prices[eur]': '9.99',
          }),
        );
      final book = dataBinder.target! as Book;
      expect(book.isbn, '978-0');
      expect(book.pages, 412);
      expect(book.tags, ['sf', 'classic']);
      expect(book.author!.name, 'Herbert');
      expect(book.author!.born, 1920);
      expect(book.prices, {'eur': 9.99});
      expect(dataBinder.bindingResult.hasErrors, isFalse);
      expect(dataBinder.bindingResult.target, same(book));
      // Validation and binding work on the created target.
      dataBinder
        ..validators.add(BeanValidator(introspector: _introspector()))
        ..validate();
      expect(dataBinder.bindingResult.hasErrors, isFalse);
    });

    test('list elements keep their index; a gap Dart cannot fill with null '
        'is reported', () {
      final dataBinder = binder()
        ..construct(
          const MapValueResolver({
            'isbn': '1',
            'title': 'T',
            'tags[1]': 'classic',
          }),
        );
      // Spring gives [null, classic]; a List<String> cannot hold null.
      expect(
        dataBinder.bindingResult.fieldError('tags[0]')?.code,
        'typeMismatch',
      );
      expect((dataBinder.target! as Book).tags, ['classic']);
    });

    test("list indexes stop at autoGrowCollectionLimit, like Spring's "
        'createList', () {
      // A hostile index fails before the list is allocated.
      final stopwatch = Stopwatch()..start();
      expect(
        () => binder().construct(
          const MapValueResolver({
            'isbn': '1',
            'title': 'T',
            'tags[0]': 'sf',
            'tags[50000000]': 'x',
          }),
        ),
        throwsA(
          isA<InvalidPropertyException>().having(
            (error) => error.propertyName,
            'propertyName',
            'tags[50000000]',
          ),
        ),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      final limited = binder()..autoGrowCollectionLimit = 3;
      expect(
        () => limited.construct(
          const MapValueResolver({'isbn': '1', 'title': 'T', 'tags[3]': 'x'}),
        ),
        throwsA(isA<InvalidPropertyException>()),
      );
      // Indexes below the limit still work.
      final dataBinder = binder()
        ..autoGrowCollectionLimit = 3
        ..construct(
          const MapValueResolver({
            'isbn': '1',
            'title': 'T',
            'tags[0]': 'a',
            'tags[1]': 'b',
            'tags[2]': 'c',
          }),
        );
      expect(dataBinder.bindingResult.hasErrors, isFalse);
      expect((dataBinder.target! as Book).tags, ['a', 'b', 'c']);
    });

    test('optional parameters keep their defaults', () {
      final book =
          (binder()..construct(
                    const MapValueResolver({'isbn': '1', 'title': 'T'}),
                  ))
                  .target!
              as Book;
      expect(book.pages, 100);
      expect(book.tags, isEmpty);
      expect(book.author, isNull);
    });

    test('conversion failures and missing values are binding errors', () {
      final dataBinder = binder()
        ..construct(const MapValueResolver({'isbn': '1', 'pages': 'many'}));
      expect(dataBinder.target, isNull);
      final errors = dataBinder.bindingResult;
      expect(errors.fieldError('pages')!.code, 'typeMismatch');
      expect(errors.fieldError('pages')!.rejectedValue, 'many');
      expect(errors.getFieldValue('pages'), 'many');
      expect(errors.fieldError('title')!.code, 'typeMismatch');
      expect(errors.getFieldValue('isbn'), '1');
      expect(() => dataBinder.close(), throwsA(isA<BindException>()));
    });

    test('state checks', () {
      expect(
        () => DataBinder(
          null,
          introspector: _introspector(),
        ).construct(const MapValueResolver({})),
        throwsStateError,
      );
      expect(
        () => DataBinder(Line()).construct(const MapValueResolver({})),
        throwsStateError,
      );
      expect(() => DataBinder(null).bind({'a': 1}), throwsStateError);
    });
  });

  group('method validation', () {
    final validator = BeanValidator(introspector: _introspector());
    const signature = MethodSignature(
      name: 'register',
      declaringType: 'Registration',
      targetType: 'Registration',
      parameterNames: ['email', 'line'],
      parameterAnnotations: [
        [NotBlank(), Email()],
        [Valid()],
      ],
      annotations: [Size(max: 5)],
      targetAnnotations: [Validated()],
    );
    const groupSignature = MethodSignature(
      name: 'update',
      declaringType: 'Registration',
      targetType: 'Registration',
      parameterNames: ['age'],
      parameterAnnotations: [
        [
          Min(18),
          Max(150, groups: [Strict]),
        ],
      ],
      annotations: [
        Validated([Strict]),
      ],
      targetAnnotations: [Validated()],
    );
    const unvalidated = MethodSignature(
      name: 'other',
      declaringType: 'Plain',
      targetType: 'Plain',
      parameterNames: ['email'],
      parameterAnnotations: [
        [NotBlank()],
      ],
    );
    final advisor = MethodValidationPostProcessor(validator);
    final target = Object();

    Object? call(
      MethodSignature signature,
      List<Object?> args,
      Object? result,
    ) => ProxyInvoker(
      [signature],
      [advisor],
      'registration',
    ).invoke(target, target, 0, args, (_) => result);

    test('only @Validated classes are advised', () {
      expect(advisor.pointcut.matches(signature, 'x'), isTrue);
      expect(advisor.pointcut.matches(unvalidated, 'x'), isFalse);
    });

    test('exclude filters skip classes by their annotations', () {
      final excluding = MethodValidationPostProcessor(null, [
        (annotations) => annotations.any((a) => a is Validated),
      ]);
      expect(excluding.pointcut.matches(signature, 'x'), isFalse);
    });

    test('parameter constraints and @Valid parameters', () {
      expect(call(signature, ['a@b.c', null], 'ok'), 'ok');
      expect(
        () => call(signature, ['', Line()], 'ok'),
        throwsA(
          isA<ConstraintViolationException>().having(
            (e) => e.constraintViolations.map((v) => v.propertyPath),
            'paths',
            unorderedEquals([
              'register.email',
              'register.line.sku',
              'register.line.qty',
            ]),
          ),
        ),
      );
    });

    test('return value constraints', () {
      expect(
        () => call(signature, ['a@b.c', null], 'too long'),
        throwsA(
          isA<ConstraintViolationException>()
              .having(
                (e) => e.constraintViolations.single.propertyPath,
                'path',
                'register.<return value>',
              )
              .having(
                (e) => e.message,
                'message',
                'register.<return value>: size must be between 0 and 5',
              ),
        ),
      );
    });

    test('groups of @Validated on the method', () {
      expect(
        call(groupSignature, [10], null),
        isNull,
        reason: 'Min is Default',
      );
      expect(
        () => call(groupSignature, [200], null),
        throwsA(isA<ConstraintViolationException>()),
      );
    });

    test('Future methods complete with the violation', () async {
      final invoker = ProxyInvoker([signature], [advisor], 'registration');
      await expectLater(
        invoker.invokeAsync<String>(target, target, 0, [
          '',
          null,
        ], (_) async => 'ok'),
        throwsA(isA<ConstraintViolationException>()),
      );
      await expectLater(
        invoker.invokeAsync<String>(target, target, 0, [
          'a@b.c',
          null,
        ], (_) async => 'too long'),
        throwsA(isA<ConstraintViolationException>()),
      );
      expect(
        await invoker.invokeAsync<String>(target, target, 0, [
          'a@b.c',
          null,
        ], (_) async => 'ok'),
        'ok',
      );
    });
  });

  group('messages', () {
    test('a parent message gets the arguments the child resolved', () {
      final parent = StaticMessageSource()
        ..addMessage('welcome', '', 'Welcome to {0}');
      final child = StaticMessageSource()
        ..addMessage('shop.name', '', 'Neon Shop')
        ..parentMessageSource = parent;
      expect(
        child.getMessage(
          'welcome',
          args: [DefaultMessageSourceResolvable.code('shop.name')],
        ),
        'Welcome to Neon Shop',
      );
    });

    test('locales with a script', () {
      expect(Locales.normalize('zh-Hant-TW'), 'zh_Hant_TW');
      expect(Locales.normalize('zh_TW_#Hant'), 'zh_Hant_TW');
      expect(Locales.candidates('zh_Hant_TW'), [
        'zh_Hant_TW',
        'zh_Hant',
        'zh_TW',
        'zh',
      ]);
      expect(Locales.candidates('en_US_POSIX'), ['en_US_POSIX', 'en_US', 'en']);
      final source = StaticMessageSource()
        ..addMessage('hi', 'zh_Hant', '你好 (Hant)')
        ..addMessage('hi', 'zh', '你好');
      expect(source.getMessage('hi', locale: 'zh-Hant-TW'), '你好 (Hant)');
      expect(source.getMessage('hi', locale: 'zh_CN'), '你好');
    });

    test('bundles are searched basename by basename', () {
      ClasspathResources.registerAll(const {
        'parity/messages.properties': EmbeddedResource.text('title=Shop'),
        'parity/errors_de.properties': EmbeddedResource.text(
          'title=Fehler\nonly.errors=Nur',
        ),
      });
      final source = ReloadableResourceBundleMessageSource(
        basenames: ['classpath:parity/messages', 'classpath:parity/errors'],
      );
      expect(source.getMessage('title', locale: 'de'), 'Shop');
      expect(source.getMessage('only.errors', locale: 'de'), 'Nur');
    });

    test('messages use the number symbols of the locale', () {
      final source = StaticMessageSource()
        ..addMessage('total', '', 'Total: {0,number,#,##0.00}');
      expect(source.getMessage('total', args: [1234.5]), 'Total: 1,234.50');
      expect(
        source.getMessage('total', args: [1234.5], locale: 'de'),
        'Total: 1.234,50',
      );
    });
  });

  group('MessageFormat details', () {
    String f(String pattern, List<Object?> args, [String? locale]) =>
        MessageFormat.format(pattern, args, locale: locale);

    test('a lone } is literal', () {
      expect(f('a } b {0}', ['x']), 'a } b x');
    });

    test('negative subpatterns and quoted literals', () {
      const accounting = '{0,number,#,##0.00;(#,##0.00)}';
      expect(f(accounting, [-1234.5]), '(1,234.50)');
      expect(f(accounting, [1234.5]), '1,234.50');
      expect(f("{0,number,'#'0}", [7]), '#7');
      expect(f("{0,number,0' units'}", [3]), '3 units');
      expect(f("{0,number,0 o''clock}", [5]), "5 o'clock");
      expect(f('{0,number,0.0;minus 0.0}', [-2.25]), 'minus 2.2');
      expect(f('{0,number,#,##0}', [-1234]), '-1,234');
    });

    test('half-even rounding on the exact binary value', () {
      expect(f('{0,number,0.0}', [0.15]), '0.1');
      expect(f('{0,number,0.0}', [0.25]), '0.2');
      expect(f('{0,number,0.00}', [2.675]), '2.67');
      expect(f('{0,number,0}', [2.5]), '2');
      expect(f('{0,number,0}', [3.5]), '4');
    });

    test('locale symbols', () {
      expect(f('{0}', [1234567.891], 'de_DE'), '1.234.567,891');
      expect(f('{0}', [1234.5], 'fr'), '1 234,5');
      expect(f('{0}', [1234.5], 'ru'), '1 234,5');
      expect(f('{0}', [1234.5], 'de_CH'), '1’234.5');
      expect(f('{0}', [1234.5], 'en_US'), '1,234.5');
      expect(f('{0}', [1234.5], 'xx'), '1,234.5');
    });
  });
}
