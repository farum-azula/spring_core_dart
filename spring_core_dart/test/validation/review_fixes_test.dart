import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

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
}
