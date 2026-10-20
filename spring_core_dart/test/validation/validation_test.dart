import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  group('constraints', () {
    test('null handling and checks', () {
      final now = DateTime.now();
      final cases = <(Constraint, Object?, bool)>[
        (const NotNull(), null, false),
        (const NotNull(), 1, true),
        (const MustBeNull(), null, true),
        (const MustBeNull(), 1, false),
        (const NotEmpty(), '', false),
        (const NotEmpty(), [1], true),
        (const NotEmpty(), <int, int>{}, false),
        (const NotEmpty(), 5, true),
        (const NotEmpty(), null, false),
        (const NotBlank(), '  ', false),
        (const NotBlank(), null, false),
        (const NotBlank(), 'x', true),
        (const Size(min: 1, max: 2), 'abc', false),
        (const Size(min: 1, max: 2), [1], true),
        (const Size(min: 1), null, true),
        (const Size(max: 1), 42, true),
        (const Min(5), 4, false),
        (const Min(5), 5.5, true),
        (const Min(5), null, true),
        (const Max(5), 6, false),
        (const Positive(), 0, false),
        (const Positive(), 1, true),
        (const PositiveOrZero(), 0, true),
        (const PositiveOrZero(), -1, false),
        (const Negative(), -1, true),
        (const Negative(), 0, false),
        (const NegativeOrZero(), 0, true),
        (const NegativeOrZero(), 1, false),
        (const Matches(r'[a-z]+'), 'abc', true),
        (const Matches(r'[a-z]+'), 'abc1', false),
        (const Matches(r'[a-z]+', caseSensitive: false), 'ABC', true),
        (const Matches('x'), null, true),
        (const Email(), 'a.b+c@example.co', true),
        (const Email(), '', true),
        (const Email(), null, true),
        (const Email(), 'nope', false),
        (const Email(), 'a..b@x.com', false),
        (const Email(), '.a@x.com', false),
        (const Digits(integer: 3, fraction: 2), 123.45, true),
        (const Digits(integer: 3, fraction: 2), 1234, false),
        (const Digits(integer: 3, fraction: 2), '1.234', false),
        (const Digits(integer: 3, fraction: 2), -12.5, true),
        (const Digits(integer: 1, fraction: 0), null, true),
        (const AssertTrue(), true, true),
        (const AssertTrue(), false, false),
        (const AssertFalse(), false, true),
        (const AssertFalse(), true, false),
        (const PastDate(), now.subtract(const Duration(days: 1)), true),
        (const PastDate(), now.add(const Duration(days: 1)), false),
        (const PastDate(), 'not a date', true),
        (const PastOrPresentDate(), now, true),
        (const PastOrPresentDate(), now.add(const Duration(days: 1)), false),
        (const FutureDate(), now.add(const Duration(days: 1)), true),
        (const FutureDate(), now.subtract(const Duration(days: 1)), false),
        (const FutureOrPresentDate(), now, true),
        (
          const FutureOrPresentDate(),
          now.subtract(const Duration(days: 1)),
          false,
        ),
      ];
      for (final (constraint, value, valid) in cases) {
        expect(
          constraint.isValid(value),
          valid,
          reason: '${constraint.name} $value',
        );
        expect(constraint.defaultMessage, isNotEmpty);
      }
    });

    test('messages and groups', () {
      expect(
        const Size(min: 1, max: 3).interpolatedMessage(),
        'size must be between 1 and 3',
      );
      expect(
        const Min(2, message: 'at least {value}!').interpolatedMessage(),
        'at least 2!',
      );
      expect(const Digits(integer: 1, fraction: 2).attributes, {
        'fraction': 2,
        'integer': 1,
      });
      expect(const Matches('x').attributes, {'regexp': 'x'});
      expect(const Max(1).attributes, {'value': 1});
      expect(const NotNull().appliesTo([]), isTrue);
      expect(const NotNull().appliesTo([Default]), isTrue);
      expect(const NotNull().appliesTo([Strict]), isFalse);
      expect(const NotNull(groups: [Strict]).appliesTo([]), isFalse);
      expect(const NotNull(groups: [Strict]).appliesTo([Strict]), isTrue);
      expect(const NotNull(groups: [Default]).appliesTo([]), isTrue);
    });
  });

  group('BeanValidator', () {
    final validator = BeanValidator(introspector: introspector());

    Person valid() => Person()
      ..name = 'Ada'
      ..age = 30
      ..address = Address('London');

    test('valid object', () {
      expect(validator.validateObject(valid()), isEmpty);
      expect(validator.supports(Person()), isTrue);
      expect(validator.supports(Object()), isFalse);
      expect(
        BeanValidator().supports(Person()),
        isFalse,
        reason: 'shared registry is empty',
      );
    });

    test('violations: properties, cascade, collections, class-level', () {
      final person = Person()
        ..name = 'A'
        ..age = 10
        ..address = (Address()..zip = 'abc')
        ..previous = [Address('ok'), Address()]
        ..byLabel = {'home': Address()};
      person.previous.add(person.previous.first);
      final violations = validator.validateObject(person);
      expect(
        violations.map((v) => '${v.propertyPath}:${v.constraint.name}'),
        unorderedEquals([
          ':Adult',
          'name:Size',
          'address.city:NotBlank',
          'address.zip:Pattern',
          'previous[1].city:NotBlank',
          'byLabel[home].city:NotBlank',
        ]),
      );
      final size = violations.firstWhere((v) => v.constraint is Size);
      expect(size.message, 'size must be between 2 and 10');
      expect(size.invalidValue, 'A');
      expect(size.rootBean, same(person));
      expect(size.toString(), 'name: size must be between 2 and 10');
    });

    test('groups', () {
      final person = valid()..age = 200;
      expect(validator.validateObject(person), isEmpty);
      expect(
        validator.validateObject(person, groups: [Strict]).single.propertyPath,
        'age',
      );
    });

    test('validateProperty and validateValue', () {
      expect(
        validator.validateProperty(valid()..name = '', 'name'),
        hasLength(2),
      );
      final byValue = validator.validateValue(Person, 'name', 'x').single;
      expect(byValue.constraint, isA<Size>());
      expect(byValue.rootBean, isNull, reason: 'no instance, as in Spring');
      expect(
        validator.validateValue(Person, 'age', 200, groups: [Strict]),
        hasLength(1),
      );
      expect(
        () => validator.validateProperty(valid(), 'nope'),
        throwsArgumentError,
      );
      expect(
        () => validator.validateValue(Person, 'nope', 1),
        throwsArgumentError,
      );
      expect(
        () => validator.validateValue(Object, 'x', 1),
        throwsArgumentError,
      );
    });

    test('errors use Spring codes and arguments', () {
      final person = valid()..name = '';
      final errors = BeanPropertyBindingResult(
        person,
        'person',
        introspector: introspector(),
      );
      validator.validate(person, errors);
      final error = errors.fieldError('name')!;
      expect(error.codes, [
        'NotBlank.person.name',
        'NotBlank.name',
        'NotBlank.String',
        'NotBlank',
      ]);
      final sizeError = errors.fieldErrors('name').last;
      expect(sizeError.arguments.skip(1), [
        10,
        2,
      ], reason: 'attributes sorted by name: max, min');
      final resolvable =
          sizeError.arguments.first! as DefaultMessageSourceResolvable;
      expect(resolvable.codes, ['person.name', 'name']);
      final adult = BeanPropertyBindingResult(
        valid()..age = 3,
        'person',
        introspector: introspector(),
      );
      validator.validateWithGroups(adult.target!, adult, const []);
      expect(adult.globalError!.codes, ['Adult.person', 'Adult']);
      expect(adult.globalError!.arguments, isEmpty);
    });
  });

  group('Errors and binding results', () {
    test('field and global errors, nested paths, wildcards', () {
      final person = Person()..address = Address('Oslo');
      final errors = BeanPropertyBindingResult(
        person,
        'person',
        introspector: introspector(),
      );
      expect(errors.hasErrors, isFalse);
      errors
        ..reject('global', defaultMessage: 'bad')
        ..rejectValue('name', 'required')
        ..pushNestedPath('address')
        ..rejectValue('city', 'invalid', args: ['x'])
        ..rejectValue('', 'whole');
      expect(errors.nestedPath, 'address.');
      errors.popNestedPath();
      expect(() => errors.popNestedPath(), throwsStateError);
      expect(errors.errorCount, 4);
      expect(errors.hasGlobalErrors, isTrue);
      expect(errors.globalError!.codes.first, 'global.person');
      expect(errors.globalError!.code, 'global', reason: 'plain code');
      expect(errors.hasFieldErrors(), isTrue);
      expect(errors.hasFieldErrors('address*'), isTrue);
      expect(errors.fieldErrors('address.*'), hasLength(1));
      expect(errors.fieldError('address.city')!.rejectedValue, 'Oslo');
      expect(errors.fieldError('address')!.codes.first, 'whole.person.address');
      expect(errors.fieldError('address')!.code, 'whole');
      expect(errors.fieldError('nope'), isNull);
      expect(errors.getFieldValue('address.city'), 'Oslo');
      expect(errors.getFieldValue('nope'), isNull);
      expect(
        errors.allErrors.first.toString(),
        contains("Error in object 'person'"),
      );
      expect(errors.fieldError()!.toString(), contains("on field 'name'"));
      expect(errors.toString(), contains('4 errors'));
      expect(errors.model.keys, ['person', 'BindingResult.person']);
      errors.nestedPath = 'address';
      expect(errors.nestedPath, 'address.');
      errors.nestedPath = '';
      errors.rejectValue('', 'empty');
      expect(errors.globalErrors, hasLength(2));
    });

    test('addError and addAllErrors check the object name', () {
      final a = MapBindingResult({'x': 1}, 'a');
      final b = MapBindingResult({'x': 2}, 'b')..reject('e');
      expect(() => a.addAllErrors(b), throwsArgumentError);
      expect(() => a.addError(ObjectError('b', ['e'])), throwsArgumentError);
      final c = MapBindingResult({}, 'a')..rejectValue('x', 'e');
      a.addAllErrors(c);
      expect(a.errorCount, 1);
      expect(a.getFieldValue('x'), 1);
      expect(a.target, {'x': 1});
    });

    test('message codes resolver options', () {
      const resolver = DefaultMessageCodesResolver(
        prefix: 'v.',
        postfixFormat: true,
      );
      expect(resolver.resolveMessageCodes('required', 'user'), [
        'v.user.required',
        'v.required',
      ]);
      expect(
        resolver.resolveFieldMessageCodes(
          'required',
          'user',
          'items[0].sku',
          String,
        ),
        [
          'v.user.items[0].sku.required',
          'v.user.items.sku.required',
          'v.items[0].sku.required',
          'v.items.sku.required',
          'v.String.required',
          'v.required',
        ],
      );
      expect(
        const DefaultMessageCodesResolver().resolveFieldMessageCodes(
          'c',
          'o',
          'f',
          null,
        ),
        ['c.o.f', 'c.f', 'c'],
      );
    });

    test('ValidationUtils', () {
      final errors = MapBindingResult({
        'a': '',
        'b': '  ',
        'c': [],
        'd': 'x',
        'e': <String, int>{},
        'f': 1,
      }, 'm');
      ValidationUtils.rejectIfEmpty(errors, 'a', 'empty');
      ValidationUtils.rejectIfEmpty(errors, 'b', 'empty');
      ValidationUtils.rejectIfEmptyOrWhitespace(errors, 'b', 'blank');
      ValidationUtils.rejectIfEmpty(errors, 'c', 'empty');
      ValidationUtils.rejectIfEmpty(errors, 'd', 'empty');
      ValidationUtils.rejectIfEmpty(errors, 'e', 'empty');
      ValidationUtils.rejectIfEmpty(errors, 'f', 'empty');
      ValidationUtils.rejectIfEmpty(
        errors,
        'missing',
        'empty',
        defaultMessage: 'x',
      );
      expect(errors.fieldErrors().map((e) => e.field), [
        'a',
        'b',
        'c',
        'e',
        'missing',
      ]);
      expect(
        () =>
            ValidationUtils.invokeValidator(BeanValidator(), Object(), errors),
        throwsArgumentError,
      );
      final plain = _PlainValidator();
      ValidationUtils.invokeValidator(plain, 'x', errors, groups: [Strict]);
      expect(plain.calls, 1);
    });
  });

  group('DataBinder', () {
    DataBinder binder(Person person) =>
        DataBinder(person, objectName: 'person', introspector: introspector());

    test('binder and binding result share the conversion service', () {
      final conversions = DefaultConversionService();
      final binder = DataBinder(
        Person(),
        introspector: introspector(),
        conversionService: conversions,
      );
      expect(binder.conversionService, same(conversions));
      expect(binder.bindingResult.wrapper.conversionService, same(conversions));
    });

    test('binding with conversion and errors', () {
      final person = Person();
      final dataBinder = binder(person)
        ..bind({
          'name': 'Ada',
          'age': 'x',
          'score': '1.5',
          'unknown': 1,
          'tags': 'a,b',
        });
      expect(person.name, 'Ada');
      expect(person.score, 1.5);
      expect(person.tags, ['a', 'b']);
      final error = dataBinder.bindingResult.fieldError('age')!;
      expect(error.bindingFailure, isTrue);
      expect(error.codes.first, 'typeMismatch.person.age');
      expect(error.codes, contains('typeMismatch.int'));
      expect(error.arguments, [int]);
      expect(dataBinder.bindingResult.getFieldValue('age'), 'x');
      expect(dataBinder.objectName, 'person');
      expect(
        DataBinder(Person(), introspector: introspector()).objectName,
        'target',
      );
    });

    test('allowed, disallowed and required fields', () {
      final person = Person();
      final dataBinder = binder(person)
        ..allowedFields = ['name', 'age', 'address.*', 'score']
        ..disallowedFields = ['score']
        ..requiredFields = ['name', 'age']
        ..bind({
          'name': ' ',
          'age': '5',
          'score': '1',
          'tags': 'x',
          'address.city': 'Rome',
        });
      expect(person.age, 5);
      expect(person.score, isNull);
      expect(person.tags, isEmpty);
      expect(person.address!.city, 'Rome', reason: 'auto-grow');
      expect(dataBinder.suppressedFields, ['score', 'tags']);
      expect(
        dataBinder.bindingResult.fieldError('name')!.codes.first,
        'required.person.name',
      );
      expect(DataBinder.simpleMatch('a*c', 'abbc'), isTrue);
      expect(DataBinder.simpleMatch('a.b', 'axb'), isFalse);
    });

    test('strict modes', () {
      expect(
        () => (binder(
          Person(),
        )..ignoreUnknownFields = false).bind({'unknown': 1}),
        throwsA(isA<NotWritablePropertyException>()),
      );
      final noGrow = binder(Person())..autoGrowNestedPaths = false;
      expect(
        () => noGrow.bind({'address.city': 'x'}),
        throwsA(isA<NullValueInNestedPathException>()),
      );
      (binder(Person())
            ..autoGrowNestedPaths = false
            ..ignoreInvalidFields = true)
          .bind({'address.city': 'x', 'previous[3].city': 'y'});
      expect(
        () => binder(Person()).bind({'previous[3].city': 'y'}),
        throwsA(isA<NotReadablePropertyException>()),
      );
      final readOnly = binder(Person())
        ..bind({'id': 'x', 'counts[a]': 'not int'});
      expect(readOnly.bindingResult.fieldErrors().single.field, 'counts[a]');
      expect(
        readOnly.bindingResult.fieldError('counts[a]')!.bindingFailure,
        isTrue,
      );
    });

    test('other bean errors become methodInvocation errors', () {
      final dataBinder = binder(Person())..bind({'lucky[0]': 1});
      expect(dataBinder.bindingResult.hasErrors, isFalse);
      final failing = DataBinder(
        _Failing(),
        introspector: BeanIntrospector(introspections: [_failingIntrospection]),
      )..bind({'value': 'x'});
      expect(
        failing.bindingResult.fieldError('value')!.codes.first,
        'methodInvocation.target.value',
      );
    });

    test('validate and close', () {
      final person = Person();
      final dataBinder = binder(person)
        ..validators.addAll([
          BeanValidator(introspector: introspector()),
          _PlainValidator(),
        ])
        ..bind({'name': 'Ada', 'age': '30'})
        ..validate();
      expect(dataBinder.bindingResult.hasErrors, isFalse);
      expect(dataBinder.close()['person'], same(person));
      dataBinder
        ..bind({'age': '200'})
        ..validate(groups: [Strict]);
      expect(
        () => dataBinder.close(),
        throwsA(
          isA<BindException>().having(
            (e) => e.toString(),
            'text',
            contains('Max'),
          ),
        ),
      );
    });
  });
}

class _PlainValidator implements Validator {
  int calls = 0;
  @override
  bool supports(Object target) => target is String;
  @override
  void validate(Object target, Errors errors) => calls++;
}

class _Failing {
  String value = '';
}

final _failingIntrospection = BeanIntrospection<_Failing>(
  properties: [
    BeanProperty<_Failing>(
      'value',
      type: String,
      get: (b) => b.value,
      set: (b, v) => throw BeanDefinitionStoreException('setter failed'),
    ),
  ],
);
