import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Box {
  Box(this.value);
  Object? value;
}

List<String> _messages(
  Object? value,
  List<Object> annotations, {
  MessageSource? source,
}) => [
  for (final violation in BeanValidator(
    introspector: BeanIntrospector(
      introspections: [
        BeanIntrospection<Box>(
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
        ),
      ],
    ),
    validationMessageSource: source,
  ).validateObject(Box(value)))
    violation.message,
];

void main() {
  group(
    '{jakarta.validation.constraints.X.message} without a message source',
    () {
      test("the constraint's own message", () {
        expect(
          _messages(null, const [
            NotNull(
              message: '{jakarta.validation.constraints.NotNull.message}',
            ),
          ]),
          ['must not be null'],
        );
        expect(
          _messages('abc', const [
            Size(
              max: 2,
              message:
                  'Too long: {jakarta.validation.constraints.Size.message}',
            ),
          ]),
          ['Too long: size must be between 0 and 2'],
        );
        expect(
          _messages(1, const [
            DecimalMin(
              '5',
              inclusive: false,
              message: '{jakarta.validation.constraints.DecimalMin.message}',
            ),
          ]),
          ['must be greater than 5'],
        );
      });

      test("another constraint's message (Hibernate's defaults)", () {
        expect(
          _messages(null, const [
            NotNull(
              message: '{jakarta.validation.constraints.NotBlank.message}',
            ),
          ]),
          ['must not be blank'],
        );
      });

      test('a message source still wins; unknown keys stay', () {
        final source = StaticMessageSource()
          ..addMessage(
            'jakarta.validation.constraints.NotNull.message',
            '',
            'is required',
          );
        expect(
          _messages(null, const [
            NotNull(
              message: '{jakarta.validation.constraints.NotNull.message}',
            ),
          ], source: source),
          ['is required'],
        );
        expect(_messages(null, const [NotNull(message: '{app.unknown}')]), [
          '{app.unknown}',
        ]);
      });
    },
  );

  group(r'\{, \}, \$ and \\ are literal characters', () {
    test('in BeanValidator messages', () {
      expect(
        _messages('abc', const [
          Size(
            max: 2,
            message: r'\{max\} is {max}, \$\{max\} or \${max}, \$5 \\ ok',
          ),
        ]),
        // `\$` is a literal `$`, so `\${max}` is `$` and the parameter.
        [r'{max} is 2, ${max} or $2, $5 \ ok'],
      );
      // An escaped message key is not resolved.
      expect(
        _messages(null, const [
          NotNull(
            message: r'\{jakarta.validation.constraints.NotNull.message}',
          ),
        ]),
        ['{jakarta.validation.constraints.NotNull.message}'],
      );
      // Inserted attribute values keep their backslashes.
      expect(
        _messages('x', const [
          Matches(r'\d{2}', message: 'must match {regexp}'),
        ]),
        [r'must match \d{2}'],
      );
    });

    test('in Constraint.interpolate', () {
      expect(
        const Size(max: 20).interpolate(r'\{max} is {max}'),
        '{max} is 20',
      );
      expect(const Size(max: 20).interpolate(r'a \\{max}'), r'a \20');
    });
  });
}
