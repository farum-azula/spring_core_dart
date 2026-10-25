/// Spring Boot for Flutter apps: `SpringApplicationWidget` runs the
/// application and gives its beans to the widgets (`context.bean<T>()`,
/// getters generated for `@BuildContextAccess` beans,
/// `SpringStatelessWidget<(...)>`, `SpringStatefulWidget<(...)>`), follows
/// the app's lifecycle and activates the platform's profiles.
///
/// Also brings and exports `spring_core_dart`, `spring_boot_dart`
/// (`@Component`, `@Value`, `@ConfigurationProperties`,
/// `@SpringBootApplication`, events, validation, JSON, ...) and
/// `spring_boot_starter_logging` (switched on: `SpringLog` output with
/// levels and patterns from `logging.*`, an in-memory `LogBuffer`), so an
/// app depends on and imports only this package. Two names would clash with Flutter's and are left out: Boot's
/// startup `Banner` (Flutter has a `Banner` widget) and the validation
/// constraint `Size` (`dart:ui` has `Size`), exported here as
/// [SizeConstraint].
library;

import 'package:spring_boot_dart/spring_boot_dart.dart' as boot;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    hide Banner, Size;

export 'src/annotations.dart';
export 'src/asset_resource.dart';
export 'src/app_lifecycle.dart';
export 'src/context_extensions.dart';
export 'src/notify_listeners.dart';
export 'src/platform_profiles.dart';
export 'src/spring_app.dart';
export 'src/spring_application_widget.dart';
export 'src/spring_scope.dart';
export 'src/spring_widgets.dart';

/// The validation constraint `@Size` of `spring_core_dart` (Jakarta's
/// `@Size`): a string's length or a collection's size between `min` and
/// `max`. Renamed here because Flutter's `Size` (`dart:ui`) is everywhere
/// in widget code.
///
/// ```dart
/// @ConfigurationProperties('profile')
/// @Validated()
/// class ProfileProperties {
///   @SizeConstraint(min: 2, max: 40)
///   String displayName = 'Reader';
/// }
/// ```
typedef SizeConstraint = boot.Size;
