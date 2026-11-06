// The advanced chapter (README chapter 13): extension points of the
// container that a bookstore does not need every day. Its beans are
// active only with the `advanced` profile, which `bin/advanced.dart`
// switches on; the server itself never does.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A meta-annotation: `@AdvancedTour()` is `@Profile(['advanced'])`, as a
/// Spring annotation annotated with `@Profile` would be.
class AdvancedTour extends Profile {
  const AdvancedTour() : super(const ['advanced']);
}
