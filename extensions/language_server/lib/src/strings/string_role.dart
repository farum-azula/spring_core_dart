import 'package:dart_spring_language_server/src/completion.dart';
import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/properties/property_references.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';
import 'package:dart_spring_language_server/src/tokens/semantic_tokens.dart';

/// What a string means to Spring, and what the editor does with such
/// strings: a bean name (`@Qualifier('cash')`), a property key
/// (`getProperty('shop.name')`), a template of `${}` and `#{}`
/// (`@Value`), a pointcut, a route, a message code, a resource location.
///
/// A role recognises its strings and implements what applies to them; the
/// others keep their defaults (nothing). The roles are registered once, in
/// order (`stringRoles`): for a definition, a hover or a completion the
/// first role that handles the string answers; for the highlighting, the
/// checks, the keys the code reads and the values shown inline every role
/// adds what it finds.
abstract class StringRole {
  /// A role.
  const StringRole();

  /// What go to definition and hover show at [offset] of [string];
  /// `null` when the string is not this role's (or not at [offset]).
  Handled<Target>? target(StringContext string, int offset) => null;

  /// The completion at [request]'s cursor inside [string]; `null` when the
  /// string is not this role's.
  Handled<CompletionResult>? complete(
    StringContext string,
    CompletionRequest request,
  ) => null;

  /// Adds the semantic tokens of [string] (offsets in the file).
  void tokens(StringContext string, AddToken add) {}

  /// Adds the problems of [string] to [problems].
  void problems(StringContext string, List<Problem> problems) {}

  /// The property keys [string] reads, which the editor then knows for
  /// completion and hovers; `null` when the string is not this role's.
  Iterable<String>? keysRead(StringContext string) => null;

  /// The places in [string] that read a property, whose values are shown
  /// inline.
  Iterable<PropertyReference> references(StringContext string) => const [];
}

/// A completion asked inside a string: where the cursor is and what is
/// typed before it on its line.
final class CompletionRequest {
  /// A completion at [offset] of the string [string].
  CompletionRequest(this.string, this.offset)
    : before = string.file.text.substring(string.contentStart, offset);

  /// The string the cursor is in.
  final StringContext string;

  /// The cursor's offset in the file.
  final int offset;

  /// The string's contents from its start to the cursor.
  final String before;

  /// The key typed so far in an open `${` before the cursor (no `}` and no
  /// `:` after it), or `null`.
  late final RegExpMatch? openPlaceholder = RegExp(
    r'\$\{([^}:]*)$',
  ).firstMatch(before);

  /// The expression typed so far in an open `#{` before the cursor, or
  /// `null`.
  late final RegExpMatch? openExpression = RegExp(
    r'#\{([^}]*)$',
  ).firstMatch(before);

  /// Whether the cursor is inside a placeholder or an expression being
  /// typed in an annotation string: what the template role completes,
  /// whatever annotation it is.
  bool get inTemplate =>
      string.annotation != null &&
      (openPlaceholder != null || openExpression != null);

  /// The span from [start] to the cursor, which a proposal replaces.
  SourceRange rangeFrom(int start) {
    final lines = string.file.lineInfo;
    final from = lines.getLocation(start);
    final to = lines.getLocation(offset);
    return SourceRange(
      string.path,
      from.lineNumber - 1,
      from.columnNumber - 1,
      to.lineNumber - 1,
      to.columnNumber - 1,
    );
  }

  /// The span of the word (letters, digits, `_`, `.`, `-`) the cursor is
  /// at the end of.
  SourceRange get wordRange {
    final word = RegExp(r'[\w.\-]*$').firstMatch(before)!;
    return rangeFrom(offset - word.group(0)!.length);
  }
}
