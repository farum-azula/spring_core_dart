import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/design_scope.dart';
import 'package:spring_boot_starter_flutter/src/text/selection_controls.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_type_scale.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:spring_boot_dart/spring_boot_dart.dart' show BracePlaceholders;
import 'package:spring_boot_starter_flutter/src/theme/content_change.dart';
import 'package:spring_boot_starter_flutter/src/markdown/markdown_outline.dart';
import 'package:spring_boot_starter_flutter/src/markdown/code_tokens.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_values.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_starter_flutter/src/text/text_morph.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_theme_data.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';
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

// A code block shown in one of several palettes, with a button per
// palette above it (`themes="dark light"`).
class _CodePalettes extends StatefulWidget {
  const _CodePalettes(this.blocks, {required this.look});

  final List<(String, Widget)> blocks;
  final _Look look;

  @override
  State<_CodePalettes> createState() => _CodePalettesState();
}

class _CodePalettesState extends State<_CodePalettes> {
  var _shown = 0;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, (label, _)) in widget.blocks.indexed)
              Semantics(
                button: true,
                selected: index == _shown,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _shown = index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: index == _shown
                            ? look.link.withValues(alpha: 0.14)
                            : null,
                        border: Border.all(
                          color: index == _shown ? look.link : look.rule,
                        ),
                        borderRadius: BorderRadius.circular(look.codeRadius),
                      ),
                      child: Text(
                        label,
                        // The page's text colour: the code's may be
                        // made for a dark block.
                        style: look.code.copyWith(
                          color: index == _shown ? look.link : look.body.color,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        widget.blocks[_shown].$2,
      ],
    );
  }
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
            _copied ? _checkIcon : _copyIcon,
            size: 16,
            color: widget.color,
          ),
        ),
      ),
    ),
  );
}

