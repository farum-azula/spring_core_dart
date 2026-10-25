import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// `counter.*` from `lib/resources/application*.properties`, overridable
/// at build time: `flutter run --dart-define=COUNTER_STEP=5`. Validated at
/// startup: a bad value fails the start with a report.
@ConfigurationProperties('counter')
@Validated()
class CounterProperties {
  /// The app bar's title; each platform's profile file sets its own.
  @SizeConstraint(min: 1, max: 60)
  String title = 'Flutter Demo Home Page';

  /// How much one tap adds.
  @Min(1)
  int step = 1;
}
