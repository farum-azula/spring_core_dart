import 'package:spring_core_dart/src/validation/message_escapes.dart';

/// The validation group of every constraint declared without `groups`.
///
/// Groups let one class carry rules for different situations. A group is
/// just a type, usually an empty `abstract final class OnUpdate {}`, named
/// in a constraint's `groups` and in the groups a validation asks for.
/// Validating without groups checks only this group; to check other groups
/// as well as the ordinary rules, list [Default] next to them.
///
/// ```dart
/// // An update checks the ordinary rules and the update ones.
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

/// The base class of every validation rule written as an annotation, such
/// as `@NotBlank()` or `@Min(18)`, and the class to extend for your own.
///
/// A constraint is a const object put on a property of an `@Introspected`
/// class, on the class itself (to compare properties), or on a method
/// parameter or method of a `@Validated()` bean. The validator calls
/// [isValid] (through [isValidWithContext]) with the value; when it
/// returns `false` it reports a violation with [name] as error code and
/// [message] (or [defaultMessage]) as text.
///
/// Write a subclass for a rule the built-in constraints do not cover, so
/// it can be reused as an annotation and its errors get message codes like
/// the others. Like Jakarta's, most constraints accept `null`; add
/// [NotNull] to require a value.
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
  /// A constraint with an optional custom [message] and the [groups] it
  /// belongs to (none: [Default]).
  const Constraint({this.message, this.groups = const []});

  /// The text of a violation instead of [defaultMessage]; `null` keeps the
  /// default.
  ///
  /// `{min}`-style placeholders take the constraint's [attributes],
  /// `${validatedValue}` the invalid value, and `{some.key}` a message of
  /// the validator's `validationMessageSource`. This text is the violation
  /// message and the field error's default message; a `messages.properties`
  /// key such as `NotBlank.signup.name` still wins when errors are shown
  /// through a message source.
  final String? message;

  /// The validation groups the constraint belongs to, such as `[OnUpdate]`;
  /// it is only checked when one of them is asked for. Empty means
  /// [Default].
  final List<Type> groups;

  /// The error code of a violation, such as `NotBlank`: the start of the
  /// message codes (`NotBlank.signup.name`, ..., `NotBlank`) and the
  /// Jakarta name of the constraint. Custom constraints usually return
  /// their class name.
  String get name;

  /// The text of a violation when [message] is not set, with the same
  /// placeholders, such as `size must be between {min} and {max}`.
  String get defaultMessage;

  /// The settings of the constraint by name, such as `{'max': 20, 'min':
  /// 0}`: they fill the `{max}` placeholders of messages and, sorted by
  /// name, become the arguments `{1}`, `{2}`, ... of field errors. Empty by
  /// default; override it when a custom constraint has settings.
  Map<String, Object?> get attributes => const {};

  /// Whether [value] satisfies the constraint; the method a custom
  /// constraint implements.
  ///
  /// For a property constraint [value] is the property value (often
  /// `null`: return `true` for it unless the rule is about presence); for a
  /// class-level constraint it is the annotated object itself.
  bool isValid(Object? value);

  /// Whether [value] satisfies the constraint, with access to the
  /// validation [context]; the method `BeanValidator` calls. By default it
  /// returns [isValid].
  ///
  /// Override it to read the validator's clock or to report violations
  /// yourself, for example on one property of a class-level constraint so
  /// the error appears next to that form field. Jakarta's
  /// `ConstraintValidator.isValid(value, context)`.
  ///
  /// ```dart
  /// // Report a password mismatch on the `confirm` field.
  /// @override
  /// bool isValidWithContext(
  ///     Object? value, ConstraintValidatorContext context) {
  ///   if (isValid(value)) return true;
  ///   context
  ///     ..disableDefaultConstraintViolation()
  ///     ..buildConstraintViolationWithTemplate(
  ///         context.defaultConstraintMessageTemplate)
  ///         .addPropertyNode('confirm')
  ///         .addConstraintViolation();
  ///   return false;
  /// }
  /// ```
  bool isValidWithContext(Object? value, ConstraintValidatorContext context) =>
      isValid(value);

  /// [message], or [defaultMessage], with the `{attribute}` placeholders
  /// filled in; message keys and `${...}` expressions stay, since only the
  /// validator can resolve them.
  ///
  /// ```dart
  /// const Size(max: 20).interpolatedMessage();
  /// // 'size must be between 0 and 20'
  /// ```
  String interpolatedMessage() => interpolate(message ?? defaultMessage);

  /// [template] with its `{attribute}` placeholders replaced by the values
  /// of [attributes]; other placeholders and `${...}` expressions stay, and
  /// the escapes `\{`, `\}`, `\$`, `\\` become the literal characters.
  ///
  /// ```dart
  /// const Size(max: 20).interpolate('at most {max}'); // 'at most 20'
  /// const Size(max: 20).interpolate(r'\{max} is {max}'); // '{max} is 20'
  /// ```
  String interpolate(String template) => revealMessageEscapes(
    interpolateAttributes(hideMessageEscapes(template), attributes),
  );

  /// Whether the constraint can check a value of this type at all; [value]
  /// is never `null`. `@Size` supports strings, collections and maps, not
  /// an `int`.
  ///
  /// When it returns `false`, `BeanValidator` throws an
  /// [UnexpectedTypeException] instead of calling [isValid]: the
  /// declaration is wrong, not the value (Hibernate Validator finds no
  /// `ConstraintValidator` for the type). Returns `true` by default;
  /// override it in a custom constraint that only makes sense for some
  /// types.
  bool supports(Object value) => true;

  /// Throws a [ConstraintDeclarationException] when the constraint's own
  /// settings are invalid: `Size(min: -1)`, `min > max`, a malformed
  /// regular expression. Does nothing by default.
  ///
  /// `BeanValidator` calls it once, before the first use of each
  /// constraint, as Hibernate Validator does when it initializes a
  /// validator. Override it when a custom constraint has settings.
  ///
  /// ```dart
  /// const Size(min: 5, max: 2).checkParameters(); // throws
  /// ```
  void checkParameters() {}

  /// Whether the constraint is checked when a validation asks for the
  /// [requested] groups: when one of its [groups] is requested.
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

