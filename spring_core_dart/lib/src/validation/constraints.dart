/// Default validation group (constraints without groups belong to it).
///
/// Validating without groups runs the constraints of this group; list it
/// explicitly to combine it with other groups.
///
/// ```dart
/// abstract final class OnUpdate {}
///
/// validator.validateObject(form, groups: [Default, OnUpdate]);
/// ```
///
/// Spring (Java):
/// ```java
/// validator.validate(form, Default.class, OnUpdate.class);
/// ```
abstract final class Default {}

/// A declarative constraint, like a Jakarta Bean Validation annotation.
///
/// Constraints are const annotations on properties of `@Introspected`
/// classes (or on the class itself for class-level checks). Subclass it
/// for custom constraints. Like Jakarta, most constraints accept `null`;
/// combine with [NotNull] to require a value.
///
/// ```dart
/// // A class-level constraint comparing two properties.
/// class PasswordsMatch extends Constraint {
///   const PasswordsMatch({super.message});
///
///   @override
///   String get name => 'PasswordsMatch';
///
///   @override
///   String get defaultMessage => 'passwords must match';
///
///   @override
///   bool isValid(Object? value) =>
///       value is! SignupForm || value.password == value.confirm;
/// }
///
/// @Introspected()
/// @PasswordsMatch()
/// class SignupForm {
///   String password = '';
///   String confirm = '';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Constraint(validatedBy = PasswordsMatchValidator.class)
/// @Target(TYPE) @Retention(RUNTIME)
/// public @interface PasswordsMatch {
///   String message() default "passwords must match";
///   Class<?>[] groups() default {};
///   Class<? extends Payload>[] payload() default {};
/// }
///
/// class PasswordsMatchValidator
///     implements ConstraintValidator<PasswordsMatch, SignupForm> {
///   public boolean isValid(SignupForm f, ConstraintValidatorContext c) {
///     return f == null || f.getPassword().equals(f.getConfirm());
///   }
/// }
/// ```
abstract class Constraint {
  /// Creates a constraint with an optional custom [message] and [groups].
  const Constraint({this.message, this.groups = const []});

  /// Custom message; `{attribute}` placeholders are interpolated.
  final String? message;

  /// Groups the constraint belongs to; empty means [Default].
  final List<Type> groups;

  /// Error code, e.g. `NotBlank`.
  String get name;

  /// Message used when [message] is not set.
  String get defaultMessage;

  /// Attributes for messages and error arguments (e.g. `min`, `max`).
  Map<String, Object?> get attributes => const {};

  /// Whether [value] satisfies the constraint.
  ///
  /// For property constraints [value] is the property value; for
  /// class-level constraints it is the annotated object itself.
  bool isValid(Object? value);

  /// Whether [value] satisfies the constraint, with access to the
  /// validation [context] (its clock, custom violations), like Jakarta's
  /// `ConstraintValidator.isValid(value, context)`.
  ///
  /// `BeanValidator` calls this method; by default it calls [isValid].
  /// Override it to read the injectable clock or to report violations on
  /// a property of a class-level constraint:
  ///
  /// ```dart
  /// @override
  /// bool isValidWithContext(Object? value, ConstraintValidatorContext context) {
  ///   if (isValid(value)) return true;
  ///   context
  ///     ..disableDefaultConstraintViolation()
  ///     ..buildConstraintViolationWithTemplate(context.defaultConstraintMessageTemplate)
  ///         .addPropertyNode('confirm')
  ///         .addConstraintViolation();
  ///   return false;
  /// }
  /// ```
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      isValid(value);

  /// [message] or [defaultMessage] with attributes interpolated.
  ///
  /// ```dart
  /// const Size(max: 20).interpolatedMessage();
  /// // 'size must be between 0 and 20'
  /// ```
  String interpolatedMessage() => interpolate(message ?? defaultMessage);

  /// [template] with `{attribute}` placeholders replaced by the attribute
  /// values; other placeholders are kept.
  ///
  /// ```dart
  /// const Size(max: 20).interpolate('at most {max}'); // 'at most 20'
  /// ```
  String interpolate(String template) {
    // One pass, so an attribute value containing braces (a regular
    // expression such as `[A-Z]{2,3}`) is not interpolated again.
    final attributes = this.attributes;
    return template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) => attributes.containsKey(match.group(1))
          ? '${attributes[match.group(1)]}'
          : match.group(0)!,
    );
  }

  /// Whether the constraint applies when validating [requested] groups.
  ///
  /// No requested groups means [Default]; a constraint without groups
  /// belongs to [Default].
  bool appliesTo(List<Type> requested) {
    if (requested.isEmpty) {
      return groups.isEmpty || groups.contains(Default);
    }
    if (groups.isEmpty) {
      return requested.contains(Default);
    }
    return groups.any(requested.contains);
  }
}

