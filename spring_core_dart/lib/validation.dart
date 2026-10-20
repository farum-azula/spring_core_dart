/// Validation and data binding: constraints, validators, errors and
/// `DataBinder` (Spring's `org.springframework.validation` plus a Jakarta
/// Bean Validation style constraint set).
///
/// ```dart
/// @Introspected()
/// class Signup {
///   @NotBlank()
///   String name = '';
/// }
///
/// final binder = DataBinder(Signup(), objectName: 'signup')
///   ..validators.add(BeanValidator())
///   ..bind({'name': ''})
///   ..validate();
/// binder.bindingResult.hasErrors; // true: NotBlank.signup.name
/// ```
///
/// Spring (Java):
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
export 'package:spring_core_dart/src/validation/validator.dart';
