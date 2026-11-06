import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// A block of code: a fenced block of Markdown ([MarkdownView.code]) in the
/// theme's `styles.code` (the panel, its border and the colors of the
/// palette, in themes/neon.yml).
class NeonCode extends StatelessWidget {
  const NeonCode(this.text, {super.key, this.language});

  final String text;

  /// The language of [text] (`yaml`, `dart`), colored; `null` for plain.
  final String? language;

  @override
  Widget build(BuildContext context) =>
      MarkdownView.code(text, language: language);
}