/// The current time for the date constraints, like Jakarta's
/// `ClockProvider` (here the time itself; Dart has no `Clock` type).
///
/// ```dart
/// final class FixedClock implements ClockProvider {
///   const FixedClock(this.time);
///   final DateTime time;
///   @override
///   DateTime now() => time;
/// }
///
/// BeanValidator(clockProvider: FixedClock(DateTime.utc(2026, 1, 1)));
/// ```
///
/// Spring (Java):
/// ```java
/// LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
/// validator.setClockProvider(() -> Clock.fixed(instant, ZoneOffset.UTC));
/// ```
abstract interface class ClockProvider {
  /// The current time.
  DateTime now();
}

/// The system clock (`DateTime.now()`), Jakarta's default `ClockProvider`.
final class DefaultClockProvider implements ClockProvider {
  /// Creates the system clock provider.
  const DefaultClockProvider();

  @override
  DateTime now() => DateTime.now();
}

/// What a constraint can use and report while validating a value, like
/// Jakarta's `ConstraintValidatorContext` (see
/// [Constraint.isValidWithContext]).
///
/// ```dart
/// // A class-level constraint reporting on the `confirm` property.
/// context
///   ..disableDefaultConstraintViolation()
///   ..buildConstraintViolationWithTemplate('{passwords.mismatch}')
///       .addPropertyNode('confirm')
///       .addConstraintViolation();
/// ```
///
/// Spring (Java):
/// ```java
/// context.disableDefaultConstraintViolation();
/// context.buildConstraintViolationWithTemplate("{passwords.mismatch}")
///     .addPropertyNode("confirm")
///     .addConstraintViolation();
/// ```
final class ConstraintValidatorContext {
  /// A context for a constraint whose message template is
  /// [defaultConstraintMessageTemplate]; [clockProvider] gives the time.
  ConstraintValidatorContext({
    required this.defaultConstraintMessageTemplate,
    this.clockProvider = const DefaultClockProvider(),
  });

  /// The clock of the validator, for date constraints.
  final ClockProvider clockProvider;

  /// The constraint's message template (`message` or its default).
  final String defaultConstraintMessageTemplate;

  bool _defaultDisabled = false;
  final _violations = <({String messageTemplate, List<String> nodes})>[];

  /// Whether [disableDefaultConstraintViolation] was called (read by the
  /// validator).
  bool get defaultConstraintViolationDisabled => _defaultDisabled;

  /// The violations added with [buildConstraintViolationWithTemplate], in
  /// order: their message template and property nodes (read by the
  /// validator).
  List<({String messageTemplate, List<String> nodes})> get customViolations =>
      List.unmodifiable(_violations);

  /// Leaves out the violation the validator reports when the constraint
  /// fails, so only custom ones are reported.
  void disableDefaultConstraintViolation() => _defaultDisabled = true;

  /// Starts a custom violation with [messageTemplate] (`{key}` and
  /// attribute placeholders are interpolated).
  ConstraintViolationBuilder buildConstraintViolationWithTemplate(
    String messageTemplate,
  ) => ConstraintViolationBuilder._(this, messageTemplate);
}

/// Builds a custom violation, like Jakarta's `ConstraintViolationBuilder`.
///
/// ```dart
/// context
///     .buildConstraintViolationWithTemplate('must match the password')
///     .addPropertyNode('confirm')
///     .addConstraintViolation();
/// ```
final class ConstraintViolationBuilder {
  ConstraintViolationBuilder._(this._context, this._template);

  final ConstraintValidatorContext _context;
  final String _template;
  final _nodes = <String>[];

  /// Reports the violation on property [name] (relative to the validated
  /// object; call again for nested properties).
  ConstraintViolationBuilder addPropertyNode(String name) {
    _nodes.add(name);
    return this;
  }

  /// Adds the violation to the context.
  ConstraintValidatorContext addConstraintViolation() {
    _context._violations.add((
      messageTemplate: _template,
      nodes: List.unmodifiable(_nodes),
    ));
    return _context;
  }
}

/// Validates nested objects, collections and maps, like Jakarta's `@Valid`.
///
/// Elements of lists are reported as `items[0].sku`, map values as
/// `byKey[key].sku`; `null` values are skipped.
///
/// ```dart
/// @Introspected()
/// class Order {
///   @Valid()
///   Address address = Address();
///
///   @Valid()
///   List<Item> items = [];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Order {
///   @Valid
///   private Address address;
///
///   @Valid
///   private List<Item> items;
/// }
/// ```
class Valid {
  /// Creates the `@Valid()` annotation.
  const Valid();
}

