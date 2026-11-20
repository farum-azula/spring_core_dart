import 'package:dart_spring_language_server/src/diagnostics/fix.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';

export 'package:dart_spring_language_server/src/diagnostics/fix.dart';

/// A diagnostic for the editor to underline: where, what, and whether it
/// is an error or a warning.
///
/// The checks of Dart files (`DartProblems`) and of config files
/// (`ConfigProblems`) produce them; the server publishes them with the
/// source `dart_spring`.
final class Problem {
  /// A warning, or with [error] an error, about [range]; [fixes] are the
  /// quick fixes the editor offers for it.
  const Problem(
    this.range,
    this.message, {
    this.error = false,
    this.info = false,
    this.fixes = const [],
  });

  /// Whether it is only a note (LSP severity 3), such as the hint to
  /// generate the Spring metadata.
  final bool info;

  /// The text to underline.
  final SourceRange range;

  /// What is wrong, and where possible how to fix it, as shown to the user.
  final String message;

  /// Whether it is an error (LSP severity 1) rather than a warning
  /// (severity 2). Errors mark what cannot work, such as invalid SpEL;
  /// warnings what may still be fine, such as a key the workspace does not
  /// define but the deployment may.
  final bool error;

  /// The changes that fix it, offered as quick fixes: the name it was
  /// probably meant to be, the key added to a config file.
  final List<Fix> fixes;
}
