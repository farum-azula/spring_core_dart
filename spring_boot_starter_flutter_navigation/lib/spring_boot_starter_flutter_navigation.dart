/// Navigation for Spring Boot Flutter apps: screens on routes, declared
/// with `@ScreenRoute` on a widget or in Dart configuration
/// (`ScreenRoutes`), on the SDK's `Router` (the web address bar, deep
/// links, Android's back button).
///
/// Paths use Spring's path patterns (`/catalog/books/{isbn}`,
/// `/docs/{*path}`). Shells (`@RouteShell`) keep the tabs while their
/// branches' screens change, with a stack per branch. `RouteTemplate` and
/// `context.route` read the current route and navigate; beans may live as
/// long as a screen (`@Scope(NavigationScopes.route)`) or a branch.
///
/// ```dart
/// @ScreenRoute('/catalog/books/{isbn}', title: 'Book')
/// class BookPage extends StatelessWidget {
///   const BookPage({super.key});
///
///   @override
///   Widget build(BuildContext context) =>
///       Text(context.route.pathVariable('isbn'));
/// }
///
/// @SpringBootApplication()
/// void main() => runApp(
///   SpringApplicationWidget(application: () => springApplication),
/// );
/// ```
///
/// The package brings and exports `spring_boot_starter_flutter` (and
/// through it `spring_boot_dart`), so an app depends on and imports only
/// this package.
library;

export 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

export 'src/annotations.dart';
export 'src/language_changed_event.dart';
export 'src/navigation.dart'
    show Navigation, NavigationEntry, ScreenEntry, ShellEntry;
export 'src/properties/navigation_properties.dart';
export 'src/route_content_view.dart';
export 'src/route_language.dart';
export 'src/route_location.dart';
export 'src/route_scopes.dart' show NavigationScopes, RouteScopes;
export 'src/route_state.dart';
export 'src/route_table.dart';
export 'src/route_template.dart';
export 'src/screen_mappings.dart';
export 'src/screen_routes.dart';
export 'src/shell_state.dart';
export 'src/spring_router.dart' show SpringRouterConfig, SpringRouterDelegate;