// Length of strings, collections and maps; `null` for anything else so
// that size checks ignore unsupported values (like Jakarta).
int? _length(Object? value) => switch (value) {
  String() => value.length,
  Iterable<Object?>() => value.length,
  Map<Object?, Object?>() => value.length,
  _ => null,
};

/// The annotated value must not be `null`.
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotNull()
///   String? email;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @NotNull
///   private String email;
/// }
/// ```
class NotNull extends Constraint {
  /// Creates the `@NotNull()` constraint.
  const NotNull({super.message, super.groups});

  @override
  String get name => 'NotNull';

  @override
  String get defaultMessage => 'must not be null';

  @override
  bool isValid(Object? value) => value != null;
}

/// The annotated value must be `null`; error code `Null` (renamed: `Null`
/// is a Dart core type).
///
/// ```dart
/// @Introspected()
/// class NewUser {
///   @MustBeNull(groups: [OnCreate])
///   int? id;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class NewUser {
///   @Null(groups = OnCreate.class)
///   private Long id;
/// }
/// ```
class MustBeNull extends Constraint {
  /// Creates the `@MustBeNull()` constraint.
  const MustBeNull({super.message, super.groups});

  @override
  String get name => 'Null';

  @override
  String get defaultMessage => 'must be null';

  @override
  bool isValid(Object? value) => value == null;
}

/// Not null, and a non-empty string, collection or map.
///
/// Other non-null values are always valid.
///
/// ```dart
/// @Introspected()
/// class Cart {
///   @NotEmpty()
///   List<String> items = [];
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Cart {
///   @NotEmpty
///   private List<String> items;
/// }
/// ```
class NotEmpty extends Constraint {
  /// Creates the `@NotEmpty()` constraint.
  const NotEmpty({super.message, super.groups});

  @override
  String get name => 'NotEmpty';

  @override
  String get defaultMessage => 'must not be empty';

  @override
  bool isValid(Object? value) => value != null && (_length(value) ?? 1) > 0;
}

/// Not null and with at least one character above U+0020, like Hibernate
/// Validator (Java's `String.trim()`: a no-break space counts as text,
/// control characters do not).
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotBlank()
///   String name = '';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @NotBlank
///   private String name;
/// }
/// ```
class NotBlank extends Constraint {
  /// Creates the `@NotBlank()` constraint.
  const NotBlank({super.message, super.groups});

  @override
  String get name => 'NotBlank';

  @override
  String get defaultMessage => 'must not be blank';

  @override
  bool isValid(Object? value) =>
      value != null && '$value'.codeUnits.any((unit) => unit > 0x20);
}

/// Length of a string, collection or map within [min]..[max].
///
/// `null` and other value types are valid. Error arguments are
/// `[field, max, min]` (attributes sorted by name).
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @Size(min: 2, max: 20)
///   String name = '';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @Size(min = 2, max = 20)
///   private String name;
/// }
/// ```
class Size extends Constraint {
  /// Creates a `@Size` constraint; both bounds are inclusive.
  const Size({
    this.min = 0,
    this.max = 0x7FFFFFFF,
    super.message,
    super.groups,
  });

  /// Minimum length (inclusive), `0` by default.
  final int min;

  /// Maximum length (inclusive), unbounded by default.
  final int max;

  @override
  String get name => 'Size';

  @override
  String get defaultMessage => 'size must be between {min} and {max}';

  @override
  Map<String, Object?> get attributes => {'max': max, 'min': min};

  @override
  bool isValid(Object? value) {
    final length = _length(value);
    return length == null || (length >= min && length <= max);
  }
}

/// An exact decimal number (`unscaled × 10^-scale`), like `BigDecimal`, so
/// numeric constraints compare `int`, `double`, `BigInt` and numeric
/// strings without rounding.
final class _Decimal implements Comparable<_Decimal> {
  const _Decimal(this.unscaled, this.scale);

  final BigInt unscaled;
  final int scale;

  static final _syntax = RegExp(
    r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$',
  );

  /// `BigDecimal(text)`: `12`, `-1.50`, `1e3`; `null` when malformed.
  static _Decimal? parse(String text) {
    final match = _syntax.firstMatch(text);
    if (match == null) {
      return null;
    }
    final whole = match[2]!;
    final fraction = match[3] ?? '';
    if (whole.isEmpty && fraction.isEmpty) {
      return null;
    }
    final digits = BigInt.parse('$whole$fraction');
    final exponent = int.parse(match[4] ?? '0');
    return _Decimal(
      match[1] == '-' ? -digits : digits,
      fraction.length - exponent,
    );
  }

  /// [value] as a decimal: a finite `num`, a `BigInt` or a numeric string.
  static _Decimal? of(Object? value) => switch (value) {
    final int value => _Decimal(BigInt.from(value), 0),
    final double value when value.isFinite => parse('$value'),
    final BigInt value => _Decimal(value, 0),
    final String value => parse(value),
    _ => null,
  };

  int get signum => unscaled.sign;

  /// Number of significant digits of [unscaled] (`BigDecimal.precision()`).
  int get precision =>
      unscaled == BigInt.zero ? 1 : unscaled.abs().toString().length;

  _Decimal stripTrailingZeros() {
    if (unscaled == BigInt.zero) {
      return _Decimal(BigInt.zero, 0);
    }
    var digits = unscaled;
    var scale = this.scale;
    final ten = BigInt.from(10);
    while (digits % ten == BigInt.zero) {
      digits ~/= ten;
      scale--;
    }
    return _Decimal(digits, scale);
  }

  @override
  int compareTo(_Decimal other) {
    final scale = this.scale > other.scale ? this.scale : other.scale;
    BigInt scaled(_Decimal d) =>
        d.unscaled * BigInt.from(10).pow(scale - d.scale);
    return scaled(this).compareTo(scaled(other));
  }
}

// The sign of [value] − [bound] for numeric constraints: `null` (valid)
// for `null` and values that are not numbers, `BigInt`s or strings; `NaN`
// (never valid) for `double.nan` and malformed numeric strings, like
// Hibernate Validator.
num? _compare(Object? value, _Decimal bound) {
  if (value is double && !value.isFinite) {
    return value.isNaN ? double.nan : value.sign;
  }
  if (value is! num && value is! BigInt && value is! String) {
    return null;
  }
  return _Decimal.of(value)?.compareTo(bound) ?? double.nan;
}

final _zero = _Decimal(BigInt.zero, 0);

_Decimal _bound(num value) =>
    _Decimal.of(value) ??
    (throw ArgumentError.value(value, 'value', 'not a finite number'));

/// A number greater than or equal to [value]; `null` is valid.
///
/// Checks `int`, `double`, `BigInt` and numeric strings (exactly, like
/// Hibernate Validator; a string that is not a number fails); other value
/// types are valid.
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @Min(18)
///   int age = 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @Min(18)
///   private int age;
/// }
/// ```
class Min extends Constraint {
  /// Creates a `@Min` constraint with the inclusive lower bound [value].
  const Min(this.value, {super.message, super.groups});

  /// The inclusive lower bound.
  final num value;

  @override
  String get name => 'Min';

  @override
  String get defaultMessage => 'must be greater than or equal to {value}';

  @override
  Map<String, Object?> get attributes => {'value': value};

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _bound(this.value));
    return sign == null || sign >= 0;
  }
}

