import 'package:dart_spring_language_server/src/config/config_check.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/did_you_mean.dart';

/// A key the schema does not know, under a known parent: a warning for a
/// property (when the metadata of every package is there), an error for a
/// theme key, with a did-you-mean. The keys below it are not checked.
final class UnknownKeyCheck implements ConfigKeyCheck {
  /// The check.
  const UnknownKeyCheck();

  @override
  void check(ConfigCheckPass pass, ResolvedKey key, List<Problem> problems) {
    final resolution = key.resolution;
    final config = key.key;
    if (!resolution.isUnknown ||
        resolution.depth < config.parentCount ||
        !(pass.complete || key.isTheme) ||
        !resolution.parent!.real) {
      return;
    }
    final index = resolution.depth - config.parentCount;
    final (from, to) = config.spans[index.clamp(0, config.spans.length - 1)];
    final range = pass.document.range(config.line, from, to);
    problems.add(
      Problem(
        range,
        _message(key),
        error: key.isTheme,
        fixes: Fix.suggesting(range, _guess(key)),
      ),
    );
    pass.reported.add(config.segments.sublist(0, resolution.depth + 1));
  }

  static List<String> _choices(ResolvedKey key) => [
    for (final node in key.resolution.parent!.named) node.name,
  ];

  static String? _guess(ResolvedKey key) =>
      didYouMean(key.resolution.unknown!, _choices(key));

  static String _message(ResolvedKey key) {
    final resolution = key.resolution;
    final name = resolution.unknown!;
    final path = key.key.segments.sublist(0, resolution.depth).join('.');
    final choices = _choices(key);
    final guess = _guess(key);
    final where = path.isEmpty ? '' : " in '$path'";
    final hint = guess == null ? '' : ". Did you mean '$guess'?";
    final kind = key.isTheme ? 'theme key' : 'property';
    final extra = key.isTheme && guess == null && choices.length <= 12
        ? '. Valid: ${choices.join(', ')}'
        : '';
    return "Unknown $kind '$name'$where$hint$extra";
  }
}
