import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart'
    show
        cupertinoDesktopTextSelectionHandleControls,
        cupertinoTextSelectionHandleControls;
import 'package:flutter/material.dart'
    show
        Icons,
        MaterialLocalizations,
        SelectionArea,
        Theme,
        desktopTextSelectionHandleControls,
        materialTextSelectionHandleControls;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:spring_boot_starter_flutter/src/theme/content_change.dart';
import 'package:spring_boot_starter_flutter/src/markdown/markdown_outline.dart';
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
/// back on the color scheme. Fenced blocks name their language, which the
/// theme's `syntax.<language>` splits into those pieces ([CodeSyntax]);
/// a language the theme does not have is plain text.
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
    this.outline,
    super.key,
  }) : location = null,
       _code = null,
       _language = null;

  /// Shows the Markdown of the application's resource [location]
  /// (`resources:content/docs/beans.md`), read once; in the app's language
  /// when there is a translation next to it (`beans.ja.md` for Japanese),
  /// read again when the language changes.
  const MarkdownView.resource(
    String this.location, {
    this.onLink,
    this.selectable = true,
    this.outline,
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
       onLink = null,
       outline = null;

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

  /// Gets the page's headings, and scrolls to one; a link to `#id` scrolls
  /// to its heading by itself.
  final MarkdownOutline? outline;

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

class _CopyButton extends StatefulWidget {
  const _CopyButton(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Copy',
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 16,
            color: widget.color,
          ),
        ),
      ),
    ),
  );
}

class _MarkdownViewState extends State<MarkdownView> {
  var _recognizers = <GestureRecognizer>[];
  // The links of the content going out while another comes in; disposed at
  // the next change, long after its transition.
  var _retired = <GestureRecognizer>[];
  Object? _builtFor;
  String? _shownFile;
  String? _shown;
  final _ids = <String>{};
  final _headings = <MarkdownHeading>[];
  final _ownOutline = MarkdownOutline();

  MarkdownOutline get _outline => widget.outline ?? _ownOutline;
  Future<String>? _loading;
  String? _file;