/// A number less than or equal to [value]; `null` is valid.
///
/// Checks `int`, `double`, `BigInt` and numeric strings like [Min].
///
/// ```dart
/// @Introspected()
/// class Order {
///   @Max(100)
///   int quantity = 1;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Order {
///   @Max(100)
///   private int quantity;
/// }
/// ```
class Max extends Constraint {
  /// Creates a `@Max` constraint with the inclusive upper bound [value].
  const Max(this.value, {super.message, super.groups});

  /// The inclusive upper bound.
  final num value;

  @override
  String get name => 'Max';

  @override
  String get defaultMessage => 'must be less than or equal to {value}';

  @override
  Map<String, Object?> get attributes => {'value': value};

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _bound(this.value));
    return sign == null || sign <= 0;
  }
}

/// A decimal number greater than (or equal to, when [inclusive]) [value],
/// like Jakarta's `@DecimalMin`; `null` is valid.
///
/// [value] is a decimal string (`'0.01'`), compared exactly with `int`,
/// `double`, `BigInt` and numeric strings. Error arguments are
/// `[field, inclusive, value]`.
///
/// ```dart
/// @Introspected()
/// class Product {
///   @DecimalMin('0.01')
///   double price = 1;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Product {
///   @DecimalMin("0.01")
///   private BigDecimal price;
/// }
/// ```
class DecimalMin extends Constraint {
  /// Creates a `@DecimalMin` constraint with the lower bound [value].
  const DecimalMin(
    this.value, {
    this.inclusive = true,
    super.message,
    super.groups,
  });

  /// The lower bound, as a decimal string.
  final String value;

  /// Whether [value] itself is valid.
  final bool inclusive;

