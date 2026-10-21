import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

class Account {
  String owner = '';
  String _iban = '';
  String get iban => _iban;
  set iban(String value) {
    if (!value.startsWith('UA')) {
      throw ArgumentError.value(value, 'iban', 'must start with UA');
    }
    _iban = value;
  }
}

final accountIntrospection = BeanIntrospection<Account>(
  properties: [
    BeanProperty<Account>(
      'owner',
      type: String,
      get: (b) => b.owner,
      set: (b, v) => b.owner = v! as String,
    ),
    BeanProperty<Account>(
      'iban',
      type: String,
      get: (b) => b.iban,
      set: (b, v) => b.iban = v! as String,
    ),
  ],
  instantiate: Account.new,
);

class Code {
  String value = '';
}

final codeIntrospection = BeanIntrospection<Code>(
  properties: [
    BeanProperty<Code>(
      'value',
      type: String,
      get: (b) => b.value,
      set: (b, v) => b.value = v! as String,
      annotations: const [
        NotBlank(message: "can't be blank"),
        Matches('[A-Z]{2,3}'),
      ],
    ),
  ],
  instantiate: Code.new,
);

void main() {
  final introspector = BeanIntrospector(
    introspections: [
      personIntrospection,
      addressIntrospection,
      codeIntrospection,
    ],
  );

  group('disallowedFields cannot be bypassed (CVE-2022-22968 style)', () {
    for (final key in [
      'counts[secret]',
      "counts['secret']",
      'counts["secret"]',
      'counts[ secret ]',
      'counts.secret',
      'COUNTS[SECRET]',
    ]) {
      test(key, () {
        final person = Person();
        final binder =
            DataBinder(person, objectName: 'person', introspector: introspector)
              ..disallowedFields = ['counts[secret]']
              ..bind({key: '1'});
        expect(person.counts, isEmpty, reason: key);
        expect(binder.suppressedFields, isNotEmpty);
      });
    }

    test('wildcards also match keys with line breaks', () {
      final person = Person();
      DataBinder(person, objectName: 'person', introspector: introspector)
        ..disallowedFields = ['counts*']
        ..bind({'counts[a\nb]': '1'});
      expect(person.counts, isEmpty);
    });

    test('allowed keys are still bound', () {
      final person = Person()..byLabel = {'home': Address()};
      final binder =
          DataBinder(person, objectName: 'person', introspector: introspector)
            ..disallowedFields = ['counts[secret]']
            ..bind({"byLabel['home'].city": 'Kyiv'});
      expect(person.byLabel['home']!.city, 'Kyiv');
      expect(binder.suppressedFields, isEmpty);
    });
  });

  group('violation messages are shown as written (Spring)', () {
    test('quotes and regex braces survive', () {
      final code = Code()..value = '';
      final binder = DataBinder(
        code,
        objectName: 'code',
        introspector: introspector,
      )..validators.add(BeanValidator(introspector: introspector));
      binder.validate();
      final messages = StaticMessageSource();
      final rendered = [
        for (final error in binder.bindingResult.fieldErrors())
          messages.getMessageFromResolvable(error),
      ];
      expect(rendered, contains("can't be blank"));
      expect(
        rendered.any((m) => m.contains('[A-Z]{2,3}')),
        isTrue,
        reason: '$rendered',
      );
    });

    test('an invalid MessageFormat pattern is returned raw', () {
      final messages = StaticMessageSource()
        ..addMessage('hint', '', 'Use {a-z} for {0}');
      expect(messages.getMessage('hint', args: ['names']), 'Use {a-z} for {0}');
    });

    test('{0} placeholders in a violation message are still formatted', () {
      final error = FieldError(
        'code',
        'value',
        '',
        const ['NotBlank'],
        arguments: const ['value'],
        defaultMessage: '{0} is required',
        shouldRenderDefaultMessage: true,
      );
      expect(
        StaticMessageSource().getMessageFromResolvable(error),
        'value is required',
      );
    });
  });

  group('DataBinder.bind records errors instead of throwing', () {
    DataBinder binder(Object target) => DataBinder(
      target,
      objectName: 'form',
      introspector: BeanIntrospector(
        introspections: [
          personIntrospection,
          addressIntrospection,
          accountIntrospection,
        ],
      ),
    );

    test('malformed keys are skipped like unknown fields', () {
      final person = Person();
      final b = binder(person)
        ..bind({
          'items[': 'x',
          'address..city': 'y',
          'tags[': 'z',
          'name': 'Ada',
        });
      expect(person.name, 'Ada'); // the rest is still bound
      expect(b.bindingResult.hasErrors, isFalse);
    });

    test('malformed keys throw when unknown fields are not ignored', () {
      final b = binder(Person())..ignoreUnknownFields = false;
      expect(
        () => b.bind({'items[': 'x'}),
        throwsA(
          isA<InvalidPropertyException>().having(
            (e) => e.propertyName,
            'propertyName',
            'items[',
          ),
        ),
      );
    });

    test('a throwing setter becomes a methodInvocation error', () {
      final account = Account();
      final b = binder(account)..bind({'iban': 'DE00', 'owner': 'Ada'});
      final error = b.bindingResult.fieldError('iban')!;
      expect(error.codes.first, 'methodInvocation.form.iban');
      expect(error.rejectedValue, 'DE00');
      expect(error.defaultMessage, contains('must start with UA'));
      expect(account.owner, 'Ada'); // binding went on
      expect(account.iban, '');
    });

    test('BeanWrapper wraps setter errors in MethodInvocationException', () {
      final wrapper = BeanWrapper(
        Account(),
        introspector: BeanIntrospector(introspections: [accountIntrospection]),
      );
      expect(
        () => wrapper.setPropertyValue('iban', 'DE00'),
        throwsA(
          isA<MethodInvocationException>()
              .having((e) => e.propertyName, 'propertyName', 'iban')
              .having((e) => e.cause, 'cause', isArgumentError),
        ),
      );
    });
  });
}
