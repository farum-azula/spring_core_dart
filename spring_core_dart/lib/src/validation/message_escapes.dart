// Jakarta message escapes (`\{`, `\}`, `\$`, `\\`): literal characters
// that interpolation must not treat as placeholders. They are replaced by
// private-use characters before interpolating and turned into the literal
// characters afterwards, so values inserted by interpolation (a regular
// expression with `\d{2}`) are left as they are.
//
// Internal: used by `Constraint.interpolate` and `BeanValidator`.

const _escapes = {
  r'\\': '\uE000',
  r'\{': '\uE001',
  r'\}': '\uE002',
  r'\$': '\uE003',
};

final _escape = RegExp(r'\\[\\{}$]');
final _escaped = RegExp('[\uE000-\uE003]');

/// [template] with its escape sequences hidden from interpolation.
String hideMessageEscapes(String template) =>
    template.replaceAllMapped(_escape, (match) => _escapes[match[0]!]!);

/// [message] with the hidden escapes turned into their literal characters.
String revealMessageEscapes(String message) => message.replaceAllMapped(
  _escaped,
  (match) => switch (match[0]!) {
    '\uE000' => r'\',
    '\uE001' => '{',
    '\uE002' => '}',
    _ => r'$',
  },
);

final _attribute = RegExp(r'(?<!\$)\{(\w+)\}');

/// [template] with `{attribute}` placeholders replaced by [attributes], in
/// one pass, so an attribute value containing braces (a regular expression
/// such as `[A-Z]{2,3}`) is not interpolated again; escapes are not
/// handled here (see [hideMessageEscapes]).
String interpolateAttributes(
  String template,
  Map<String, Object?> attributes,
) => template.replaceAllMapped(
  _attribute,
  (match) =>
      attributes.containsKey(match[1]) ? '${attributes[match[1]]}' : match[0]!,
);

/// Hibernate Validator's default messages (its `ValidationMessages`), by
/// constraint name: what `{jakarta.validation.constraints.<Name>.message}`
/// stands for when no message source defines it.
const builtInConstraintMessages = {
  'AssertFalse': 'must be false',
  'AssertTrue': 'must be true',
  'DecimalMax': 'must be less than or equal to {value}',
  'DecimalMin': 'must be greater than or equal to {value}',
  'Digits':
      'numeric value out of bounds (<{integer} digits>.<{fraction} digits> '
      'expected)',
  'Email': 'must be a well-formed email address',
  'Future': 'must be a future date',
  'FutureOrPresent': 'must be a date in the present or in the future',
  'Max': 'must be less than or equal to {value}',
  'Min': 'must be greater than or equal to {value}',
  'Negative': 'must be less than 0',
  'NegativeOrZero': 'must be less than or equal to 0',
  'NotBlank': 'must not be blank',
  'NotEmpty': 'must not be empty',
  'NotNull': 'must not be null',
  'Null': 'must be null',
  'Past': 'must be a past date',
  'PastOrPresent': 'must be a date in the past or in the present',
  'Pattern': 'must match "{regexp}"',
  'Positive': 'must be greater than 0',
  'PositiveOrZero': 'must be greater than or equal to 0',
  'Size': 'size must be between {min} and {max}',
};