  @override
  String get name => 'DecimalMin';

  @override
  String get defaultMessage => inclusive
      ? 'must be greater than or equal to {value}'
      : 'must be greater than {value}';

  @override
  Map<String, Object?> get attributes => {
    'inclusive': inclusive,
    'value': value,
  };

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _decimalBound(this.value));
    return sign == null || (inclusive ? sign >= 0 : sign > 0);
  }
}

/// A decimal number less than (or equal to, when [inclusive]) [value],
/// like Jakarta's `@DecimalMax`; `null` is valid.
///
/// ```dart
/// @Introspected()
/// class Discount {
///   @DecimalMax('100', inclusive: false)
///   double percent = 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Discount {
///   @DecimalMax(value = "100", inclusive = false)
///   private BigDecimal percent;
/// }
/// ```
class DecimalMax extends Constraint {
  /// Creates a `@DecimalMax` constraint with the upper bound [value].
  const DecimalMax(
    this.value, {
    this.inclusive = true,
    super.message,
    super.groups,
  });

  /// The upper bound, as a decimal string.
  final String value;

  /// Whether [value] itself is valid.
  final bool inclusive;

  @override
  String get name => 'DecimalMax';

  @override
  String get defaultMessage => inclusive
      ? 'must be less than or equal to {value}'
      : 'must be less than {value}';

  @override
  Map<String, Object?> get attributes => {
    'inclusive': inclusive,
    'value': value,
  };

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _decimalBound(this.value));
    return sign == null || (inclusive ? sign <= 0 : sign < 0);
  }
}

_Decimal _decimalBound(String value) =>
    _Decimal.parse(value.trim()) ??
    (throw ArgumentError.value(value, 'value', 'not a decimal number'));

/// A number strictly greater than 0; `null` is valid (numbers, `BigInt`s
/// and numeric strings are checked, like [Min]).
///
/// ```dart
/// @Introspected()
/// class Product {
///   @Positive()
///   double price = 1;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Product {
///   @Positive
///   private double price;
/// }
/// ```
class Positive extends Constraint {
  /// Creates the `@Positive()` constraint.
  const Positive({super.message, super.groups});

  @override
  String get name => 'Positive';

  @override
  String get defaultMessage => 'must be greater than 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign > 0;
  }
}

/// A number greater than or equal to 0; `null` is valid (see [Positive]).
///
/// ```dart
/// @Introspected()
/// class Account {
///   @PositiveOrZero()
///   int balance = 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Account {
///   @PositiveOrZero
///   private int balance;
/// }
/// ```
class PositiveOrZero extends Constraint {
  /// Creates the `@PositiveOrZero()` constraint.
  const PositiveOrZero({super.message, super.groups});

  @override
  String get name => 'PositiveOrZero';

  @override
  String get defaultMessage => 'must be greater than or equal to 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign >= 0;
  }
}

/// A number strictly less than 0; `null` is valid (see [Positive]).
///
/// ```dart
/// @Introspected()
/// class Refund {
///   @Negative()
///   int amount = -1;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Refund {
///   @Negative
///   private int amount;
/// }
/// ```
class Negative extends Constraint {
  /// Creates the `@Negative()` constraint.
  const Negative({super.message, super.groups});

  @override
  String get name => 'Negative';

  @override
  String get defaultMessage => 'must be less than 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign < 0;
  }
}

/// A number less than or equal to 0; `null` is valid (see [Positive]).
///
/// ```dart
/// @Introspected()
/// class Adjustment {
///   @NegativeOrZero()
///   int delta = 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Adjustment {
///   @NegativeOrZero
///   private int delta;
/// }
/// ```
class NegativeOrZero extends Constraint {
  /// Creates the `@NegativeOrZero()` constraint.
  const NegativeOrZero({super.message, super.groups});

  @override
  String get name => 'NegativeOrZero';

  @override
  String get defaultMessage => 'must be less than or equal to 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign <= 0;
  }
}

/// Regular expression flags of [Matches] and [Email], like Jakarta's
/// `Pattern.Flag` (the ones Dart's `RegExp` supports).
enum PatternFlag {
  /// `CASE_INSENSITIVE`: letters match regardless of case.
  caseInsensitive,

  /// `MULTILINE`: `^` and `$` also match at line breaks.
  multiline,

  /// `DOTALL`: `.` also matches line breaks.
  dotall,

  /// `UNICODE_CASE`: Unicode-aware matching (Dart's `unicode: true`).
  unicodeCase,
}