  // The file of [location] in the app's language: `beans.ja.md` next to
  // `beans.md` when there is one.
  String _localized(String location) {
    final language = Localizations.maybeLocaleOf(context)?.languageCode;
    if (language == null || !location.endsWith('.md')) {
      return location;
    }
    final base = location.substring(0, location.length - '.md'.length);
    if (base.endsWith('.$language')) {
      return location;
    }
    final translation = '$base.$language.md';
    return SpringScope.of(
          context,
          listen: false,
        ).getResource(translation).exists()
        ? translation
        : location;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final location = widget.location;
    if (location != null) {
      final file = _localized(location);
      if (file != _file) {
        _load(file);
      }
    }
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      final location = widget.location;
      if (location == null) {
        _file = null;
        _loading = null;
      } else {
        _load(_localized(location));
      }
    }
  }

  // Reads [file]; the content shown stays until it is read, so the view
  // keeps its height instead of collapsing for a frame.
  void _load(String file) {
    _file = file;
    final loading = _loading = SpringScope.of(
      context,
      listen: false,
    ).getResource(file).readAsString();
    loading.then(
      (text) {
        if (mounted && identical(_loading, loading)) {
          setState(() {
            _shownFile = file;
            _shown = text;
          });
        }
      },
      // A file that cannot be read shows nothing, not the last one.
      onError: (Object _) {
        if (mounted && identical(_loading, loading)) {
          setState(() {
            _shownFile = file;
            _shown = '';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _ownOutline.dispose();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in [..._recognizers, ..._retired]) {
      recognizer.dispose();
    }
    _recognizers.clear();
    _retired.clear();
  }

  // A new build of [content]: the links of its last build go; those of
  // other content (going out) wait for the next change.
  void _renewRecognizers(Object? content) {
    if (content == _builtFor) {
      for (final recognizer in _recognizers) {
        recognizer.dispose();
      }
    } else {
      for (final recognizer in _retired) {
        recognizer.dispose();
      }
      _retired = _recognizers;
      _builtFor = content;
    }
    _recognizers = [];
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
    final shown = _shown;
    if (shown == null) {
      return const SizedBox.shrink();
    }
    return ContentChange(
      id: _shownFile,
      child: _view(context, shown, content: _shownFile),
    );
  }

  Widget _view(BuildContext context, String markdown, {Object? content}) {
    _renewRecognizers(content ?? markdown);
    _ids.clear();
    _headings.clear();
    final nodes = md.Document(
      extensionSet: MarkdownView.syntax,
    ).parse(MarkdownView.withoutFrontMatter(markdown));
    final look = _Look.of(context);
    final blocks = _blocks(nodes, look);
    final headings = List.of(_headings);
    final page = _builtFor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _outline.update(headings, page: page);
      }
    });
    final view = DefaultTextStyle.merge(
      style: look.body,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: blocks,
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
        final text = _unescape(node.textContent);
        final heading = MarkdownHeading(
          level: level,
          text: text,
          id: MarkdownHeading.idOf(text, _ids),
        );
        _headings.add(heading);
        return [
          Text.rich(
            key: _outline.keyOf(heading.id, page: _builtFor),
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
        final title = _title.firstMatch(
          _unescape(node.attributes['data-metadata'] ?? ''),
        );
        return [
          _codeBlock(
            text,
            language,
            look,
            title: title == null ? null : title[1] ?? title[2] ?? title[3],
          ),
        ];
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
      case 'div'
          when (node.attributes['class'] ?? '').startsWith('markdown-alert'):
        return [_callout(node, look)];
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

  // `title="lib/main.dart"` (or 'x', or a word) after a fence's language.
  static final _title = RegExp(r'''title=(?:"([^"]*)"|'([^']*)'|(\S+))''');

  // A callout of GitHub's Markdown (`> [!NOTE]`): a box in the kind's
  // color, with the kind's name (the message `markdown.alert.<kind>`).
  Widget _callout(md.Element node, _Look look) {
    final kind = (node.attributes['class'] ?? '').split('-').last;
    final children = (node.children ?? const <md.Node>[])
        .where(
          (child) =>
              child is! md.Element ||
              child.attributes['class'] != 'markdown-alert-title',
        )
        .toList();
    final color = look.callouts[kind] ?? look.link;
    final label = (node.children?.firstOrNull?.textContent ?? kind);
    final title =
        SpringScope.maybeOf(context, listen: false)?.getMessage(
          'markdown.alert.$kind',
          defaultMessage: label,
          locale:
              (Localizations.maybeLocaleOf(context) ??
                      PlatformDispatcher.instance.locale)
                  .toString(),
        ) ??
        label;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(look.codeRadius),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title.toUpperCase(),
            style: look.body.copyWith(
              color: color,
              fontSize: (look.body.fontSize ?? 14) * 0.75,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          ..._blocks(children, look),
        ],
      ),
    );
  }

  Widget _codeBlock(
    String text,
    String? language,
    _Look look, {
    String? title,
  }) {
    final block = _code(text, language, look);
    if (title == null) {
      return block;
    }
    final border = look.codeBorder;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.codeRadius),
        border: border == null
            ? null
            : Border.all(color: border, width: look.codeBorderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: look.codePadding.left,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: look.codeHeader,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(look.codeRadius),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: look.code.copyWith(color: look.codeTitle),
                  ),
                ),
                _CopyButton(text, color: look.codeTitle),
              ],
            ),
          ),
          _code(text, language, look, header: true),
        ],
      ),
    );
  }

  Widget _code(
    String text,
    String? language,
    _Look look, {
    bool header = false,
  }) => Container(
    padding: look.codePadding,
    decoration: BoxDecoration(
      color: look.codeBackground,
      borderRadius: header
          ? BorderRadius.vertical(bottom: Radius.circular(look.codeRadius))
          : BorderRadius.circular(look.codeRadius),
      border: switch (look.codeBorder) {
        final color? when !header => Border.all(
          color: color,
          width: look.codeBorderWidth,
        ),
        _ => null,
      },
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text.rich(
        TextSpan(
          style: look.code,
          children: [
            for (final token in CodeTokens.of(text, look.syntax(language)))
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
          style: look.code.copyWith(
            color: look.inlineText,
            backgroundColor: look.inlineBackground ?? look.codeBackground,
          ),
        );
      case 'br':
        return const TextSpan(text: '\n');
      case 'a':
        final href = node.attributes['href'];
        final onLink = widget.onLink;
        TapGestureRecognizer? recognizer;
        if (href != null && href.startsWith('#')) {
          recognizer = TapGestureRecognizer()
            ..onTap = () => _outline.show(href.substring(1));
          _recognizers.add(recognizer);
        } else if (href != null && onLink != null) {
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
    this.syntax = _noSyntax,
    this.inlineText,
    this.inlineBackground,
    this.codeHeader,
    this.codeTitle,
    this.callouts = const {},
  });

  static CodeSyntax? _noSyntax(String? language) => null;

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

    // Another style's color, or `null` when it is not written.
    Color? colorOf(String styleName, String prop) {
      final other = theme.styles[styleName]?.resolve(const {});
      if (other == null) {
        return null;
      }
      try {
        return other.color(prop);
      } on StateError {
        return null;
      }
    }

    final link = colorOf('link', 'color');
    Color? callout(String kind) => colorOf('callout', kind);

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
      link: link ?? scheme.primary,
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
      syntax: theme.syntaxOf,
      inlineText: color('inline-text'),
      inlineBackground: color('inline-background'),
      codeHeader:
          color('header') ??
          (color('background') ?? scheme.surfaceContainerHighest),
      codeTitle: color('title') ?? scheme.onSurfaceVariant,
      callouts: {
        'note': callout('note') ?? scheme.primary,
        'tip': callout('tip') ?? scheme.tertiary,
        'important': callout('important') ?? scheme.secondary,
        'warning': callout('warning') ?? scheme.error,
        'caution': callout('caution') ?? scheme.error,
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

  /// The theme's language of a fenced block (`syntax.<name>`).
  final CodeSyntax? Function(String? language) syntax;

  /// Inline code's text color (`styles.code.inline-text`); the code's.
  final Color? inlineText;

  /// Inline code's background (`styles.code.inline-background`); the
  /// block's.
  final Color? inlineBackground;

  /// The fill of a titled block's header (`styles.code.header`).
  final Color? codeHeader;

  /// The title and copy button of a titled block (`styles.code.title`).
  final Color? codeTitle;

  /// The colors of the callouts by kind (`styles.callout.<kind>`).
  final Map<String, Color> callouts;

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
