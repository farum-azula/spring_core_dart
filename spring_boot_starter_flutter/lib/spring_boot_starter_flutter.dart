/// Spring Boot inside a Flutter app: import it to keep the app's state and
/// services in beans and to give those beans to the widgets.
///
/// `SpringApplicationWidget` at the root starts the application context
/// (beans, configuration files, messages) while a splash screen shows, and
/// hands it to the widget tree. Widgets get their beans without passing
/// them through constructors: as a `beans` record declared in the widget's
/// type (`SpringStatelessWidget`, `SpringStatefulWidget`), with
/// `context.bean<T>()`, or with getters generated for `@BuildContextAccess`
/// beans. State beans marked `@ChangeNotifierComponent` or
/// `@NotifyListeners` rebuild the widgets that show them. The app widget
/// itself, its themes and its locales can come from properties
/// (`spring.flutter.app.*`, `spring.flutter.theme.*`), the platform is an
/// active profile, and a hot reload restarts the context when the beans
/// changed.
///
/// ```dart
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(
///     application: () => springApplication, // generated in main.spring.dart
///     home: const CounterPage(),
///   ),
/// );
/// ```
///
/// The package also brings and exports `spring_core_dart`,
/// `spring_boot_dart` (`@Component`, `@Value`, `@ConfigurationProperties`,
/// `@SpringBootApplication`, events, validation, JSON, ...) and
/// `spring_boot_starter_logging` (switched on: `SpringLog` output with
/// levels and patterns from `logging.*`, an in-memory `LogBuffer`), so an
/// app depends on and imports only this package. Two names would clash
/// with Flutter's and are left out: Boot's startup `Banner` (Flutter has a
/// `Banner` widget) and the validation constraint `Size` (`dart:ui` has
/// `Size`), exported here as [SizeConstraint].
///
/// The user's tokens and secrets go to the platform's secure storage
/// ([SecureTokenStore]: the Keychain, the Android Keystore, DPAPI,
/// libsecret), and an app's login opens the system browser
/// ([PlatformAuthorizationBrowser]); both are beans by default and serve
/// the OAuth2 client (`spring_boot_starter_oauth2_client`).
library;

import 'package:spring_boot_dart/spring_boot_dart.dart' as boot;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    hide Banner, Size;
// The OAuth2 client's types the platform code implements; the app needs
// them to declare its own store or browser.
export 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart'
    show
        AuthorizationBrowser,
        AuthorizationCancelledException,
        InMemoryTokenStore,
        TokenStore;

export 'src/annotations.dart';
export 'src/asset_resource.dart';
export 'src/browser/platform_authorization_browser.dart'
    show PlatformAuthorizationBrowser, AuthorizationBrowserException;
export 'src/bean_reads.dart' show BeanReadsPointcut, BeanReadsInterceptor;
export 'src/app_lifecycle.dart';
export 'src/context_extensions.dart';
export 'src/notify_listeners.dart';
export 'src/platform_profiles.dart';
export 'src/secure_storage/secure_token_store.dart';
export 'src/spring_app.dart';
export 'src/spring_application_widget.dart';
export 'src/spring_scope.dart';
export 'src/spring_widgets.dart';
export 'src/theme/spring_theme_data.dart'
    show SpringThemeData, SpringTextSpec, SpringThemeExtension;
export 'src/theme/spring_themes.dart';
export 'src/theme/theme_fonts.dart';
export 'src/theme/theme_values.dart' show ThemePropertyException;

/// The validation constraint that keeps a string's length or a
/// collection's size between `min` and `max`.
///
/// It is the `@Size` of `spring_core_dart` (Jakarta's `@Size`) under
/// another name, because Flutter's `Size` (`dart:ui`) is everywhere in
/// widget code. Use it on validated configuration properties or on objects
/// checked by the validator.
///
/// ```dart
/// // A display name from the settings must be 2 to 40 characters long.
/// @ConfigurationProperties('profile')
/// @Validated()
/// class ProfileProperties {
///   @SizeConstraint(min: 2, max: 40)
///   String displayName = 'Reader';
/// }
/// ```
typedef SizeConstraint = boot.Size;