/// Where the date constraints (`@Past()`, `@FutureDate()`, ...) get the
/// current time.
///
/// The validator uses [DefaultClockProvider], the system clock. Give a
/// `BeanValidator` another one to make date checks repeatable in tests, or
/// to use a server-wide clock. Jakarta's `ClockProvider`; it returns the
/// time itself, since Dart has no `Clock` type.
///
/// ```dart
/// // Tests run on a fixed date.
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
  /// The current time, read once per date constraint check.
  DateTime now();
}

/// The [ClockProvider] of the system clock, `DateTime.now()`; the default
/// of `BeanValidator`.
final class DefaultClockProvider implements ClockProvider {
  /// The system clock.
  const DefaultClockProvider();

  @override
  DateTime now() => DateTime.now();
}

/// The help a constraint gets while it checks one value: the validator's
/// clock, and a way to report violations other than the default one.
///
/// The validator creates one per check and passes it to
/// [Constraint.isValidWithContext]. Only custom constraints that override
/// that method use it, mostly to put a class-level violation on a property
/// or to report several problems with their own messages. Jakarta's
/// `ConstraintValidatorContext`.
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
  /// The validator creates it; build one yourself only to test a
  /// constraint.
  ConstraintValidatorContext({
    required this.defaultConstraintMessageTemplate,
    this.clockProvider = const DefaultClockProvider(),
  });

  /// The validator's clock; date constraints read "now" from it.
  final ClockProvider clockProvider;

  /// The constraint's message before interpolation: its `message`, else
  /// its default. Pass it to [buildConstraintViolationWithTemplate] to move
  /// the usual message to another property.
  final String defaultConstraintMessageTemplate;

  bool _defaultDisabled = false;
  final _violations = <({String messageTemplate, List<String> nodes})>[];

  /// Whether [disableDefaultConstraintViolation] was called; the validator
  /// reads it after the check.
  bool get defaultConstraintViolationDisabled => _defaultDisabled;

  /// The violations added with [buildConstraintViolationWithTemplate], in
  /// order: their message template and property nodes. The validator reads
  /// them after the check.
  List<({String messageTemplate, List<String> nodes})> get customViolations =>
      List.unmodifiable(_violations);

  /// Drops the violation the validator would report when the constraint
  /// fails, so only the ones built with
  /// [buildConstraintViolationWithTemplate] are reported.
  void disableDefaultConstraintViolation() => _defaultDisabled = true;

  /// Starts an extra violation with [messageTemplate], interpolated like a
  /// constraint message (`{key}`, `{attribute}`). Finish it with
  /// [ConstraintViolationBuilder.addConstraintViolation], or it is not
  /// reported.
  ConstraintViolationBuilder buildConstraintViolationWithTemplate(
    String messageTemplate,
  ) => ConstraintViolationBuilder._(this, messageTemplate);
}

/// A violation being put together inside a constraint: its message is
/// set, a property path may be added, and [addConstraintViolation]
/// reports it.
///
/// It comes from
/// [ConstraintValidatorContext.buildConstraintViolationWithTemplate] and
/// is never created directly. Jakarta's `ConstraintViolationBuilder`.
///
/// ```dart
/// // The mismatch is shown next to the `confirm` field.
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

  /// Puts the violation on the property [name] of the validated object,
  /// such as `confirm`; call it again to go deeper (`address`, then
  /// `city`). Without it the violation stays on the value itself.
  ConstraintViolationBuilder addPropertyNode(String name) {
    _nodes.add(name);
    return this;
  }

  /// Reports the violation; returns the context, to build another one.
  ConstraintValidatorContext addConstraintViolation() {
    _context._violations.add((
      messageTemplate: _template,
      nodes: List.unmodifiable(_nodes),
    ));
    return _context;
  }
}

/// The base of the exceptions that mean validation itself is set up
/// wrongly: a bad constraint declaration or group definition, never an
/// invalid value.
///
/// Invalid values are reported as violations or errors, not thrown. One of
/// these is a programming error to fix in the code; you do not normally
/// catch it, except to report it. Jakarta's `ValidationException`.
///
/// ```dart
/// try {
///   validator.validateObject(form);
/// } on ValidationException catch (e) {
///   log.error(e.message); // a wrong declaration, not an invalid form
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (jakarta.validation.ValidationException e) { ... }
/// ```
class ValidationException implements Exception {
  /// An exception explaining the problem in [message].
  const ValidationException(this.message);

