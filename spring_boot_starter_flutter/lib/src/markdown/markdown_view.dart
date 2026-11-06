import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart'
    show
        cupertinoDesktopTextSelectionHandleControls,
        cupertinoTextSelectionHandleControls;
import 'package:flutter/material.dart'
    show
        MaterialLocalizations,
        SelectionArea,
        Theme,
        desktopTextSelectionHandleControls,
        materialTextSelectionHandleControls;
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:spring_boot_starter_flutter/src/markdown/code_tokens.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_styles.dart';

/// Shows Markdown with the theme's text styles and the code colored by
/// `styles.code`: headings, paragraphs, lists, quotes, tables, code
/// blocks and inline code, links.
///
/// The Markdown is GitHub's; HTML written in it is shown as text (the
/// site's pages, which the build writes from the same files, do the same).
/// A front matter (`---` ... `---` at the top) is left out.
///
/// The colors of code come from the theme's `styles.code`: `background`,
/// `text`, and one color per kind of piece (`keyword`, `string`,
/// `comment`, `number`, `key`, `annotation`); one that is not set falls
/// back on the color scheme. Fenced blocks name their language (Dart,
/// YAML, properties, shell, JSON are colored).
///
/// ```yaml
/// # themes/site.yml
/// styles:
///   code:
///     background: $colors.surfaceContainerLow
///     keyword: '#c678dd'
///     string: '#98c379'
///     comment: '#5c6370'
/// ```
///
/// ```dart
/// MarkdownView(text, onLink: (href) => launch(href));
/// MarkdownView.resource('resources:content/docs/beans.md');
/// MarkdownView.code('server:\n  port: 8080', language: 'yaml');
/// ```
class MarkdownView extends StatefulWidget {
  /// Shows [markdown]; [onLink] gets the address of a tapped link.
  const MarkdownView(
    String this.markdown, {
    this.onLink,
    this.selectable = true,
    super.key,
  }) : location = null,
       _code = null,
       _language = null;

  /// Shows the Markdown of the application's resource [location]
  /// (`resources:content/docs/beans.md`), read once.
  const MarkdownView.resource(
    String this.location, {
    this.onLink,
    this.selectable = true,
    super.key,
  }) : markdown = null,
       _code = null,
       _language = null;

  /// Shows [code] as a fenced block of Markdown in [language] (`yaml`,
  /// `dart`, ...): the theme's `styles.code`, as in a Markdown page.
  const MarkdownView.code(
    String this._code, {
    this._language,
    this.selectable = true,
    super.key,
  }) : markdown = null,
       location = null,
       onLink = null;

  /// The Markdown shown, or `null` for a [location].
  final String? markdown;

  final String? _code;
  final String? _language;

  /// The resource read, or `null`.
  final String? location;

  /// Called with the address of a tapped link (as written).
  final void Function(String href)? onLink;

  /// Whether the text can be selected.
  final bool selectable;

  // A fence longer than any run of backticks in [code].
  static String _fenced(String code, String? language) {
    final longest = RegExp('`+')
        .allMatches(code)
        .fold(
          0,
          (max, run) => run.end - run.start > max ? run.end - run.start : max,
        );
    final fence = '`' * (longest < 3 ? 3 : longest + 1);
    return '$fence${language ?? ''}\n$code\n$fence\n';
  }

  /// GitHub's Markdown, HTML in it kept as text.
  static final syntax = md.ExtensionSet(
    [const _HtmlAsText(), ...md.ExtensionSet.gitHubWeb.blockSyntaxes],
    [
      for (final syntax in md.ExtensionSet.gitHubWeb.inlineSyntaxes)
        if (syntax is! md.InlineHtmlSyntax) syntax,
    ],
  );

