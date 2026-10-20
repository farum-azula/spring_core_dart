import 'package:spring_core_dart/spring_core_dart.dart';

/// Class-level constraint: compares two properties.
class PasswordsMatch extends Constraint {
  const PasswordsMatch({super.message});

  @override
  String get name => 'PasswordsMatch';

  @override
  String get defaultMessage => 'passwords must match';

  @override
  bool isValid(Object? value) =>
      value is! SignupForm || value.password == value.confirmPassword;
}

/// Validation group for updates.
abstract final class OnUpdate {}

@Introspected()
class Address {
  @NotBlank()
  String city = '';

  @Matches(r'\d{5}', message: 'must be 5 digits')
  String? zip;
}

/// A form bound from user input and validated declaratively.
@Introspected()
@PasswordsMatch()
class SignupForm {
  @NotBlank()
  @Size(max: 20)
  String name = '';

  @NotNull()
  @Email()
  String? email;

  @Min(18)
  int age = 0;

  @Positive(groups: [OnUpdate])
  int id = 0;

  String password = '';
  String confirmPassword = '';

  @Valid()
  Address address = Address();

  @Valid()
  List<Address> previous = [];

  String greet(String prefix) => '$prefix $name';
}
