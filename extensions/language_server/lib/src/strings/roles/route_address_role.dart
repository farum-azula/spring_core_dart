import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/navigation_strings.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// A path of a screen: the address of `go('/x')`, `push`, `redirect`,
/// `parse` / `expand`, a branch of `@RouteShell(branches: [...])`, a path
/// of `@RouteInfo(paths: [...])`. It goes to the screens it opens and
/// completes from the routes; in an app with screens, an address of
/// `go`/`push` or a shell branch that no screen has is reported (a
/// pattern with variables is not checked).
final class RouteAddressRole extends StringRole {
  /// The role, over [model].
  const RouteAddressRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) =>
      string.value.startsWith('/') &&
          (isRouteArgument(string) || isRouteListPath(string))
      ? Handled(model.screens.screensOf(string.path, string.value))
      : null;

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (!isRouteArgument(string) || !request.before.startsWith('/')) {
      return null;
    }
    final routes = model.metadataFor(string.path).routes;
    if (routes.isEmpty) {
      return null;
    }
    return Handled(
      CompletionResult(request.rangeFrom(string.contentStart), [
        for (final route in routes)
          Completion(
            route.path,
            kind: 18,
            detail: [?route.className, ?route.title].join(' · '),
          ),
      ]),
    );
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    final value = string.value;
    final checked =
        isRouteArgument(string) &&
            (string.method == 'go' || string.method == 'push') ||
        string.annotationType == 'RouteShell' && isRouteListPath(string);
    if (!checked || !value.startsWith('/') || value.contains('{')) {
      return;
    }
    final address = Uri.tryParse(value)?.path;
    final routes = model.metadataFor(string.path).routes;
    if (address == null ||
        routes.isEmpty ||
        routes.any((route) => route.matches(address))) {
      return;
    }
    problems.add(
      Problem(
        model.locations.rangeOf(
          string.file,
          string.contentStart,
          string.contentEnd,
        ),
        "No screen has the address '$address' (@ScreenRoute or ScreenRoutes)",
      ),
    );
  }
}
