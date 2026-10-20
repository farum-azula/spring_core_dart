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

  /// [message] or [defaultMessage] with attributes interpolated.
  ///
  /// ```dart
  /// const Size(max: 20).interpolatedMessage();
  /// // 'size must be between 0 and 20'
  /// ```
  String interpolatedMessage() {
    var text = message ?? defaultMessage;
    attributes.forEach(
      (key, value) => text = text.replaceAll('{$key}', '$value'),
    );
    return text;
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

/// Not null and with at least one non-whitespace character.
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
      value != null && value.toString().trim().isNotEmpty;
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

/// A number greater than or equal to [value]; `null` and non-numbers are
/// valid.
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
  bool isValid(Object? value) => value is! num || value >= this.value;
}

/// A number less than or equal to [value]; `null` and non-numbers are
/// valid.
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
  bool isValid(Object? value) => value is! num || value <= this.value;
}

/// A number strictly greater than 0; `null` and non-numbers are valid.
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
  bool isValid(Object? value) => value is! num || value > 0;
}

/// A number greater than or equal to 0; `null` and non-numbers are valid.
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
  bool isValid(Object? value) => value is! num || value >= 0;
}

/// A number strictly less than 0; `null` and non-numbers are valid.
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
  bool isValid(Object? value) => value is! num || value < 0;
}

/// A number less than or equal to 0; `null` and non-numbers are valid.
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
  bool isValid(Object? value) => value is! num || value <= 0;
}

/// A string fully matching [regexp]; error code `Pattern` (renamed: `Pattern`
/// is a Dart core type).
///
/// The whole value must match (the pattern is anchored); `null` is valid.
///
/// ```dart
/// @Introspected()
/// class Address {
///   @Matches(r'\d{5}', message: 'must be 5 digits')
///   String? zip;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Address {
///   @Pattern(regexp = "\\d{5}", message = "must be 5 digits")
///   private String zip;
/// }
/// ```
class Matches extends Constraint {
  /// Creates a `@Matches` constraint for the regular expression [regexp].
  const Matches(
    this.regexp, {
    this.caseSensitive = true,
    super.message,
    super.groups,
  });

  /// The regular expression the whole value must match.
  final String regexp;

  /// Whether matching is case-sensitive (Jakarta's
  /// `flags = Pattern.Flag.CASE_INSENSITIVE` when `false`).
  final bool caseSensitive;

  @override
  String get name => 'Pattern';

  @override
  String get defaultMessage => 'must match "{regexp}"';

  @override
  Map<String, Object?> get attributes => {'regexp': regexp};

  @override
  bool isValid(Object? value) =>
      value == null ||
      RegExp('^(?:$regexp)\$', caseSensitive: caseSensitive).hasMatch('$value');
}

/// A well-formed email address (pragmatic check like Hibernate Validator).
///
/// `null` and the empty string are valid; combine with [NotBlank] to
/// require an address.
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotNull()
///   @Email()
///   String? email;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Signup {
///   @NotNull
///   @Email
///   private String email;
/// }
/// ```
class Email extends Constraint {
  /// Creates the `@Email()` constraint.
  const Email({super.message, super.groups});

  static final _pattern = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*$',
  );

  @override
  String get name => 'Email';

  @override
  String get defaultMessage => 'must be a well-formed email address';

  @override
  bool isValid(Object? value) {
    if (value == null || value == '') {
      return true;
    }
    final text = '$value';
    // The pattern allows dots in the local part; reject the forms RFC 5322
    // forbids (consecutive or leading dots) separately.
    return _pattern.hasMatch(text) &&
        !text.contains('..') &&
        !text.startsWith('.');
  }
}

/// At most [integer] integer digits and [fraction] fraction digits.
///
/// Accepts numbers and numeric strings; `null` is valid.
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
    if (value == null) {
      return true;
    }
    final text = (value is num ? value.abs() : '$value')
        .toString()
        .replaceFirst('-', '');
    final parts = text.split('.');
    // Leading zeros of the integer part and trailing zeros of the fraction
    // are not significant (`007.50` has 1 integer and 1 fraction digit).
    final integerDigits = parts.first
        .replaceFirst(RegExp('^0+(?=.)'), '')
        .length;
    final fractionDigits = parts.length > 1
        ? parts[1].replaceFirst(RegExp(r'0+$'), '').length
        : 0;
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

// Date constraints only check `DateTime` values; others count as valid.
DateTime? _date(Object? value) => value is DateTime ? value : null;

/// A `DateTime` in the past; error code `Past`.
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Person {
///   @PastDate()
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
class PastDate extends Constraint {
  /// Creates the `@PastDate()` constraint.
  const PastDate({super.message, super.groups});

  @override
  String get name => 'Past';

  @override
  String get defaultMessage => 'must be a past date';

  @override
  bool isValid(Object? value) => _date(value)?.isBefore(DateTime.now()) ?? true;
}

/// A `DateTime` in the past or now; error code `PastOrPresent`.
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Payment {
///   @PastOrPresentDate()
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
class PastOrPresentDate extends Constraint {
  /// Creates the `@PastOrPresentDate()` constraint.
  const PastOrPresentDate({super.message, super.groups});

  @override
  String get name => 'PastOrPresent';

  @override
  String get defaultMessage => 'must be a date in the past or in the present';

  @override
  bool isValid(Object? value) =>
      !(_date(value)?.isAfter(DateTime.now()) ?? false);
}

/// A `DateTime` in the future; error code `Future` (renamed: `Future` is a
/// Dart core type).
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
  bool isValid(Object? value) => _date(value)?.isAfter(DateTime.now()) ?? true;
}

/// A `DateTime` now or in the future; error code `FutureOrPresent`.
///
/// `null` and non-`DateTime` values are valid.
///
/// ```dart
/// @Introspected()
/// class Reminder {
///   @FutureOrPresentDate()
///   DateTime? dueAt;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Reminder {
///   @FutureOrPresent
///   private Instant dueAt;
/// }
/// ```
class FutureOrPresentDate extends Constraint {
  /// Creates the `@FutureOrPresentDate()` constraint.
  const FutureOrPresentDate({super.message, super.groups});

  @override
  String get name => 'FutureOrPresent';

  @override
  String get defaultMessage => 'must be a date in the present or in the future';

  // A one-second tolerance keeps "now" (captured slightly earlier by the
  // caller) counting as present.
  @override
  bool isValid(Object? value) =>
      !(_date(value)
              ?.isBefore(DateTime.now().subtract(const Duration(seconds: 1))) ??
          false);
}