// Whether the whole of [text] matches [regexp] (Java's `Matcher.matches()`;
// the end is asserted with a lookahead so `multiline` keeps the meaning).
bool _fullMatch(String regexp, List<PatternFlag> flags, String text) =>
    RegExp(
      '(?:$regexp)(?![\\s\\S])',
      caseSensitive: !flags.contains(PatternFlag.caseInsensitive),
      multiLine: flags.contains(PatternFlag.multiline),
      dotAll: flags.contains(PatternFlag.dotall),
      unicode: flags.contains(PatternFlag.unicodeCase),
    ).matchAsPrefix(text) !=
    null;

/// A string fully matching [regexp]; error code `Pattern` (renamed: `Pattern`
/// is a Dart core type).
///
/// The whole value must match (Java's `Matcher.matches()`); `null` is
/// valid. Error arguments are `[field, flags, regexp]`, as in Spring.
///
/// ```dart
/// @Introspected()
/// class Address {
///   @Matches(r'\d{5}', message: 'must be 5 digits')
///   String? zip;
///
///   @Matches('[a-z]+', flags: [PatternFlag.caseInsensitive])
///   String code = 'abc';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Address {
///   @Pattern(regexp = "\\d{5}", message = "must be 5 digits")
///   private String zip;
///
///   @Pattern(regexp = "[a-z]+", flags = Pattern.Flag.CASE_INSENSITIVE)
///   private String code;
/// }
/// ```
class Matches extends Constraint {
  /// Creates a `@Matches` constraint for the regular expression [regexp].
  const Matches(
    this.regexp, {
    this.flags = const [],
    super.message,
    super.groups,
  });

  /// The regular expression the whole value must match.
  final String regexp;

  /// How [regexp] is matched (Jakarta's `flags`).
  final List<PatternFlag> flags;

  @override
  String get name => 'Pattern';

  @override
  String get defaultMessage => 'must match "{regexp}"';

  @override
  Map<String, Object?> get attributes => {'flags': flags, 'regexp': regexp};

  @override
  bool isValid(Object? value) =>
      value == null || _fullMatch(regexp, flags, '$value');
}

/// A well-formed email address, checked like Hibernate Validator's
/// `@Email`: a local part of at most 64 characters (dot-separated atoms or
/// quoted strings), `@`, and a domain name (labels without leading or
/// trailing `-`, at most 63 characters each and 255 in total) or an IP
/// address literal (`[192.168.0.1]`, `[IPv6:::1]`).
///
/// `null` and the empty string are valid; combine with [NotBlank] to
/// require an address. [regexp] (with [flags]) is an additional pattern
/// the whole address must match. Error arguments are
/// `[field, flags, regexp]`.
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotNull()
///   @Email()
///   String? email;
///
///   @Email(regexp: r'.+@example\.com')
///   String? work;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @NotNull
///   @Email
///   private String email;
///
///   @Email(regexp = ".+@example\\.com")
///   private String work;
/// }
/// ```
class Email extends Constraint {
  /// Creates the `@Email()` constraint.
  const Email({
    this.regexp = '.*',
    this.flags = const [],
    super.message,
    super.groups,
  });

  /// An additional pattern the whole address must match (`.*`: any).
  final String regexp;

  /// How [regexp] is matched.
  final List<PatternFlag> flags;

  static const _atom = r"[a-z0-9!#$%&'*+/=?^_`{|}~\u0080-￿-]";
  static const _quotedAtom =
      r"(?:[a-z0-9!#$%&'*.(),<>\[\]:; @+/=?^_`{|}~\u0080-￿-]|\\\\|"
      r'\\")';
  static const _word = '(?:$_atom+|"$_quotedAtom+")';
  static final _localPart = RegExp(
    '^$_word(?:\\.$_word)*\$',
    caseSensitive: false,
  );
  static final _label = RegExp(
    r"^[a-z0-9!#$%&'*+/=?^_`{|}~\u0080-￿]"
    r"(?:[a-z0-9!#$%&'*+/=?^_`{|}~\u0080-￿-]*"
    r"[a-z0-9!#$%&'*+/=?^_`{|}~\u0080-￿])?$",
    caseSensitive: false,
  );
  static final _ipLiteral = RegExp(
    r'^\[(?:[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|IPv6:'
    r'(?:([0-9a-f]{1,4}:){7,7}[0-9a-f]{1,4}|([0-9a-f]{1,4}:){1,7}:|'
    r'([0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}|'
    r'([0-9a-f]{1,4}:){1,5}(:[0-9a-f]{1,4}){1,2}|'
    r'([0-9a-f]{1,4}:){1,4}(:[0-9a-f]{1,4}){1,3}|'
    r'([0-9a-f]{1,4}:){1,3}(:[0-9a-f]{1,4}){1,4}|'
    r'([0-9a-f]{1,4}:){1,2}(:[0-9a-f]{1,4}){1,5}|'
    r'[0-9a-f]{1,4}:((:[0-9a-f]{1,4}){1,6})|:((:[0-9a-f]{1,4}){1,7}|:)|'
    r'fe80:(:[0-9a-f]{0,4}){0,4}%[0-9a-z]{1,}|'
    r'::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}'
    r'[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|'
    r'([0-9a-f]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.)'
    r'{3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])))\]$',
    caseSensitive: false,
  );

