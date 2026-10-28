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

/// [template] with each escape (`\{`, `\}`, `\$`, `\\`) replaced by a
/// private-use character, so the following interpolation steps do not see
/// a placeholder in it. Undo with [revealMessageEscapes].
String hideMessageEscapes(String template) =>
    template.replaceAllMapped(_escape, (match) => _escapes[match[0]!]!);

/// [message] with the characters [hideMessageEscapes] put in turned into
/// the literal `\`, `{`, `}` and `$`; the last step of interpolation.
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

/// [template] with each `{name}` placeholder whose name is a key of
/// [attributes] replaced by that value; other placeholders and `${...}`
/// expressions stay.
///
/// One pass, so an inserted value with braces (a regular expression such
/// as `[A-Z]{2,3}`) is not interpolated again. Escapes must already be
/// hidden with [hideMessageEscapes].
String interpolateAttributes(
  String template,
  Map<String, Object?> attributes,
) => template.replaceAllMapped(
  _attribute,
  (match) =>
      attributes.containsKey(match[1]) ? '${attributes[match[1]]}' : match[0]!,
);

/// Hibernate Validator's English default messages (its
/// `ValidationMessages`), by constraint name.
///
/// A message may refer to another constraint's message with
/// `{jakarta.validation.constraints.<Name>.message}`; when the validator's
/// message source does not define that key, the text comes from here.
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