  /// What is wrong and where, for the developer.
  final String message;

  @override
  // Subclasses show their own name.
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// Thrown when a constraint is declared wrongly: invalid settings
/// (`Size(min: -1)`, `min > max`, a malformed regular expression),
/// `@ConvertGroup` without `@Valid()`, or `@Each` on a value that is not a
/// collection. Jakarta's `ConstraintDeclarationException`.
///
/// ```dart
/// // @Size(min: 5, max: 2) String name = '';
/// validator.validateObject(form); // throws ConstraintDeclarationException
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (jakarta.validation.ConstraintDeclarationException e) { ... }
/// ```
class ConstraintDeclarationException extends ValidationException {
  /// An exception explaining the wrong declaration in [message].
  const ConstraintDeclarationException(super.message);
}

/// Thrown when a constraint meets a value of a type it cannot check:
/// `@Size` on an `int`, `@NotBlank` on a `List`. Jakarta's
/// `UnexpectedTypeException`.
///
/// The generator already rejects such declarations at build time when the
/// declared type is known; this catches `dynamic` and `Object` properties
/// and hand-written metadata at run time.
///
/// ```dart
/// // @Size(max: 3) Object age = 42;
/// validator.validateObject(form); // throws UnexpectedTypeException
/// ```
///
/// Spring (Java):
/// ```java
/// // HV000030: No validator could be found for constraint
/// // 'jakarta.validation.constraints.Size' validating type 'java.lang.Integer'
/// ```
class UnexpectedTypeException extends ConstraintDeclarationException {
  /// An exception naming the constraint, the type and the path in
  /// [message].
  const UnexpectedTypeException(super.message);
}

/// Thrown when a group sequence is defined wrongly: a cycle, `Default` in
/// a class's `@GroupSequence`, the class missing from it, or [Default] as
/// a key of `BeanValidator.groupSequences`. Jakarta's
/// `GroupDefinitionException`.
///
/// ```dart
/// // @GroupSequence([Default, Strict]) class Form { ... }
/// validator.validateObject(form); // throws GroupDefinitionException
/// ```
///
/// Spring (Java):
/// ```java
/// } catch (jakarta.validation.GroupDefinitionException e) { ... }
/// ```
class GroupDefinitionException extends ValidationException {
  /// An exception explaining the wrong definition in [message].
  const GroupDefinitionException(super.message);
}

/// A class annotation that checks the class's rules in stages: the groups
/// in [value] are checked in order, and checking stops at the first group
/// with a violation.
///
/// Use it when some rules are expensive (a database lookup) or pointless
/// while simpler ones fail: they then run only on otherwise valid data. It
/// replaces the [Default] group of the class, so every ordinary
/// validation follows the sequence. The class itself stands for its
/// ordinary constraints and must be listed; [Default] must not be. Jakarta's
/// `@GroupSequence` on a bean class.
///
/// A sequence used as a group of its own (Jakarta's `@GroupSequence` on a
/// group interface) is given to `BeanValidator(groupSequences: ...)`
/// instead, since a Dart group type cannot carry annotations that are read
/// at run time.
///
/// ```dart
/// // The stock lookup only runs when the SKU is filled in.
/// abstract final class Expensive {}
///
/// @Introspected()
/// @GroupSequence([Order, Expensive])
/// class Order {
///   @NotBlank()
///   String sku = '';
///
///   // Only checked when the Default constraints of Order pass.
///   @StockAvailable(groups: [Expensive])
///   String warehouse = '';
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @GroupSequence({Order.class, Expensive.class})
/// class Order { ... }
/// ```
class GroupSequence {
  /// A sequence of the groups [value].
  const GroupSequence(this.value);

  /// The groups, in the order they are checked; the annotated class stands
  /// for its own ordinary constraints.
  final List<Type> value;
}

/// An annotation next to `@Valid()` that checks the nested value with
/// another group: when the outer validation runs group [from], the nested
/// value is checked with group [to].
///
/// Use it when a nested object's rules depend on its owner's situation,
/// for example a car's driver whose licence only matters for the car's
/// checks. Without `@Valid()` it is a declaration error. Jakarta's
/// `@ConvertGroup`.
///
/// ```dart
/// // The ordinary check of a Car checks its driver's DriverChecks rules.
/// abstract final class DriverChecks {}
///
/// @Introspected()
/// class Car {
///   @Valid()
///   @ConvertGroup(to: DriverChecks) // from: Default
///   Driver? driver;
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Valid
/// @ConvertGroup(from = Default.class, to = DriverChecks.class)
/// private Driver driver;
/// ```
class ConvertGroup {
  /// Turns the group [from] (by default [Default]) into [to] for the
  /// nested value; one conversion per [from] group.
  const ConvertGroup({required this.to, this.from = Default});

  /// The group of the outer validation that is converted.
  final Type from;

