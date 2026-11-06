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
/// Logins and secrets (the Keychain, the Android Keystore, the system's
/// login window, widgets that follow the logged-in user) come with
/// `spring_boot_starter_flutter_security`, which brings this package: an
/// app without a login carries none of that code.
library;

import 'package:spring_boot_dart/spring_boot_dart.dart' as boot;

export 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart'
    hide Banner, Size;
// The HTTP model and clients: the starter's API takes an `HttpTransport`
// (`RemoteCache`, the theme's network images), and an app sending its own
// requests needs no other dependency.
export 'package:spring_web_dart/spring_web_dart.dart';

export 'src/annotations.dart';
export 'src/app_lifecycle.dart';
export 'src/asset_resource.dart';
export 'src/bean_lookup_scope.dart';
export 'src/bean_reads.dart' show BeanReadsPointcut, BeanReadsInterceptor;
export 'src/context_extensions.dart';
export 'src/desktop_window/desktop_window.dart';
export 'src/desktop_window/desktop_window_settings.dart';
export 'src/files/file_store.dart';
export 'src/files/file_template.dart' show FileArea, FileTemplate;
export 'src/files/memory_file_store.dart' show InMemoryFileStore;
export 'src/markdown/code_tokens.dart';
export 'src/markdown/markdown_outline.dart';
export 'src/markdown/markdown_view.dart';
export 'src/properties/flutter_properties.dart';
export 'src/notify_listeners.dart';
export 'src/platform_profiles.dart';
export 'src/shortcuts/keyboard_shortcuts.dart';
export 'src/shortcuts/keyboard_shortcuts_scope.dart';
export 'src/shortcuts/shortcut.dart';
export 'src/shortcuts/shortcut_handler.dart';
export 'src/shortcuts/shortcut_handlers.dart';
export 'src/shortcuts/shortcut_intent.dart';
export 'src/shortcuts/shortcut_invocation.dart';
export 'src/shortcuts/shortcut_keys.dart';
export 'src/shortcuts/shortcut_label.dart';
export 'src/spring_app.dart';
export 'src/spring_application_widget.dart';
export 'src/spring_scope.dart';
export 'src/spring_widgets.dart';
export 'src/text/highlighted_text.dart';
export 'src/theme/content_change.dart';
export 'src/theme/wheel_scroll.dart';
export 'src/splash/frame_pacer.dart';
export 'src/splash/splash_properties.dart';
export 'src/splash/splash_stage.dart';
export 'src/splash/splash_stage_event.dart';
export 'src/splash/splash_stages.dart';
export 'src/splash/splash_trace.dart';
export 'src/theme/loader_tracks.dart';
export 'src/theme/spring_theme_data.dart'
    show SpringThemeData, SpringTextSpec, SpringThemeExtension;
export 'src/theme/spring_themes.dart';
export 'src/theme/theme_animation.dart';
export 'src/theme/theme_background.dart';
export 'src/theme/theme_background_widget.dart' show ThemeBackground;
export 'src/theme/theme_fonts.dart';
export 'src/theme/theme_image.dart' show ThemeImage;
export 'src/theme/theme_loader.dart'
    show
        BuiltInLoaderLook,
        LoaderFrame,
        LoaderKindRegistration,
        LoaderValues,
        ThemeLoaderKinds,
        ThemeLoaderPainter,
        ThemeLoaderPhase,
        ThemeLoaderSpec,
        ThemeLoaderWidget;
export 'src/theme/theme_loader_widget.dart'
    show LoaderTimeline, ThemeLoader, ThemeSkeleton;
export 'src/theme/theme_splash.dart' show ThemeSplash, ThemeSplashData;
export 'src/theme/theme_key_reader.dart';
export 'src/theme/theme_states.dart';
export 'src/theme/theme_text.dart';
export 'src/theme/theme_styles.dart';
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
