import 'package:flutter/foundation.dart';

/// The profiles of the platform the app runs on, which `SpringApplicationWidget` adds to
/// the active profiles: `web` in a browser; else `mobile` plus `android` /
/// `ios`, or `desktop` plus `macos` / `windows` / `linux` (`fuchsia` on
/// Fuchsia). The specific one comes last, so its
/// `application-android.properties` wins over
/// `application-mobile.properties`.
///
/// ```dart
/// @Component()
/// @Profile(['ios'])
/// class ApnsPushService implements PushService { ... }
///
/// @Component()
/// @Profile(['desktop'])
/// class NoPushService implements PushService { ... }
/// ```
///
/// Follows `defaultTargetPlatform`, so a test can set
/// `debugDefaultTargetPlatformOverride`.
List<String> platformProfiles() {
  if (kIsWeb) {
    return const ['web'];
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => const ['mobile', 'android'],
    TargetPlatform.iOS => const ['mobile', 'ios'],
    TargetPlatform.macOS => const ['desktop', 'macos'],
    TargetPlatform.windows => const ['desktop', 'windows'],
    TargetPlatform.linux => const ['desktop', 'linux'],
    TargetPlatform.fuchsia => const ['fuchsia'],
  };
}