  /// The group the nested value is checked with instead.
  final Type to;
}

/// An annotation that checks every element of a list or set, or every
/// value of a map, against [constraints].
///
/// Use it for rules about the items rather than the collection: each
/// answer non-blank, each score at least 0. Jakarta writes these on the
/// type argument (`List<@NotBlank String>`); Dart has no annotations
/// there. A `null` collection is skipped, and a value that is not a
/// collection or map throws a [ConstraintDeclarationException].
///
/// A list element is reported as `answers[1].<list element>` (field error
/// on `answers[1]`), another iterable's as `tags[].<iterable element>`,
/// and a map value as `scores[math].<map value>`. Use [EachKey] for map
/// keys, and `@Valid()` to check the constraints inside element objects.
///
/// ```dart
/// // Short, non-blank answers, and no negative scores.
/// @Introspected()
/// class Survey {
///   @Each([NotBlank(), Size(max: 20)])
///   List<String> answers = [];
///
///   @Each([Min(0)])
///   Map<String, int> scores = {};
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// class Survey {
///   private List<@NotBlank @Size(max = 20) String> answers;
///   private Map<String, @Min(0) Integer> scores;
/// }
/// ```
class Each {
  /// Checks [constraints] on every element or map value.
  const Each(this.constraints);

  /// The constraints each element must meet, such as
  /// `[NotBlank(), Size(max: 20)]`.
  final List<Constraint> constraints;
}

/// An annotation that checks every key of a map against [constraints].
///
/// Use it when the keys are user input, such as the names of a score
/// table. A `null` map is skipped; a value that is not a map throws a
/// [ConstraintDeclarationException]. A key is reported as
/// `scores<K>[key].<map key>` (field error on `scores[key]`). Jakarta's
/// container element constraint on a map key
/// (`Map<@NotBlank String, Integer>`).
///
/// ```dart
/// // Subject names of at most 10 characters.
/// @Introspected()
/// class Survey {
///   @EachKey([Size(max: 10)])
///   Map<String, int> scores = {};
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// private Map<@Size(max = 10) String, Integer> scores;
/// ```
class EachKey {
  /// Checks [constraints] on every key of the map.
  const EachKey(this.constraints);

  /// The constraints each key must meet.
  final List<Constraint> constraints;
}

/// An annotation that asks for the constraints inside an object to be
/// checked: of a nested object, of the objects in a list, set or map, or
/// of a request body or method argument.
///
/// Constraints are not checked inside a property by default; `@Valid()`
/// says "go in here". In the web starter, `@Valid()` on a `@RequestBody`
/// parameter checks the body and answers a 400 when it is invalid. On a
/// parameter or method of a `@Validated()` bean it checks the argument or
/// the result.
///
/// Errors inside a list element are reported as `items[0].sku`, inside
/// another iterable (a set) as `items[].sku`, inside a map value as
/// `byKey[key].sku`. `null` values are skipped. An object reached on
/// several paths is checked on each, but one that contains itself is not
/// entered again. [ConvertGroup] changes the groups of the nested check.
/// Jakarta's `@Valid`.
///
/// ```dart
/// // An order is only valid with a valid address and valid items.
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
  /// The `@Valid()` annotation; it has no settings.
  const Valid();
}

bool _isSized(Object value) =>
    value is String || value is Iterable || value is Map;

bool _isNumeric(Object value) =>
    value is num || value is BigInt || value is String;

// Hibernate Validator's checks of the `@Size` bounds.
void _checkBounds(int min, int max) {
  if (min < 0) {
    throw const ConstraintDeclarationException(
      'The min parameter cannot be negative.',
    );
  }
  if (max < 0) {
    throw const ConstraintDeclarationException(
      'The max parameter cannot be negative.',
    );
  }
  if (max < min) {
    throw const ConstraintDeclarationException(
      'The length cannot be negative.',
    );
  }
}

void _checkRegExp(String regexp, List<PatternFlag> flags) {
  try {
    _fullMatch(regexp, flags, '');
  } on FormatException catch (error) {
    throw ConstraintDeclarationException(
      'Invalid regular expression "$regexp": ${error.message}',
    );
  }
}

// Length of strings, collections and maps; `null` for anything else so
// that size checks ignore unsupported values (like Jakarta).
int? _length(Object? value) => switch (value) {
  String() => value.length,
  Iterable<Object?>() => value.length,
  Map<Object?, Object?>() => value.length,
  _ => null,
};

/// A constraint that requires a value: `null` fails, anything else passes.
///
/// Most other constraints let `null` pass, so combine it with them when
/// the value is required, as in `@NotNull() @Email()`. For text that must
/// not be empty either, use [NotBlank]. In a class with non-nullable
/// fields it matters for nullable ones and for input that may be missing.
///
/// ```dart
/// // The email may be missing in the JSON, but not in a valid signup.
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
  /// The constraint; [message] replaces `must not be null`, and [groups]
  /// limits it to those validation groups.
  const NotNull({super.message, super.groups});

  @override
  String get name => 'NotNull';

  @override
  String get defaultMessage => 'must not be null';

  @override
  bool isValid(Object? value) => value != null;
}

/// A constraint that requires the value to be `null`, usually in one
/// validation group only.
///
/// The typical use is an `id` that a client must not send when creating
/// a record, but must send on update. Its error code is Jakarta's `Null`;
/// the class has another name because `Null` is a Dart core type.
///
/// ```dart
/// // A new user gets its id from the database, not from the client.
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
  /// The constraint; [message] replaces `must be null`, and [groups]
  /// limits it to those validation groups.
  const MustBeNull({super.message, super.groups});

  @override
  String get name => 'Null';

  @override
  String get defaultMessage => 'must be null';

  @override
  bool isValid(Object? value) => value == null;
}

