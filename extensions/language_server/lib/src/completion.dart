import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// One completion proposal.
final class Completion {
  /// A proposal shown as [label], which inserts [insertText] (else the
  /// label).
  const Completion(
    this.label, {
    this.kind = 10,
    this.detail,
    this.documentation,
    this.insertText,
    this.sortText,
  });

  /// What the list shows and the editor filters on.
  final String label;

  /// An LSP `CompletionItemKind`: 10 property, 9 module, 12 value, 18
  /// reference, 6 variable, 2 method, 7 class.
  final int kind;

  /// A short note beside the label, such as a type.
  final String? detail;

  /// Markdown shown for the selected proposal.
  final String? documentation;

  /// The text inserted, when it is not the label.
  final String? insertText;

  /// The key the list is sorted by, when it is not the label.
  final String? sortText;
}

/// Proposals with the span of text they replace (on one line).
final class CompletionResult {
  /// [items] that replace [replace].
  const CompletionResult(this.replace, this.items);

  /// The text the chosen proposal replaces.
  final SourceRange replace;

  /// The proposals.
  final List<Completion> items;
}