  /// [text] without its front matter.
  static String withoutFrontMatter(String text) {
    final match = RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n?').firstMatch(text);
    return match == null ? text : text.substring(match.end);
  }

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <GestureRecognizer>[];
  Future<String>? _loading;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = widget.location;
    if (location != null && _loading == null) {
      _loading = SpringScope.of(
        context,
        listen: false,
      ).getResource(location).readAsString();
    }
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _loading = widget.location == null
          ? null
          : SpringScope.of(
              context,
              listen: false,
            ).getResource(widget.location!).readAsString();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget._code;
    final markdown =
        widget.markdown ??
        (code == null ? null : MarkdownView._fenced(code, widget._language));
    if (markdown != null) {
      return _view(context, markdown);
    }
    return FutureBuilder<String>(
      future: _loading,
      builder: (context, snapshot) => snapshot.hasData
          ? _view(context, snapshot.data!)
          : const SizedBox.shrink(),
    );
  }

  Widget _view(BuildContext context, String markdown) {
    _disposeRecognizers();
    final nodes = md.Document(
      extensionSet: MarkdownView.syntax,
    ).parse(MarkdownView.withoutFrontMatter(markdown));
    final look = _Look.of(context);
    final view = DefaultTextStyle.merge(
      style: look.body,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _blocks(nodes, look),
      ),
    );
    if (!widget.selectable) {
      return view;
    }
    // Material's SelectionArea needs MaterialLocalizations (its menu); in a
    // CupertinoApp or WidgetsApp the text is selectable without a menu.
    if (Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        ) !=
        null) {
      return SelectionArea(child: view);
    }
    return SelectableRegion(
      selectionControls: switch (defaultTargetPlatform) {
        TargetPlatform.iOS => cupertinoTextSelectionHandleControls,
        TargetPlatform.macOS => cupertinoDesktopTextSelectionHandleControls,
        TargetPlatform.linux ||
        TargetPlatform.windows => desktopTextSelectionHandleControls,
        TargetPlatform.android ||
        TargetPlatform.fuchsia => materialTextSelectionHandleControls,
      },
      child: view,
    );
  }

  // The blocks of [nodes] with the gaps between them: none before the
  // first or after the last, more above a heading, less below one.
  List<Widget> _blocks(List<md.Node> nodes, _Look look) {
    final result = <Widget>[];
    md.Node? previous;
    for (final node in nodes) {
      final blocks = _block(node, look);
      if (blocks.isEmpty) {
        continue;
      }
      if (previous != null) {
        result.add(
          SizedBox(
            height: switch (_heading(node)) {
              final level? => level <= 2 ? 24 : 16,
              null => _heading(previous) == null ? 12 : 8,
            },
          ),
        );
      }
      result.addAll(blocks);
      previous = node;
    }
    return result;
  }

  // The level of a heading, or `null`.
  static int? _heading(md.Node node) => switch (node) {
    md.Element(:final tag) when RegExp(r'^h[1-6]$').hasMatch(tag) => int.parse(
      tag.substring(1),
    ),
    _ => null,
  };

  List<Widget> _block(md.Node node, _Look look) {
    if (node is md.Text) {
      return [Text.rich(TextSpan(text: node.text))];
    }
    if (node is! md.Element) {
      return const [];
    }
    final children = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(node.tag.substring(1));
        return [
          Text.rich(
            TextSpan(children: _inline(children, look)),
            style: look.heading(level),
          ),
        ];
      case 'p':
        return [Text.rich(TextSpan(children: _inline(children, look)))];
      case 'pre':
        final code = children.whereType<md.Element>().firstOrNull;
        final language = code?.attributes['class']?.replaceFirst(
          'language-',
          '',
        );
        final text = _unescape(
          code?.textContent ?? node.textContent,
        ).replaceFirst(RegExp(r'\n$'), '');
        return [_codeBlock(text, language, look)];
      case 'ul' || 'ol':
        final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        var number = start;
        return [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 4,
            children: [
              for (final item in children.whereType<md.Element>())
                _listItem(item, node.tag == 'ol' ? '${number++}.' : '•', look),
            ],
          ),
        ];
      case 'blockquote':
        return [
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: look.rule, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _blocks(children, look),
            ),
          ),
        ];
      case 'hr':
        return [
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: look.rule,
          ),
        ];
      case 'table':
        return [_table(node, look)];
      default:
        return _blocks(children, look);
    }
  }

  Widget _listItem(md.Element item, String marker, _Look look) {
    final children = item.children ?? const <md.Node>[];
    final blocks = children.any(
      (child) =>
          child is md.Element &&
          const {'p', 'ul', 'ol', 'pre', 'blockquote'}.contains(child.tag),
    );
    final checkbox = children.whereType<md.Element>().where(
      (child) => child.tag == 'input',
    );
    final mark = checkbox.isEmpty
        ? marker
        : checkbox.first.attributes.containsKey('checked')
        ? '☑'
        : '☐';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 24, child: Text(mark)),
        Expanded(
          child: blocks
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _blocks(children, look),
                )
              : Text.rich(
                  TextSpan(
                    children: _inline(
                      [
                        for (final child in children)
                          if (child is! md.Element || child.tag != 'input')
                            child,
                      ],
                      look,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _codeBlock(String text, String? language, _Look look) => Container(
    padding: look.codePadding,
    decoration: BoxDecoration(
      color: look.codeBackground,
      borderRadius: BorderRadius.circular(look.codeRadius),
      border: switch (look.codeBorder) {
        final color? => Border.all(color: color, width: look.codeBorderWidth),
        null => null,
      },
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text.rich(
        TextSpan(
          style: look.code,
          children: [
            for (final token in CodeTokens.of(text, language))
              TextSpan(
                text: token.text,
                style: switch (look.token(token.kind)) {
                  final color? => TextStyle(color: color),
                  null => null,
                },
              ),
          ],
        ),
      ),
    ),
  );

  Widget _table(md.Element table, _Look look) {
    final rows = <md.Element>[
      for (final section
          in (table.children ?? const <md.Node>[]).whereType<md.Element>())
        ...(section.children ?? const <md.Node>[]).whereType<md.Element>(),
    ];
    final width = rows.fold(
      0,
      (max, row) =>
          (row.children?.length ?? 0) > max ? row.children!.length : max,
    );
    return Table(
      border: TableBorder.all(color: look.rule),
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < width; i++)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: switch (row.children?.elementAtOrNull(i)) {
                    final md.Element cell => Text.rich(
                      TextSpan(children: _inline(cell.children ?? [], look)),
                      style: cell.tag == 'th'
                          ? const TextStyle(fontWeight: FontWeight.w600)
                          : null,
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ),
            ],
          ),
      ],
    );
  }

  List<InlineSpan> _inline(List<md.Node> nodes, _Look look) => [
    for (final node in nodes) _span(node, look),
  ];

  InlineSpan _span(md.Node node, _Look look) {
    if (node is md.Text) {
      // A line break inside a paragraph is a space (a hard break is `br`).
      return TextSpan(text: _unescape(node.text).replaceAll('\n', ' '));
    }
    if (node is! md.Element) {
      return const TextSpan();
    }
    final children = _inline(node.children ?? const [], look);
    switch (node.tag) {
      case 'strong':
        return TextSpan(
          style: const TextStyle(fontWeight: FontWeight.bold),
          children: children,
        );
      case 'em':
        return TextSpan(
          style: const TextStyle(fontStyle: FontStyle.italic),
          children: children,
        );
      case 'del':
        return TextSpan(
          style: const TextStyle(decoration: TextDecoration.lineThrough),
          children: children,
        );
      case 'code':
        return TextSpan(
          text: _unescape(node.textContent).replaceAll('\n', ' '),
          style: look.code.copyWith(backgroundColor: look.codeBackground),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        final onLink = widget.onLink;
        TapGestureRecognizer? recognizer;
        if (href != null && onLink != null) {
          recognizer = TapGestureRecognizer()..onTap = () => onLink(href);
          _recognizers.add(recognizer);
        }
        // A recognizer is not inherited: every piece of the link gets it.
        return TextSpan(
          style: TextStyle(
            color: look.link,
            decoration: TextDecoration.underline,
            decorationColor: look.link,
          ),
          children: [
            for (final child in children) _tappable(child, recognizer),
          ],
        );
      case 'img':
        return TextSpan(text: node.attributes['alt'] ?? '');
      default:
        return TextSpan(children: children);
    }
  }

  static InlineSpan _tappable(InlineSpan span, GestureRecognizer? onTap) {
    if (onTap == null || span is! TextSpan) {
      return span;
    }
    return TextSpan(
      text: span.text,
      style: span.style,
      recognizer: onTap,
      mouseCursor: SystemMouseCursors.click,
      children: [
        for (final child in span.children ?? const <InlineSpan>[])
          _tappable(child, onTap),
      ],
    );
  }

  // The parser keeps entities in text (`&lt;`); the widgets show text.
  static String _unescape(String text) => text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

// The theme's styles and colors for Markdown.
final class _Look {
  _Look({
    required this.body,
    required this.code,
    required this.codeBackground,
    this.codePadding = const EdgeInsets.all(12),
    this.codeRadius = 6,
    this.codeBorder,
    this.codeBorderWidth = 1,
    required this.link,
    required this.rule,
    required this.headings,
    required this.tokens,
  });

  static _Look of(BuildContext context) {
    final theme = SpringTheme.maybeOf(context);
    final base = DefaultTextStyle.of(context).style;
    if (theme == null) {
      return _Look(
        body: base,
        code: base.copyWith(fontFamily: 'monospace'),
        codeBackground: const Color(0x14000000),
        link: const Color(0xFF1A73E8),
        rule: const Color(0x33000000),
        headings: {
          for (var level = 1; level <= 6; level++)
            'h$level': base.copyWith(
              fontSize: (base.fontSize ?? 14) * (2.2 - level * 0.2),
              fontWeight: FontWeight.w600,
            ),
        },
        tokens: const {},
      );
    }
    final scheme = theme.colorScheme;
    final style = theme.styles['code']?.resolve(const {});
    // A property of `styles.code`, or `null` when it is not written.
    T? read<T>(T Function(StyleValues values) get) {
      if (style == null) {
        return null;
      }
      try {
        return get(style);
      } on StateError {
        return null;
      }
    }

    Color? color(String prop) => read((values) => values.color(prop));

    // Theme.of's styles: the theme's, with the sizes of the locale's
    // script (a SpringTheme's own text styles have only what was set).
    final text = Theme.of(context).textTheme;
    final roles = [
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
    ];
    final code = (text.bodyMedium ?? base).merge(theme.textStyle('code'));
    return _Look(
      body: text.bodyLarge ?? base,
      code: color('text') == null ? code : code.copyWith(color: color('text')),
      codeBackground: color('background') ?? scheme.surfaceContainerHighest,
      codePadding:
          read((values) => values.insets('padding')) ??
          const EdgeInsets.all(12),
      codeRadius: read((values) => values.number('radius')) ?? 6,
      codeBorder: color('border'),
      codeBorderWidth: read((values) => values.number('border-width')) ?? 1,
      link: scheme.primary,
      rule: scheme.outlineVariant,
      headings: {
        for (var level = 1; level <= 6; level++)
          'h$level': roles[level - 1] ?? base,
      },
      tokens: {
        CodeTokenKind.keyword: color('keyword') ?? scheme.primary,
        CodeTokenKind.string: color('string') ?? scheme.tertiary,
        CodeTokenKind.comment: color('comment') ?? scheme.outline,
        CodeTokenKind.number: color('number') ?? scheme.secondary,
        CodeTokenKind.key: color('key') ?? scheme.primary,
        CodeTokenKind.annotation: color('annotation') ?? scheme.secondary,
        CodeTokenKind.punctuation:
            color('punctuation') ?? scheme.onSurfaceVariant,
        CodeTokenKind.variable: color('variable') ?? scheme.onTertiaryContainer,
        CodeTokenKind.type: color('type') ?? scheme.onSecondaryContainer,
      },
    );
  }

  final TextStyle body;
  final TextStyle code;
  final Color codeBackground;
  final EdgeInsets codePadding;
  final double codeRadius;
  final Color? codeBorder;
  final double codeBorderWidth;
  final Color link;
  final Color rule;
  final Map<String, TextStyle> headings;
  final Map<CodeTokenKind, Color> tokens;

  TextStyle heading(int level) => headings['h$level'] ?? body;

  Color? token(CodeTokenKind kind) => tokens[kind];
}

// An HTML block of the Markdown as a paragraph of its text.
final class _HtmlAsText extends md.HtmlBlockSyntax {
  const _HtmlAsText();

  @override
  md.Node parse(md.BlockParser parser) {
    final html = super.parse(parser);
    return html is md.Text ? md.Element('p', [md.Text(html.text)]) : html;
  }
}