  @override
  String get name => 'Email';

  @override
  String get defaultMessage => 'must be a well-formed email address';

  @override
  Map<String, Object?> get attributes => {'flags': flags, 'regexp': regexp};

  @override
  bool isValid(Object? value) {
    if (value == null || value == '') {
      return true;
    }
    final text = '$value';
    final at = text.lastIndexOf('@');
    if (at < 0) {
      return false;
    }
    final local = text.substring(0, at);
    final domain = text.substring(at + 1);
    if (local.length > 64 || !_localPart.hasMatch(local)) {
      return false;
    }
    if (!_isValidDomain(domain)) {
      return false;
    }
    return (regexp == '.*' && flags.isEmpty) || _fullMatch(regexp, flags, text);
  }

  // Hibernate's DomainNameUtil: a domain name (IDN labels of at most 63
  // characters) or an IP address literal.
  static bool _isValidDomain(String domain) {
    if (domain.isEmpty || domain.length > 255 || domain.endsWith('.')) {
      return false;
    }
    if (domain.startsWith('[')) {
      return _ipLiteral.hasMatch(domain);
    }
    return domain
        .split('.')
        .every((label) => label.length <= 63 && _label.hasMatch(label));
  }
}

/// At most [integer] integer digits and [fraction] fraction digits, like
/// Hibernate Validator's `@Digits`.
///
/// Numbers and `BigInt`s are counted without trailing zeros (`1.50` has one
/// fraction digit, `1000` four integer digits); numeric strings as written
/// (`'1.50'` has two, like `new BigDecimal("1.50")`), and a string that is
/// not a number fails. `null` and other value types are valid.
///
/// ```dart
/// @Introspected()
/// class Invoice {
///   @Digits(integer: 6, fraction: 2)
///   double total = 0;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Invoice {
///   @Digits(integer = 6, fraction = 2)
///   private BigDecimal total;
/// }
/// ```
class Digits extends Constraint {
  /// Creates a `@Digits` constraint with the maximum digit counts.
  const Digits({
    required this.integer,
    required this.fraction,
    super.message,
    super.groups,
  });

  /// Maximum number of integer digits.
  final int integer;

  /// Maximum number of fraction digits.
  final int fraction;

  @override
  String get name => 'Digits';

  @override
  String get defaultMessage =>
      'numeric value out of bounds (<{integer} digits>.<{fraction} digits> expected)';

  @override
  Map<String, Object?> get attributes => {
    'fraction': fraction,
    'integer': integer,
  };

  @override
  bool isValid(Object? value) {
    final _Decimal? number;
    switch (value) {
      case final String text:
        number = _Decimal.parse(text);
      case num() || BigInt():
        number = _Decimal.of(value)?.stripTrailingZeros();
      default:
        return true;
    }
    if (number == null) {
      return false;
    }
    final integerDigits = number.precision - number.scale;
    final fractionDigits = number.scale < 0 ? 0 : number.scale;
    return integerDigits <= integer && fractionDigits <= fraction;
  }
}

/// The annotated value must be `true`; `null` is valid.
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @AssertTrue(message: 'terms must be accepted')
///   bool acceptedTerms = false;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @AssertTrue(message = "terms must be accepted")
///   private boolean acceptedTerms;
/// }
/// ```
class AssertTrue extends Constraint {
  /// Creates the `@AssertTrue()` constraint.
  const AssertTrue({super.message, super.groups});

  @override
  String get name => 'AssertTrue';

  @override
  String get defaultMessage => 'must be true';

  @override
  bool isValid(Object? value) => value == null || value == true;
}

/// The annotated value must be `false`; `null` is valid.
///
/// ```dart
/// @Introspected()
/// class Account {
///   @AssertFalse()
///   bool locked = false;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Account {
///   @AssertFalse
///   private boolean locked;
/// }
/// ```
class AssertFalse extends Constraint {
  /// Creates the `@AssertFalse()` constraint.
  const AssertFalse({super.message, super.groups});

  @override
  String get name => 'AssertFalse';