/// A constraint that requires a string, list, set or map that is neither
/// `null` nor empty.
///
/// Use it for a collection that needs at least one entry, such as the
/// items of a cart. For text, [NotBlank] is usually better, since it also
/// rejects `'   '`. On a value of another type it is a declaration error:
/// the generator rejects it at build time, and the validator throws an
/// [UnexpectedTypeException].
///
/// ```dart
/// // A cart cannot be ordered empty.
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
  /// The constraint; [message] replaces `must not be empty`, and [groups]
  /// limits it to those validation groups.
  const NotEmpty({super.message, super.groups});

  @override
  String get name => 'NotEmpty';

  @override
  bool supports(Object value) => _isSized(value);

  @override
  String get defaultMessage => 'must not be empty';

  @override
  bool isValid(Object? value) => value != null && (_length(value) ?? 1) > 0;
}

/// A constraint that requires text with at least one visible character:
/// `null`, `''` and `'   '` fail.
///
/// The usual rule for required text fields: names, titles, comments.
/// "Visible" means a character above U+0020, as Hibernate Validator checks
/// it with Java's `String.trim()`: a no-break space counts as text,
/// control characters do not. Only for strings: on another type the
/// generator fails the build, and the validator throws an
/// [UnexpectedTypeException].
///
/// ```dart
/// // A name of only spaces is not a name.
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
  /// The constraint; [message] replaces `must not be blank`, and [groups]
  /// limits it to those validation groups.
  const NotBlank({super.message, super.groups});

  @override
  String get name => 'NotBlank';

  @override
  bool supports(Object value) => value is String;

  @override
  String get defaultMessage => 'must not be blank';

  @override
  bool isValid(Object? value) =>
      value != null && '$value'.codeUnits.any((unit) => unit > 0x20);
}

/// A constraint on the length of a string, or the number of entries of a
/// list, set or map: from [min] to [max], both included.
///
/// Use it for limits such as a name of 2 to 20 characters or at most 5
/// tags; the limits often mirror a database column. `null` passes (add
/// [NotNull] to require a value), and `Size(min: 1)` does not reject
/// `'  '` (use [NotBlank]). The arguments of a field error are
/// `[field, max, min]`, so a message such as `Size={0} has {2} to {1}
/// characters` can show the limits. On a value of another type the
/// generator fails the build and the validator throws an
/// [UnexpectedTypeException]; invalid limits throw a
/// [ConstraintDeclarationException].
///
/// In Flutter apps the class is exported as `SizeConstraint`, since
/// Flutter has a `Size` class of its own.
///
/// ```dart
/// // A display name of 2 to 20 characters.
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
  /// The constraint for a length from [min] to [max], both included; at
  /// least one of them is usually given. [message] replaces `size must be
  /// between {min} and {max}`, and [groups] limits it to those groups.
  const Size({
    this.min = 0,
    this.max = 0x7FFFFFFF,
    super.message,
    super.groups,
  });

  /// The smallest allowed length, included; `0` by default. Must not be
  /// negative.
  final int min;

  /// The largest allowed length, included; by default 2147483647 (Java's
  /// `Integer.MAX_VALUE`), so no limit. Must not be below [min].
  final int max;

  @override
  String get name => 'Size';

  @override
  bool supports(Object value) => _isSized(value);

  @override
  void checkParameters() {
    _checkBounds(min, max);
  }

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

  /// [text] parsed like Java's `new BigDecimal(text)`: `12`, `-1.50`,
  /// `1e3`; `null` when it is not a number.
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

  /// [value] as a decimal when it is a finite `num`, a `BigInt` or a
  /// numeric string; else `null`.
  static _Decimal? of(Object? value) => switch (value) {
    final int value => _Decimal(BigInt.from(value), 0),
    final double value when value.isFinite => parse('$value'),
    final BigInt value => _Decimal(value, 0),
    final String value => parse(value),
    _ => null,
  };

  int get signum => unscaled.sign;

  /// The number of digits of [unscaled], `1` for zero
  /// (`BigDecimal.precision()`).
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

/// A constraint that requires a number of at least [value].
///
/// Use it for lower limits such as an age of 18 or a quantity of 1. It
/// checks `int`, `double`, `BigInt` and numeric strings, compared exactly
/// as Hibernate Validator does; a string that is not a number fails, and
/// so does `double.nan`. `null` passes. The arguments of a field error are
/// `[field, value]`: `Min={0} must be at least {1}`. On a value of another
/// type the generator fails the build and the validator throws an
/// [UnexpectedTypeException].
///
/// ```dart
/// // Only adults may sign up.
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
  /// The constraint for numbers of at least [value]; [message] replaces
  /// `must be greater than or equal to {value}`, and [groups] limits it to
  /// those groups.
  const Min(this.value, {super.message, super.groups});

  /// The smallest allowed number, included; it must be finite.
  final num value;

  @override
  String get name => 'Min';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  void checkParameters() {
    _checkFinite(value);
  }

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

