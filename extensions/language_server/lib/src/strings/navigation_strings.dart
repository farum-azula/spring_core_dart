import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';

/// The navigation's calls that take an address or a pattern as their
/// first argument: `route.go('/catalog')`, `push`, `redirect`,
/// `RouteLocation.parse` / `.expand`.
const routeMethods = {'go', 'push', 'redirect', 'parse', 'expand'};

/// Whether [string] is the first argument of a call of [routeMethods]
/// (outside annotations).
bool isRouteArgument(StringContext string) =>
    string.annotation == null &&
    routeMethods.contains(string.method) &&
    string.isFirstArgument;

/// Whether [string] is the branch a screen opens in:
/// `@ScreenRoute('/motion', branch: '/more')`.
bool isScreenBranch(StringContext string) =>
    string.annotationType == 'ScreenRoute' && string.argumentName == 'branch';

/// Whether [string] is a path of the list `@RouteShell(branches: [...])`
/// or `@RouteInfo(paths: [...])`.
bool isRouteListPath(StringContext string) {
  final list = string.literal.parent;
  final named = list is ListLiteral ? list.parent : null;
  if (named is! NamedArgument) {
    return false;
  }
  final name = named.name.lexeme;
  return string.annotationType == 'RouteShell' && name == 'branches' ||
      string.annotationType == 'RouteInfo' && name == 'paths';
}

/// Whether [string] is a title or description of the navigation, where
/// `#{key}` is a message key (the navigation and the SEO build translate
/// it): `@ScreenRoute(title:)`, `@RouteInfo(description:)`,
/// `ScreenRoutes.route()...screen(title:)`.
bool isRouteMessageArgument(StringContext string) {
  final name = string.argumentName;
  if (name == null) {
    return false;
  }
  if (string.annotation != null) {
    final type = string.annotationType;
    return type == 'ScreenRoute' && name == 'title' ||
        type == 'RouteInfo' && name == 'description';
  }
  return string.method == 'screen' && name == 'title';
}

final _messageKey = RegExp(r'^#\{\s*([^{}\s]+)\s*\}$');

/// The message key of a navigation title or description that is
/// `#{key}`; `null` for any other string.
String? routeMessageKey(StringContext string) => isRouteMessageArgument(string)
    ? _messageKey.firstMatch(string.value)?.group(1)
    : null;
