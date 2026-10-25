// Validation and data binding: constraints, a class-level constraint,
// @Valid cascading, groups.
//
// Spring (Java): Jakarta Bean Validation annotations + DataBinder.
import 'package:spring_core_dart/spring_core_dart.dart';

class SameEmails extends Constraint {
  const SameEmails({super.message});

  @override
  String get name => 'SameEmails';

  @override
  String get defaultMessage => "e-mails don't match";

  @override
  bool isValid(Object? value) =>
      value is! CheckoutForm || value.email == value.confirmEmail;
}

/// Constraints in this group are checked only when asked for.
abstract final class OnGift {}

@Introspected()
class Address {
  @NotBlank()
  String city = '';

  @Matches(r'\d{5}', message: 'must be 5 digits like [0-9]{5}')
  String? zip;
}

@Introspected()
@SameEmails()
class CheckoutForm {
  @NotBlank(message: "can't be blank")
  @Size(max: 20)
  String name = '';

  @NotNull()
  @Email()
  String? email;

  String? confirmEmail;

  @Min(1)
  int quantity = 1;

  @NotBlank(groups: [OnGift])
  String giftNote = '';

  @Valid()
  Address address = Address();
}