/// A constraint that requires a number of at most [value].
///
/// Use it for upper limits such as 100 items per order. It checks the
/// same values the same way as [Min]; `null` passes. The arguments of a
/// field error are `[field, value]`.
///
/// ```dart
/// // No more than 100 copies in one order.
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
  /// The constraint for numbers of at most [value]; [message] replaces
  /// `must be less than or equal to {value}`, and [groups] limits it to
  /// those groups.
  const Max(this.value, {super.message, super.groups});

  /// The largest allowed number, included; it must be finite.
  final num value;

  @override
  String get name => 'Max';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  void checkParameters() {
    _checkFinite(value);
  }

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

/// A constraint that requires a number above a decimal limit, or equal to
/// it when [inclusive].
///
/// Use it instead of [Min] when the limit has decimals, such as a price of
/// at least 0.01, or must be excluded (`inclusive: false`: more than 0).
/// The limit is a string (`'0.01'`) so it is exact; values are compared
/// exactly like [Min]'s, and `null` passes. The arguments of a field error
/// are `[field, inclusive, value]`.
///
/// ```dart
/// // Nothing is free: at least one cent.
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
  /// The constraint for numbers above [value] (or equal, when [inclusive]);
  /// [message] replaces the default message, and [groups] limits it to
  /// those groups.
  const DecimalMin(
    this.value, {
    this.inclusive = true,
    super.message,
    super.groups,
  });

  /// The limit, as a decimal string such as `'0.01'` or `'1e3'`; a string
  /// that is not a number throws a [ConstraintDeclarationException].
  final String value;

  /// Whether [value] itself passes; `true` by default.
  final bool inclusive;

  @override
  String get name => 'DecimalMin';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  void checkParameters() {
    _checkDecimal(value);
  }

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

/// A constraint that requires a number below a decimal limit, or equal to
/// it when [inclusive].
///
/// The counterpart of [DecimalMin], for limits such as "less than 100
/// percent". `null` passes. The arguments of a field error are
/// `[field, inclusive, value]`.
///
/// ```dart
/// // A discount below 100 percent.
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
  /// The constraint for numbers below [value] (or equal, when [inclusive]);
  /// [message] replaces the default message, and [groups] limits it to
  /// those groups.
  const DecimalMax(
    this.value, {
    this.inclusive = true,
    super.message,
    super.groups,
  });

  /// The limit, as a decimal string such as `'100'`; a string that is not
  /// a number throws a [ConstraintDeclarationException].
  final String value;

  /// Whether [value] itself passes; `true` by default.
  final bool inclusive;

  @override
  String get name => 'DecimalMax';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  void checkParameters() {
    _checkDecimal(value);
  }

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

void _checkDecimal(String value) {
  if (_Decimal.parse(value.trim()) == null) {
    throw ConstraintDeclarationException(
      '$value does not represent a valid BigDecimal format.',
    );
  }
}

void _checkFinite(num value) {
  if (!value.isFinite) {
    throw ConstraintDeclarationException('$value is not a finite number.');
  }
}

_Decimal _decimalBound(String value) =>
    _Decimal.parse(value.trim()) ??
    (throw ArgumentError.value(value, 'value', 'not a decimal number'));

/// A constraint that requires a number greater than 0.
///
/// Use it for prices, quantities and amounts where zero makes no sense. It
/// checks the same values the same way as [Min]; `null` passes.
///
/// ```dart
/// // A price must be above zero.
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
  /// The constraint; [message] replaces `must be greater than 0`, and
  /// [groups] limits it to those validation groups.
  const Positive({super.message, super.groups});

  @override
  String get name => 'Positive';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  String get defaultMessage => 'must be greater than 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign > 0;
  }
}

/// A constraint that requires a number of 0 or more.
///
/// Use it for counts and balances that may be zero but never negative. It
/// checks the same values as [Min]; `null` passes.
///
/// ```dart
/// // A balance may be empty, not overdrawn.
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
  /// The constraint; [message] replaces `must be greater than or equal to
  /// 0`, and [groups] limits it to those validation groups.
  const PositiveOrZero({super.message, super.groups});

  @override
  String get name => 'PositiveOrZero';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  String get defaultMessage => 'must be greater than or equal to 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign >= 0;
  }
}

/// A constraint that requires a number below 0.
///
/// Use it for amounts stored with a sign, such as refunds. It checks the
/// same values as [Min]; `null` passes.
///
/// ```dart
/// // A refund is booked as a negative amount.
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
  /// The constraint; [message] replaces `must be less than 0`, and [groups]
  /// limits it to those validation groups.
  const Negative({super.message, super.groups});

  @override
  String get name => 'Negative';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  String get defaultMessage => 'must be less than 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign < 0;
  }
}

/// A constraint that requires a number of 0 or less.
///
/// It checks the same values as [Min]; `null` passes.
///
/// ```dart
/// // A correction may only lower the stock.
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
  /// The constraint; [message] replaces `must be less than or equal to 0`,
  /// and [groups] limits it to those validation groups.
  const NegativeOrZero({super.message, super.groups});

  @override
  String get name => 'NegativeOrZero';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  String get defaultMessage => 'must be less than or equal to 0';

  @override
  bool isValid(Object? value) {
    final sign = _compare(value, _zero);
    return sign == null || sign <= 0;
  }
}

/// Options for the regular expression of [Matches] and [Email], such as
/// matching without regard to case.
///
/// Jakarta's `Pattern.Flag`, limited to the options Dart's `RegExp` has.
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

