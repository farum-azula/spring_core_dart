// Typed configuration: `neon.shop.*` bound to a class and validated at
// startup (chapter 2 and 10).
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// A class-level constraint: the shop must close after it opens. A
/// constraint is a const class with `isValid`; its `name` is the message
/// code (`ValidOpeningHours` in messages*.properties).
class ValidOpeningHours extends Constraint {
  const ValidOpeningHours({super.message});

  @override
  String get name => 'ValidOpeningHours';

  @override
  String get defaultMessage => 'the shop must close after it opens';

  @override
  bool isValid(Object? value) =>
      value is! ShopProperties || value.opensAt < value.closesAt;
}

/// Bound from `neon.shop.*` in any source and any relaxed form:
/// `neon.shop.max-basket-size` in a file, `--neon.shop.max-basket-size=5`
/// on the command line, `NEON_SHOP_MAX_BASKET_SIZE=5` in the environment.
/// `@Validated()` checks the constraints when the application starts: an
/// invalid value stops it with a report naming the property.
@ConfigurationProperties('neon.shop')
@Validated()
@ValidOpeningHours()
class ShopProperties {
  @NotBlank()
  String name = 'NEON Books';

  /// Opening hours, 0-24.
  @Min(0)
  @Max(24)
  int opensAt = 9;

  @Min(0)
  @Max(24)
  int closesAt = 21;

  /// Books per basket, all titles together.
  @Min(1)
  int maxBasketSize = 10;

  /// `2d`, `48h`, `PT48H`: converted to a Duration.
  Duration deliveryTime = const Duration(days: 2);

  /// `512KB`, `1MB`: converted to a DataSize.
  DataSize maxCoverSize = DataSize.ofKilobytes(512);

  /// Whether the shop is open at [time].
  bool isOpenAt(DateTime time) => time.hour >= opensAt && time.hour < closesAt;
}
