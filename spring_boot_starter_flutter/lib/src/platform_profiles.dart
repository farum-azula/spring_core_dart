import 'package:flutter/foundation.dart';

/// The profile names of the platform the app runs on: `web` in a browser;
/// else `mobile` plus `android` or `ios`, or `desktop` plus `macos`,
/// `windows` or `linux` (`fuchsia` on Fuchsia).
///
/// `SpringApplicationWidget` adds them to the active profiles, so an app
/// can configure and assemble itself per platform without code:
/// `application-ios.properties` is read on iPhones only, and a bean marked
/// `@Profile(['android'])` exists on Android only. The specific profile
/// comes last, so `application-android.properties` wins over
/// `application-mobile.properties`. You rarely call the function yourself.
///
/// ```dart
/// // Each platform gets its own push service.
/// @Component()
/// @Profile(['ios'])
/// class ApnsPushService implements PushService { ... }
///
/// @Component()
/// @Profile(['desktop'])
/// class NoPushService implements PushService { ... }
/// ```
///
/// It follows `defaultTargetPlatform`, so a test can pretend to run on
/// another platform by setting `debugDefaultTargetPlatformOverride`.
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