/// A constraint that requires a string to match the regular expression
/// [regexp] as a whole.
///
/// Use it for formats with a fixed shape: postal codes, ISBNs, product
/// codes. The whole value must match, as with Java's `Matcher.matches()`,
/// so `^` and `$` are not needed. `null` passes. Since the default message
/// shows the expression, give a [message] users understand, or a
/// `Pattern.<object>.<field>` key in `messages.properties`.
///
/// Its error code is Jakarta's `Pattern`; the class has another name
/// because `Pattern` is a Dart core type. The arguments of a field error
/// are `[field, flags, regexp]`, as in Spring. Only for strings: on
/// another type the generator fails the build and the validator throws an
/// [UnexpectedTypeException]; a malformed expression throws a
/// [ConstraintDeclarationException].
///
/// ```dart
/// // A five-digit postal code, and a code of letters in any case.
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
  /// The constraint for strings that match [regexp] with [flags]; [message]
  /// replaces `must match "{regexp}"`, and [groups] limits it to those
  /// groups.
  const Matches(
    this.regexp, {
    this.flags = const [],
    super.message,
    super.groups,
  });

  /// The regular expression, in Dart's `RegExp` syntax, that the whole
  /// value must match.
  final String regexp;

  /// Options for matching [regexp], such as
  /// [PatternFlag.caseInsensitive]; none by default.
  final List<PatternFlag> flags;

  @override
  String get name => 'Pattern';

  @override
  bool supports(Object value) => value is String;

  @override
  void checkParameters() {
    _checkRegExp(regexp, flags);
  }

  @override
  String get defaultMessage => 'must match "{regexp}"';

  @override
  Map<String, Object?> get attributes => {'flags': flags, 'regexp': regexp};

  @override
  bool isValid(Object? value) =>
      value == null || _fullMatch(regexp, flags, '$value');
}

/// A constraint that requires a string to look like an email address.
///
/// It checks the form only, as Hibernate Validator's `@Email` does, not
/// that the address exists: a local part of at most 64 characters
/// (dot-separated atoms or quoted strings), `@`, and a domain name (labels
/// without a leading or trailing `-`, at most 63 characters each and 255
/// in total) or an IP address literal (`[192.168.0.1]`, `[IPv6:::1]`). A
/// domain without a dot, such as `localhost`, passes.
///
/// `null` and the empty string pass; add [NotBlank] to require an address.
/// [regexp] (with [flags]) adds a pattern the whole address must also
/// match, for example one company domain. The arguments of a field error
/// are `[field, flags, regexp]`. Only for strings: on another type the
/// generator fails the build and the validator throws an
/// [UnexpectedTypeException].
///
/// ```dart
/// // Every user needs an address; a work address must be the company's.
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
  /// The constraint, optionally with an extra [regexp] and its [flags];
  /// [message] replaces `must be a well-formed email address`, and
  /// [groups] limits it to those groups.
  const Email({
    this.regexp = '.*',
    this.flags = const [],
    super.message,
    super.groups,
  });

  /// An extra regular expression the whole address must match; `.*` (the
  /// default) accepts any well-formed address.
  final String regexp;

  /// Options for matching [regexp]; none by default.
  final List<PatternFlag> flags;

  static const _atom = r"[a-z0-9!#$%&'*+/=?^_`{|}~\u0080-￿-]";
  static const _quotedAtom =
      // The pieces join without a space on purpose: they are a regex.
      // ignore: missing_whitespace_between_adjacent_strings
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
    '(?:([0-9a-f]{1,4}:){7,7}[0-9a-f]{1,4}|([0-9a-f]{1,4}:){1,7}:|'
    '([0-9a-f]{1,4}:){1,6}:[0-9a-f]{1,4}|'
    '([0-9a-f]{1,4}:){1,5}(:[0-9a-f]{1,4}){1,2}|'
    '([0-9a-f]{1,4}:){1,4}(:[0-9a-f]{1,4}){1,3}|'
    '([0-9a-f]{1,4}:){1,3}(:[0-9a-f]{1,4}){1,4}|'
    '([0-9a-f]{1,4}:){1,2}(:[0-9a-f]{1,4}){1,5}|'
    '[0-9a-f]{1,4}:((:[0-9a-f]{1,4}){1,6})|:((:[0-9a-f]{1,4}){1,7}|:)|'
    'fe80:(:[0-9a-f]{0,4}){0,4}%[0-9a-z]{1,}|'
    '::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}'
    r'[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|'
    r'([0-9a-f]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.)'
    r'{3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])))\]$',
    caseSensitive: false,
  );

  @override
  String get name => 'Email';

  @override
  bool supports(Object value) => value is String;

  @override
  void checkParameters() {
    if (regexp != '.*' || flags.isNotEmpty) {
      _checkRegExp(regexp, flags);
    }
  }

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

