import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// How the app shows its sections.
enum NavigationStyle {
  /// A `NavigationBar` at the bottom: phones.
  bar,

  /// A `NavigationRail` at the side: desktops and browsers.
  rail,
}

/// `app.*` of `lib/resources/application*.properties`: the platform
/// profiles set their own (`application-desktop.properties`, ...).
@ConfigurationProperties('app')
@Validated()
class AppProperties {
  /// The app bar's title.
  @SizeConstraint(min: 1, max: 40)
  String title = 'NEON Books';

  /// `bar` on phones, `rail` on wide screens.
  NavigationStyle navigation = NavigationStyle.bar;
}
