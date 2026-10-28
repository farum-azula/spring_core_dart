/// Bean validation and data binding: constraint annotations such as
/// `@NotBlank()` and `@Min(18)` for the properties of your classes, the
/// validator that checks them, and the error objects that say what failed
/// and why.
///
/// Import it (the package's main library exports it too) to put rules on
/// request bodies, forms, `@ConfigurationProperties` classes and service
/// methods instead of writing `if` checks by hand. In an application the
/// checks usually run without a call of your own:
///
/// - `@Valid()` on a controller's `@RequestBody` parameter checks the
///   body; a violation is answered with a 400 that lists the fields.
/// - `@Validated()` on a bean class checks the arguments and return values
///   of its methods; a violation throws a `ConstraintViolationException`.
/// - `@Validated()` on a `@ConfigurationProperties` class checks the bound
///   values, and an invalid one stops the start.
///
/// Call `BeanValidator` yourself for anything else, and use `DataBinder`
/// to copy string input (a form, a query) onto an object and check it in
/// one step:
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotBlank()
///   String name = '';
/// }
///
/// // The empty name breaks @NotBlank: one field error on `name`.
/// final binder = DataBinder(Signup(), objectName: 'signup')
///   ..validators.add(BeanValidator())
///   ..bind({'name': ''})
///   ..validate();
/// binder.bindingResult.hasErrors; // true: NotBlank.signup.name
/// ```
///
/// Spring (Java): `org.springframework.validation` plus a Jakarta Bean
/// Validation style set of constraints.
/// ```java
/// class Signup { @NotBlank String name; }
///
/// var binder = new DataBinder(new Signup(), "signup");
/// binder.setValidator(new LocalValidatorFactoryBean());
/// binder.bind(new MutablePropertyValues(Map.of("name", "")));
/// binder.validate();
/// binder.getBindingResult().hasErrors();
/// ```
library;

export 'package:spring_core_dart/src/validation/bean_validator.dart';
export 'package:spring_core_dart/src/validation/constraints.dart';
export 'package:spring_core_dart/src/validation/data_binder.dart';
export 'package:spring_core_dart/src/validation/errors.dart';
export 'package:spring_core_dart/src/validation/method_validation.dart';
export 'package:spring_core_dart/src/validation/validator.dart';
