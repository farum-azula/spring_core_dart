import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/navigation_strings.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// The branch a screen opens in: `@ScreenRoute('/motion', branch: '/more')`.
/// It goes to the screens of that path, and in an app with screens a
/// branch that no `@RouteShell` has is reported.
final class ScreenBranchRole extends StringRole {
  /// The role, over [model].
  const ScreenBranchRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) =>
      isScreenBranch(string) && string.value.startsWith('/')
      ? Handled(model.screens.screensOf(string.path, string.value))
      : null;

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (!isScreenBranch(string)) {
      return;
    }
    final view = model.metadataFor(string.path);
    final branches = view.shellBranches;
    if (view.routes.isEmpty ||
        branches.isEmpty ||
        branches.contains(string.value)) {
      return;
    }
    problems.add(
      Problem(
        model.locations.rangeOf(
          string.file,
          string.contentStart,
          string.contentEnd,
        ),
        "No @RouteShell has the branch '${string.value}' "
        '(branches: ${(branches.toList()..sort()).join(', ')})',
      ),
    );
  }
}