/// A constraint that limits how many digits a number has before and after
/// the decimal point.
///
/// Use it when the value must fit a fixed-point column or format, such as
/// amounts with at most 6 integer and 2 fraction digits. Numbers and
/// `BigInt`s are counted without trailing zeros (`1.50` has one fraction
/// digit, `1000` four integer digits); numeric strings as written (`'1.50'`
/// has two, like `new BigDecimal("1.50")`), and a string that is not a
/// number fails. `null` passes. The arguments of a field error are
/// `[field, fraction, integer]`. On a value that is not a number or string
/// the generator fails the build and the validator throws an
/// [UnexpectedTypeException], as Hibernate Validator does.
///
/// ```dart
/// // Up to 999999.99, as in a DECIMAL(8, 2) column.
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
  /// The constraint for at most [integer] digits before the point and
  /// [fraction] after it; [message] replaces the default message, and
  /// [groups] limits it to those groups.
  const Digits({
    required this.integer,
    required this.fraction,
    super.message,
    super.groups,
  });

  /// The most digits allowed before the decimal point; must not be
  /// negative.
  final int integer;

  /// The most digits allowed after the decimal point; `0` allows whole
  /// numbers only. Must not be negative.
  final int fraction;

  @override
  String get name => 'Digits';

  @override
  bool supports(Object value) => _isNumeric(value);

  @override
  void checkParameters() {
    if (integer < 0) {
      throw const ConstraintDeclarationException(
        'The length of the integer part cannot be negative.',
      );
    }
    if (fraction < 0) {
      throw const ConstraintDeclarationException(
        'The length of the fraction part cannot be negative.',
      );
    }
  }

  @override
  String get defaultMessage =>
      'numeric value out of bounds (<{integer} digits>.<{fraction} digits> '
      'expected)';

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

/// A constraint that requires a `bool` to be `true`; `null` passes.
///
/// Use it for a box that must be ticked, such as accepted terms, usually
/// with a [message] that says what to do.
///
/// ```dart
/// // The signup is refused until the terms are accepted.
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
  /// The constraint; [message] replaces `must be true`, and [groups]
  /// limits it to those validation groups.
  const AssertTrue({super.message, super.groups});

  @override
  String get name => 'AssertTrue';

  @override
  bool supports(Object value) => value is bool;

  @override
  String get defaultMessage => 'must be true';

  @override
  bool isValid(Object? value) => value == null || value == true;
}

/// A constraint that requires a `bool` to be `false`; `null` passes.
///
/// Use it for a state that must not hold, such as a locked account.
///
/// ```dart
/// // A locked account cannot be used.
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
  /// The constraint; [message] replaces `must be false`, and [groups]
  /// limits it to those validation groups.
  const AssertFalse({super.message, super.groups});

  @override
  String get name => 'AssertFalse';

  @override
  bool supports(Object value) => value is bool;

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

/// A constraint that requires a `DateTime` before now.
///
/// Use it for birthdays, the dates of past events, payment dates. A
/// `DateTime` without a time of day (`DateTime(2026, 5, 1)`, what
/// `DateTime.parse('2026-05-01')` gives) is a date compared by day, like
/// Java's `LocalDate`: today is not in the past. Other values are compared
/// to the instant. "Now" comes from the validator's [ClockProvider], so
/// tests can fix it. `null` passes. On a value that is not a `DateTime`
/// the generator fails the build and the validator throws an
/// [UnexpectedTypeException].
///
/// ```dart
/// // A birthday cannot be today or later.
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
  /// The constraint; [message] replaces `must be a past date`, and
  /// [groups] limits it to those validation groups.
  const Past({super.message, super.groups});

  @override
  String get name => 'Past';

  @override
  bool supports(Object value) => value is DateTime;

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

/// A constraint that requires a `DateTime` that is not in the future.
///
/// Use it for things that have happened, where today counts, such as the
/// moment a payment was made. Dates without a time of day are compared by
/// day, so today passes (see [Past]); "now" comes from the validator's
/// [ClockProvider]. `null` passes; other types are rejected as for
/// [Past].
///
/// ```dart
/// // A payment cannot be dated in the future.
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
  /// The constraint; [message] replaces `must be a date in the past or in
  /// the present`, and [groups] limits it to those validation groups.
  const PastOrPresent({super.message, super.groups});

  @override
  String get name => 'PastOrPresent';

  @override
  bool supports(Object value) => value is DateTime;

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

/// A constraint that requires a `DateTime` after now.
///
/// Use it for bookings, deadlines and appointments. Dates without a time of
/// day are compared by day, so today is not in the future (see [Past]);
/// "now" comes from the validator's [ClockProvider]. `null` passes; other
/// types are rejected as for [Past]. Its error code is Jakarta's `Future`;
/// the class has another name because `Future` is a Dart core type.
///
/// ```dart
/// // A booking starts tomorrow at the earliest.
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
  /// The constraint; [message] replaces `must be a future date`, and
  /// [groups] limits it to those validation groups.
  const FutureDate({super.message, super.groups});

  @override
  String get name => 'Future';

  @override
  bool supports(Object value) => value is DateTime;

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

/// A constraint that requires a `DateTime` that is not in the past.
///
/// Use it for due dates and start dates where today is allowed. Dates
/// without a time of day are compared by day, so today passes (see
/// [Past]); "now" comes from the validator's [ClockProvider]. `null`
/// passes; other types are rejected as for [Past].
///
/// ```dart
/// // A reminder cannot be due yesterday.
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
  /// The constraint; [message] replaces `must be a date in the present or
  /// in the future`, and [groups] limits it to those validation groups.
  const FutureOrPresent({super.message, super.groups});

  @override
  String get name => 'FutureOrPresent';

  @override
  bool supports(Object value) => value is DateTime;

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