class _MarkdownViewState extends State<MarkdownView>
    with SingleTickerProviderStateMixin {
  var _recognizers = <GestureRecognizer>[];
  // `motion.content-change: morph`: the page's lines come in one after the
  // other as [_appear] runs; [_lines] is how many the last build made,
  // [_line] the one being made.
  late final _appear = AnimationController(vsync: this, value: 1);
  ContentChangeSpec? _morph;
  String? _appearFor;
  int _lines = 0;
  int _line = 0;
  // The links of the content going out while another comes in; disposed at
  // the next change, long after its transition.
  var _retired = <GestureRecognizer>[];
  Object? _builtFor;
  String? _shownFile;
  String? _shown;
  final _ids = <String>{};
  final _headings = <MarkdownHeading>[];
  final _ownOutline = MarkdownOutline();
  // A long page comes in over a few frames: [_built] of its [_cached]
  // blocks this frame, more at each next one, so no frame lays the whole
  // page out (a page of tables took a fifth of a second on the web).
  // [_cachedFor] is what the blocks were made from, [_weights] what each
  // costs, roughly.
  List<Widget>? _cached;
  List<Object?>? _cachedFor;
  var _weights = <int>[];
  int _built = 0;
  Object? _grownFor;
  bool _growing = false;

  // How much of a page one frame builds, in characters of its text (a
  // table cell counts more: its columns are measured).
  static const _frameBudget = 3000;

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

  // The scrollable the page is in: the outline's current heading follows
  // it.
  ScrollPosition? _position;

  void _track() {
    final position = _position;
    if (mounted && position != null) {
      _outline.track(position);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(
      context,
      axis: Axis.vertical,
    )?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_track);
      _position = position?..addListener(_track);
    }
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
    _position?.removeListener(_track);
    if (_outline.buildAll == _buildAll) {
      _outline.buildAll = null;
    }
    _disposeRecognizers();
    _ownOutline.dispose();
    _appear.dispose();
    super.dispose();
  }

  // The morph of the theme's content change when it applies here: a page
  // read from a resource, motion not reduced. Another page starts it over
  // once the page is built and its lines are counted.
  ContentChangeSpec? _morphFor(String? file) {
    final spec = SpringTheme.maybeOf(context)?.contentChange;
    if (spec == null ||
        !spec.morphs ||
        spec.duration <= Duration.zero ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _appearFor = null;
      return null;
    }
    if (file != _appearFor) {
      _appearFor = file;
      _appear
        ..stop()
        ..value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _appearFor == file) {
          _appear
            ..duration = spec.delay + spec.duration
            ..forward(from: 0);
        }
      });
    }
    return spec;
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
    _morph = _morphFor(_shownFile);
    return ContentChange(
      id: _shownFile,
      child: _view(context, shown, content: _shownFile),
    );
  }

  // A line of the page: [span] in [style], with [key]. With the morph it
  // comes in at its turn, [line] (the next one unless given: a list's
  // marker shares its item's).
  Widget _text(InlineSpan span, {TextStyle? style, Key? key, int? line}) {
    final morph = _morph;
    final settled = Text.rich(span, style: style);
    if (morph == null) {
      return key == null ? settled : KeyedSubtree(key: key, child: settled);
    }
    return _MorphLine(
      key: key,
      index: line ?? _line++,
      lines: () => _lines,
      appear: _appear,
      spec: morph,
      span: span,
      style: style,
      settled: settled,
    );
  }

  // The same blocks again: what they were made from has not changed.
  bool _sameAs(List<Object?> made) {
    final cached = _cachedFor;
    if (cached == null || cached.length != made.length) {
      return false;
    }
    for (var i = 0; i < made.length; i++) {
      if (!identical(cached[i], made[i])) {
        return false;
      }
    }
    return true;
  }

  // The blocks of the first frame of a page, then of each next one: up to
  // the frame's budget, at least one.
  int _grow(int from) {
    var spent = 0;
    var to = from;
    while (to < _weights.length && (to == from || spent < _frameBudget)) {
      spent += _weights[to++];
    }
    return to;
  }

  // Builds the rest of the page now: a heading further down is wanted.
  void _buildAll() {
    final cached = _cached;
    if (mounted && cached != null && _built < cached.length) {
      setState(() => _built = cached.length);
    }
  }

  // [markdown] with its `{{key}}` placeholders replaced from the
  // configuration, with `spring.flutter.markdown.placeholders: true`; the
  // same text again while [markdown] is the same, so the blocks are kept.
  String? _resolvedFor;
  String _resolved = '';

  String _withValues(BuildContext context, String markdown) {
    final environment = SpringScope.maybeOf(context)?.environment;
    if (environment == null ||
        environment.getPropertyAs<bool>(
              'spring.flutter.markdown.placeholders',
            ) !=
            true) {
      return markdown;
    }
    if (!identical(markdown, _resolvedFor)) {
      _resolvedFor = markdown;
      _resolved = BracePlaceholders.resolve(markdown, environment.getProperty);
    }
    return _resolved;
  }

  Widget _view(BuildContext context, String source, {Object? content}) {
    final markdown = _withValues(context, source);
    final look = _Look.of(context);
    final made = <Object?>[
      widget,
      markdown,
      SpringTheme.maybeOf(context),
      DefaultTextStyle.of(context).style,
      _morph,
    ];
    if (!_growing || !_sameAs(made)) {
      _renewRecognizers(content ?? markdown);
      _ids.clear();
      _headings.clear();
      _line = 0;
      final nodes = md.Document(
        extensionSet: MarkdownView.syntax,
      ).parse(MarkdownView.withoutFrontMatter(markdown));
      final weights = <int>[];
      _cached = _blocks(nodes, look, weights: weights);
      _weights = weights;
      _cachedFor = made;
      _lines = _line;
      final headings = List.of(_headings);
      final page = _builtFor;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _outline.update(headings, page: page);
          _track();
        }
      });
    }
    _growing = false;
    _outline.buildAll = _buildAll;
    final blocks = _cached!;
    final key = content ?? markdown;
    if (!identical(key, _grownFor) && key != _grownFor) {
      _grownFor = key;
      _built = _grow(0);
    } else {
      _built = _built.clamp(_grow(0), blocks.length);
    }
    if (_built < blocks.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final cached = _cached;
        if (mounted && cached != null && _built < cached.length) {
          setState(() {
            _growing = true;
            _built = _grow(_built);
          });
          // More of the page is laid out: its headings have places now.
          WidgetsBinding.instance.addPostFrameCallback((_) => _track());
        }
      });
    }
    final view = DefaultTextStyle.merge(
      style: look.body,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _built >= blocks.length ? blocks : blocks.sublist(0, _built),
      ),
    );
    if (!widget.selectable) {
      return view;
    }
    // The design library of the app selects text its own way (Material's
    // SelectionArea with its menu); without one the text is selectable
    // with the starter's handles and no menu.
    final design = DesignScope.maybeOf(context);
    if (design != null) {
      return design.selectable(context, view);
    }
    return SelectableRegion(
      selectionControls: SpringTextSelectionControls.instance,
      // No menu: the platform's shortcuts copy. Flutter asks for one at a
      // long press or a right click, so it gets one that shows nothing.
      contextMenuBuilder: (_, _) => const SizedBox.shrink(),
      child: view,
    );
  }

  // The blocks of [nodes] with the gaps between them: none before the
  // first or after the last, more above a heading, less below one.
  // [weights], when given, gets what each block costs to build.
  List<Widget> _blocks(
    List<md.Node> nodes,
    _Look look, {
    List<int>? weights,
  }) {
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
        weights?.add(0);
      }
      result.addAll(blocks);
      if (weights != null) {
        weights.add(_weight(node));
        for (var i = 1; i < blocks.length; i++) {
          weights.add(0);
        }
      }
      previous = node;
    }
    return result;
  }

  // Roughly what [node] costs to build and lay out: its text, and more for
  // a table's cells, whose columns are measured.
  static int _weight(md.Node node) {
    var cells = 0;
    void count(md.Node node) {
      if (node is md.Element) {
        if (node.tag == 'td' || node.tag == 'th') {
          cells++;
        }
        node.children?.forEach(count);
      }
    }

    count(node);
    // A long table builds its first rows only (_LongTable).
    return 40 + node.textContent.length ~/ 4 + math.min(cells, 80) * 60;
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
      return [_text(TextSpan(text: node.text))];
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
          _text(
            key: _outline.keyOf(heading.id, page: _builtFor),
            TextSpan(
              children: [
                for (final span in _inline(children, look))
                  _breakAfterUnderscores(span),
              ],
            ),
            style: look.heading(level),
          ),
        ];
      case 'p':
        return [_text(TextSpan(children: _inline(children, look)))];
      case 'pre':
        final code = children.whereType<md.Element>().firstOrNull;
        final language = code?.attributes['class']?.replaceFirst(
          'language-',
          '',
        );
        final text = _unescape(
          code?.textContent ?? node.textContent,
        ).replaceFirst(RegExp(r'\n$'), '');
        final metadata = _unescape(node.attributes['data-metadata'] ?? '');
        final title = _title.firstMatch(metadata);
        final themes = _themes.firstMatch(metadata);
        final titleText = title == null
            ? null
            : title[1] ?? title[2] ?? title[3];
        final palettes = [
          for (final name
              in (themes == null ? '' : themes[1] ?? themes[2] ?? themes[3]!)
                  .split(RegExp(r'[\s,]+'))
                  .where((name) => name.isNotEmpty))
            ?look.palette(name),
        ];
        if (palettes.isNotEmpty) {
          return [
            _CodePalettes([
              for (final (label, palette) in palettes)
                (
                  label,
                  _codeBlock(text, language, palette, title: titleText),
                ),
            ], look: look),
          ];
        }
        return [_codeBlock(text, language, look, title: titleText)];
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
    // The marker comes in with the item's first line.
    final line = _morph == null ? null : _line;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: _text(TextSpan(text: mark), line: line),
        ),
        Expanded(
          child: blocks
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _blocks(children, look),
                )
              : _text(
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
  static final _themes = RegExp(r'''themes=(?:"([^"]*)"|'([^']*)'|(\S+))''');

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
          _text(
            TextSpan(text: title.toUpperCase()),
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
      if (!look.codeCopy) {
        return block;
      }
      // The copy button in the block's corner, as a titled block has it in
      // its header.
      return Stack(
        // The block keeps the width it has without the button.
        fit: StackFit.passthrough,
        children: [
          block,
          PositionedDirectional(
            top: 6,
            end: 6,
            child: _CopyButton(text, color: look.codeTitle),
          ),
        ],
      );
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
                if (look.codeCopy) _CopyButton(text, color: look.codeTitle),
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
      child: _text(
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
    // A long table: its columns measured from their longest cells, its
    // rows coming in over a few frames.
    if (rows.length > _LongTable.from) {
      return _LongTable(
        [
          for (final row in rows)
            [
              for (var i = 0; i < width; i++)
                switch (row.children?.elementAtOrNull(i)) {
                  final md.Element cell => _cell(cell, look),
                  _ => const _Cell.empty(),
                },
            ],
        ],
        rule: look.rule,
        cellWidth: look.cellWidth,
        fill: look.tableFill,
      );
    }
    // Each column as wide as its text up to `cellWidth`, the text wrapping
    // beyond; a table wider than the view scrolls sideways instead of
    // squeezing its columns. With `tableFill`, a narrower table widens its
    // columns to the view's width, so it lines up with the text.
    final grid = Table(
      border: TableBorder.all(color: look.rule),
      defaultColumnWidth: IntrinsicColumnWidth(flex: look.tableFill ? 1 : null),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var i = 0; i < width; i++)
                Container(
                  constraints: BoxConstraints(maxWidth: look.cellWidth),
                  padding: const EdgeInsets.all(6),
                  child: switch (row.children?.elementAtOrNull(i)) {
                    final md.Element cell => _text(
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: look.tableFill && constraints.hasBoundedWidth
                ? constraints.maxWidth
                : 0,
          ),
          child: grid,
        ),
      ),
    );
  }

  _Cell _cell(md.Element cell, _Look look) {
    final span = TextSpan(children: _inline(cell.children ?? [], look));
    final style = cell.tag == 'th'
        ? const TextStyle(fontWeight: FontWeight.w600)
        : null;
    return _Cell(span, style, _text(span, style: style));
  }

  List<InlineSpan> _inline(List<md.Node> nodes, _Look look) => [
    for (final node in nodes) _span(node, look),
  ];

  // A heading's long identifier (`spring_boot_starter_flutter`) may break
  // after an underscore, not in the middle of a word, on a narrow screen.
  static InlineSpan _breakAfterUnderscores(InlineSpan span) => switch (span) {
    TextSpan(:final text, :final children, :final style) => TextSpan(
      text: text?.replaceAll('_', '_\u200B'),
      style: style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      children: children?.map(_breakAfterUnderscores).toList(),
    ),
    _ => span,
  };

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

// One line of a page coming in with `motion.content-change: morph`: at
// its turn among [lines] (the [index]th start, the starts [spec.stagger]
// apart over at most 85 percent of [spec.duration]) its characters type
// in as `text-change: morph` types a line, from the start. Before its
// turn it holds its place unseen, so the page has its height from the
// first frame; after it, it is [settled].
class _MorphLine extends StatelessWidget {
  const _MorphLine({
    required this.index,
    required this.lines,
    required this.appear,
    required this.spec,
    required this.span,
    required this.style,
    required this.settled,
    super.key,
  });

  final int index;
  final int Function() lines;
  final Animation<double> appear;
  final ContentChangeSpec spec;
  final InlineSpan span;
  final TextStyle? style;
  final Widget settled;

  // How far this line is, 0 to 1, at [value] of the whole change (the
  // delay included).
  double _local(double value) {
    final total = spec.delay + spec.duration;
    final page =
        ((value * total.inMicroseconds - spec.delay.inMicroseconds) /
                spec.duration.inMicroseconds)
            .clamp(0.0, 1.0);
    final progress = spec.curve.transform(page);
    final count = lines();
    final spread =
        (spec.stagger.inMicroseconds /
                spec.duration.inMicroseconds *
                (count - 1))
            .clamp(0.0, 0.85);
    final start = count <= 1 ? 0.0 : spread * index / (count - 1);
    return ((progress - start) / (1 - spread)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final text =
        SpringTheme.maybeOf(context)?.textChange ?? const TextChangeSpec();
    return AnimatedBuilder(
      animation: appear,
      builder: (context, _) {
        final local = _local(appear.value);
        if (local >= 1) {
          return settled;
        }
        if (local <= 0) {
          return Visibility.maintain(visible: false, child: settled);
        }
        // The window one line types in, for the pace of its characters.
        final count = lines();
        final spread =
            (spec.stagger.inMicroseconds /
                    spec.duration.inMicroseconds *
                    (count - 1))
                .clamp(0.0, 0.85);
        final window = spec.duration * (1 - spread);
        final morph = TextMorph(
          count: TextMorph.lengthOf(span),
          progress: local,
          stagger: window == Duration.zero
              ? 0
              : text.stagger.inMicroseconds / window.inMicroseconds,
          seed:
              (local *
                      window.inMicroseconds /
                      text.glyphDuration.inMicroseconds)
                  .floor(),
          glyphs: text.glyphs,
        );
        final (typed, _) = morph.spanOf(span);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Visibility.maintain(visible: false, child: settled),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: Text.rich(typed, style: style),
            ),
          ],
        );
      },
    );
  }
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
    this.cellWidth = 280,
    this.tableFill = true,
    this.codeCopy = true,
    this.codeStyle = _noStyle,
  });

  static StyleValues? _noStyle(String name) => null;

  /// A style of the theme by name (`code-dark` for the palette `dark`).
  final StyleValues? Function(String name) codeStyle;

  /// The look of a code block in the palette [name], the theme's style
  /// `code-<name>` (`themes="dark light"` after a block's language), with
  /// its label (`label`, else the name); `null` when the theme has none.
  (String, _Look)? palette(String name) {
    final values = codeStyle('code-$name');
    if (values == null) {
      return null;
    }
    T? read<T>(T Function() get) {
      try {
        return get();
      } on StateError {
        return null; // not set
      }
    }

    Color? color(String prop) => read(() => values.color(prop));
    final background = color('background') ?? codeBackground;
    return (
      read(() => values.text('label')) ?? name,
      _Look(
        body: body,
        code: code.copyWith(color: color('text') ?? code.color),
        codeBackground: background,
        codePadding: codePadding,
        codeRadius: codeRadius,
        codeBorder: color('border') ?? codeBorder,
        codeBorderWidth: codeBorderWidth,
        link: link,
        rule: rule,
        headings: headings,
        tokens: {
          for (final MapEntry(:key, :value) in tokens.entries)
            key: color(key.name) ?? value,
        },
        syntax: syntax,
        inlineText: inlineText,
        inlineBackground: inlineBackground,
        codeHeader: color('header') ?? background,
        codeTitle: color('title') ?? codeTitle,
        callouts: callouts,
        cellWidth: cellWidth,
        tableFill: tableFill,
        codeCopy: codeCopy,
        codeStyle: codeStyle,
      ),
    );
  }

  static CodeSyntax? _noSyntax(String? language) => null;

  // What Theme.of gives in a MaterialApp: the style of the design's theme
  // when the app has a design library, else the theme's own with the sizes
  // of the locale's script (the Material 3 type scale).
  static TextStyle _style(
    BuildContext context,
    SpringThemeData theme,
    String name,
  ) =>
      DesignScope.maybeOf(context)?.textStyle(context, name) ??
      theme.localizedTextStyle(
        name,
        SpringTypeScale.scriptOf(Localizations.maybeLocaleOf(context)),
      );

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
    final table = theme.styles['table']?.resolve(const {});
    T? tableValue<T>(T Function(StyleValues values) read) {
      if (table == null) {
        return null;
      }
      try {
        return read(table);
      } on StateError {
        return null; // not set, or not of its kind
      }
    }

    final cellWidth = tableValue((values) => values.number('cell-width'));
    final tableFill = tableValue((values) => values.flag('fill'));
    bool? codeCopy;
    try {
      codeCopy = theme.styles['code']?.resolve(const {}).flag('copy');
    } on StateError {
      codeCopy = null; // not set, or not true or false
    }
    Color? callout(String kind) => colorOf('callout', kind);

    // The styles with the sizes of the locale's script (a SpringTheme's
    // own text styles have only what was set).
    TextStyle text(String name) => _style(context, theme, name);
    final roles = [
      text('headlinelarge'),
      text('headlinemedium'),
      text('headlinesmall'),
      text('titlelarge'),
      text('titlemedium'),
      text('titlesmall'),
    ];
    final code = text('bodymedium').merge(theme.textStyle('code'));
    return _Look(
      body: text('bodylarge'),
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
      // `styles.heading`: `color` for every level, `h1` ... `h6` for one.
      headings: {
        for (var level = 1; level <= 6; level++)
          'h$level': switch (colorOf('heading', 'h$level') ??
              colorOf('heading', 'color')) {
            final color? => roles[level - 1].copyWith(color: color),
            null => roles[level - 1],
          },
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
      cellWidth: cellWidth ?? 280,
      tableFill: tableFill ?? true,
      codeCopy: codeCopy ?? true,
      codeStyle: (name) {
        try {
          // Styles are kept by canonical name (`code-night` is codenight).
          return theme.styles[ThemeValues.canonical(name)]?.resolve(const {});
        } on StateError {
          return null;
        }
      },
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

  /// The widest a table's column grows before its text wraps
  /// (`styles.table.cell-width`); a table wider than the view scrolls
  /// sideways.
  final double cellWidth;

  /// Whether a table narrower than the view widens its columns to the
  /// view's width (`styles.table.fill`, `true` by default).
  final bool tableFill;

  /// Whether every code block has a button that copies its text
  /// (`styles.code.copy`, `true` by default).
  final bool codeCopy;

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

// A cell of a long table: its text, to measure the column, and the widget
// shown.
final class _Cell {
  const _Cell(this.span, this.style, this.child);

  const _Cell.empty() : span = null, style = null, child = const SizedBox();

  final InlineSpan? span;
  final TextStyle? style;
  final Widget child;

  int get length => span?.toPlainText().length ?? 0;
}

// A table of many rows: each column as wide as its longest cells (up to
// `cellWidth`), measured once, and the rows coming in a few at a frame (up
// to [budget] characters), so no frame lays out the whole table and
// measures every cell twice as [IntrinsicColumnWidth] does.
class _LongTable extends StatefulWidget {
  const _LongTable(
    this.rows, {
    required this.rule,
    required this.cellWidth,
    required this.fill,
  });

  // A table of more rows than this is a long one.
  static const from = 30;
  // The characters of the rows one frame adds (a cell counts some more).
  static const budget = 1500;
  // The cells of a column measured: its longest ones by their text.
  static const measured = 4;
  static const padding = 6.0;

  final List<List<_Cell>> rows;
  final Color rule;
  final double cellWidth;
  final bool fill;

  @override
  State<_LongTable> createState() => _LongTableState();
}

class _LongTableState extends State<_LongTable> {
  // Where the pieces added frame after frame end: each is a [Table].
  late final _ends = [_next(0)];
  List<double>? _widths;

  // The end of the piece from row [from]: rows up to the budget, one at
  // least.
  int _next(int from) {
    final rows = widget.rows;
    var spent = 0;
    var to = from;
    while (to < rows.length && (to == from || spent < _LongTable.budget)) {
      for (final cell in rows[to++]) {
        spent += cell.length + 10;
      }
    }
    return to;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _widths = null;
  }

  @override
  void didUpdateWidget(_LongTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rows, widget.rows)) {
      _widths = null;
      _ends.removeWhere((end) => end > widget.rows.length);
      if (_ends.isEmpty) {
        _ends.add(_next(0));
      }
    }
  }

  List<double> _measure(BuildContext context) {
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final columns = widget.rows.fold(0, (n, row) => math.max(n, row.length));
    return [
      for (var column = 0; column < columns; column++)
        () {
          final cells = [
            for (final row in widget.rows)
              if (column < row.length && row[column].span != null) row[column],
          ]..sort((a, b) => b.length.compareTo(a.length));
          var text = 0.0;
          for (final cell in cells.take(_LongTable.measured)) {
            final painter = TextPainter(
              text: TextSpan(
                style: base.merge(cell.style),
                children: [cell.span!],
              ),
              textDirection: direction,
              textScaler: scaler,
            )..layout();
            text = math.max(text, painter.maxIntrinsicWidth);
            painter.dispose();
          }
          return math.min(
            (text + _LongTable.padding * 2 + 1).ceilToDouble(),
            widget.cellWidth,
          );
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final measured = _widths ??= _measure(context);
    if (_ends.last < rows.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ends.last < widget.rows.length) {
          setState(() => _ends.add(_next(_ends.last)));
        }
      });
    }
    final side = BorderSide(color: widget.rule);
    return LayoutBuilder(
      builder: (context, constraints) {
        var widths = measured;
        final total = widths.fold(0.0, (sum, w) => sum + w);
        // Like the flex of a short table: what the view has left is shared
        // out evenly.
        if (widget.fill &&
            constraints.hasBoundedWidth &&
            total < constraints.maxWidth &&
            widths.isNotEmpty) {
          final extra = (constraints.maxWidth - total) / widths.length;
          widths = [for (final w in widths) w + extra];
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: widths.fold<double>(0, (sum, w) => sum + w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (piece, end) in _ends.indexed)
                  Table(
                    // One line between two pieces: the upper one's bottom.
                    border: TableBorder(
                      top: piece == 0 ? side : BorderSide.none,
                      bottom: side,
                      left: side,
                      right: side,
                      horizontalInside: side,
                      verticalInside: side,
                    ),
                    columnWidths: {
                      for (final (i, w) in widths.indexed)
                        i: FixedColumnWidth(w),
                    },
                    children: [
                      for (final row in rows.sublist(
                        piece == 0 ? 0 : _ends[piece - 1],
                        end,
                      ))
                        TableRow(
                          children: [
                            for (var i = 0; i < widths.length; i++)
                              Padding(
                                padding: const EdgeInsets.all(
                                  _LongTable.padding,
                                ),
                                child: i < row.length
                                    ? row[i].child
                                    : const SizedBox(),
                              ),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// The two icons of the copy button, of the Material Icons font (an app
// has it with `uses-material-design: true`); constants, so that the build
// keeps only their glyphs.
const _copyIcon = IconData(0xf66c, fontFamily: 'MaterialIcons');
const _checkIcon = IconData(0xf636, fontFamily: 'MaterialIcons');