  @override
  String get defaultMessage => 'must be false';

  @override
  bool isValid(Object? value) => value == null || value == false;
}

// The sign of [value] − now for the date constraints; `null` for values
// that are not `DateTime`s (valid). A `DateTime` without a time of day
// (midnight to the microsecond) is a date and is compared by day, like a
// `LocalDate`: today is neither past nor future. Other values are compared
// as instants.
int? _compareToNow(Object? value, DateTime now) {
  if (value is! DateTime) {
    return null;
  }
  final isDate =
      value.hour == 0 &&
      value.minute == 0 &&
      value.second == 0 &&
      value.millisecond == 0 &&
      value.microsecond == 0;
  if (!isDate) {
    return value.compareTo(now).sign;
  }
  final today = value.isUtc ? now.toUtc() : now.toLocal();
  return switch (value.year.compareTo(today.year)) {
    0 => switch (value.month.compareTo(today.month)) {
      0 => value.day.compareTo(today.day).sign,
      final month => month.sign,
    },
    final year => year.sign,
  };
}

/// A `DateTime` in the past, like Jakarta's `@Past`.
///
/// A `DateTime` without a time of day (`DateTime(2026, 5, 1)`, what
/// `DateTime.parse('2026-05-01')` gives) is a date compared by day, like a
/// `LocalDate`: today is not in the past. "Now" comes from the validator's
/// `ClockProvider`. `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Person {
///   @Past()
///   DateTime? birthday;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Person {
///   @Past
///   private LocalDate birthday;
/// }
/// ```
class Past extends Constraint {
  /// Creates the `@Past()` constraint.
  const Past({super.message, super.groups});

  @override
  String get name => 'Past';

  @override
  String get defaultMessage => 'must be a past date';

  @override
  bool isValid(Object? value) => _valid(value, DateTime.now());

  @override
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      _valid(value, context.clockProvider.now());

  bool _valid(Object? value, DateTime now) {
    final sign = _compareToNow(value, now);
    return sign == null || sign < 0;
  }
}

/// A `DateTime` in the past or the present, like Jakarta's
/// `@PastOrPresent`; dates without a time of day are compared by day (see
/// [Past]).
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Payment {
///   @PastOrPresent()
///   DateTime? paidAt;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Payment {
///   @PastOrPresent
///   private Instant paidAt;
/// }
/// ```
class PastOrPresent extends Constraint {
  /// Creates the `@PastOrPresent()` constraint.
  const PastOrPresent({super.message, super.groups});

  @override
  String get name => 'PastOrPresent';

  @override
  String get defaultMessage => 'must be a date in the past or in the present';

  @override
  bool isValid(Object? value) => _valid(value, DateTime.now());

  @override
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      _valid(value, context.clockProvider.now());

  bool _valid(Object? value, DateTime now) {
    final sign = _compareToNow(value, now);
    return sign == null || sign <= 0;
  }
}

/// A `DateTime` in the future; error code `Future` (renamed: `Future` is a
/// Dart core type). Dates without a time of day are compared by day (see
/// [Past]).
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Booking {
///   @FutureDate()
///   DateTime? checkIn;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Booking {
///   @Future
///   private LocalDate checkIn;
/// }
/// ```
class FutureDate extends Constraint {
  /// Creates the `@FutureDate()` constraint.
  const FutureDate({super.message, super.groups});

  @override
  String get name => 'Future';

  @override
  String get defaultMessage => 'must be a future date';

  @override
  bool isValid(Object? value) => _valid(value, DateTime.now());

  @override
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      _valid(value, context.clockProvider.now());

  bool _valid(Object? value, DateTime now) {
    final sign = _compareToNow(value, now);
    return sign == null || sign > 0;
  }
}

/// A `DateTime` in the present or the future, like Jakarta's
/// `@FutureOrPresent`; dates without a time of day are compared by day
/// (today is present, see [Past]).
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Reminder {
///   @FutureOrPresent()
///   DateTime? dueOn;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Reminder {
///   @FutureOrPresent
///   private LocalDate dueOn;
/// }
/// ```
class FutureOrPresent extends Constraint {
  /// Creates the `@FutureOrPresent()` constraint.
  const FutureOrPresent({super.message, super.groups});

  @override
  String get name => 'FutureOrPresent';

  @override
  String get defaultMessage => 'must be a date in the present or in the future';

  @override
  bool isValid(Object? value) => _valid(value, DateTime.now());

  @override
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      _valid(value, context.clockProvider.now());

  bool _valid(Object? value, DateTime now) {
    final sign = _compareToNow(value, now);
    return sign == null || sign >= 0;
  }
}
