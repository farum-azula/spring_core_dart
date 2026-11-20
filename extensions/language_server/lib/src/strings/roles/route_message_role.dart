import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/navigation_strings.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

/// A `#{key}` title or description of the navigation
/// (`@ScreenRoute(title: '#{nav.home}')`, `@RouteInfo(description:)`,
/// `screen(title:)`): a message key, which goes to the bundles, completes
/// from them, and is reported when no bundle of the package defines it.
final class RouteMessageRole extends StringRole {
  /// The role, over [model].
  const RouteMessageRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final key = routeMessageKey(string);
    if (key == null) {
      return null;
    }
    return Handled(
      MessageTarget(key, model.messages.messages(key, from: string.path)),
    );
  }

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    final typed = RegExp(r'#\{([\w.\-]*)$').firstMatch(request.before);
    if (typed == null || !isRouteMessageArgument(string)) {
      return null;
    }
    return Handled(
      CompletionResult(
        request.rangeFrom(request.offset - typed.group(1)!.length),
        [
          for (final code
              in model.messages.messageCodes(string.path).toList()..sort())
            Completion(code, detail: 'message'),
        ],
      ),
    );
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    final key = routeMessageKey(string);
    if (key == null ||
        !model.messages.checksCodes(string.path) ||
        model.messages.defines(string.path, key)) {
      return;
    }
    problems.add(
      Problem(
        model.locations.rangeOf(
          string.file,
          string.contentStart,
          string.contentEnd,
        ),
        "No message '$key' in the message bundles (messages*.properties)",
      ),
    );
  }
}
