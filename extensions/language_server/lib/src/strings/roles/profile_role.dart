import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';

final _profileName = RegExp(r'[A-Za-z0-9_][\w\-.]*');

/// A profile expression of `@Profile('dev')`: it completes with the
/// profiles the package knows, and a name that no metadata, profile file
/// or setting knows is reported. Only checked when the package has
/// metadata of its own, else the name may be declared where the editor
/// cannot see.
final class ProfileRole extends StringRole {
  /// The role, over [model].
  const ProfileRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) {
    if (string.annotationType != 'Profile') {
      return null;
    }
    return Handled(
      CompletionResult(request.wordRange, [
        for (final name
            in model.properties.knownProfiles(string.path).toList()..sort())
          Completion(name, kind: 20, detail: 'profile'),
      ]),
    );
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    if (string.annotationType != 'Profile' ||
        !model.metadata.hasMetadata(
          model.packages.packageRootOf(string.path),
        )) {
      return;
    }
    final known = {...model.properties.knownProfiles(string.path), 'default'};
    for (final match in _profileName.allMatches(string.contents)) {
      final name = match.group(0)!;
      if (known.contains(name)) {
        continue;
      }
      final guess = didYouMean(name, known.toList());
      final range = model.locations.rangeOf(
        string.file,
        string.contentStart + match.start,
        string.contentStart + match.end,
      );
      problems.add(
        Problem(
          range,
          "Unknown profile '$name': no application-$name file and the "
          'metadata does not list it (known: '
          "${(known.toList()..sort()).join(', ')})"
          "${guess == null ? '' : ". Did you mean '$guess'?"}",
          fixes: Fix.suggesting(range, guess),
        ),
      );
    }
  }
}
