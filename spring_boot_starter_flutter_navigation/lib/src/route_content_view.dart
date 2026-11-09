import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_template.dart';

/// The Markdown of the screen's route (`content:` of `@ScreenRoute`), shown
/// with [MarkdownView]: a link to another Markdown file of the site opens
/// its screen (`beans.md#scopes` from `/docs/core/configuration` goes to
/// `/docs/core/beans#scopes`), as on the pages the build writes for search
/// engines; any other link goes to [onLink].
///
/// ```dart
/// @ScreenRoute('/docs/{*path}', content: 'resources:content/docs/')
/// class DocPage extends StatelessWidget {
///   const DocPage({super.key});
///
///   @override
///   Widget build(BuildContext context) =>
///       const SingleChildScrollView(child: RouteContentView());
/// }
/// ```
class RouteContentView extends StatelessWidget {
  /// The content of the widget's screen; [onLink] gets the links that are
  /// no file of the site (an `https` address).
  const RouteContentView({
    this.onLink,
    this.selectable = true,
    this.outline,
    this.scrollToTop = true,
    super.key,
  });

  /// Whether another page of the route (another address, not an `#anchor`
  /// or a translation of the same page) starts at the top of the
  /// scrollable it is in, as a browser opens a page. The screen and its
  /// scrollable stay; the position goes back the theme's way
  /// (`motion.scroll-to-top`: 400ms ease-out-cubic by default, `none` to
  /// jump).
  final bool scrollToTop;

  /// Called with a link to no Markdown file of the site.
  final void Function(String href)? onLink;

  /// Gets the page's headings ("On this page"); the address's `#anchor`
  /// scrolls to its heading either way.
  final MarkdownOutline? outline;

  /// Whether the text can be selected.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final route = context.route;
    final content = route.content;
    if (content == null) {
      throw FlutterError(
        'RouteContentView needs a route with content '
        '(@ScreenRoute(content: ...)); ${route.pattern} has none.',
      );
    }
    final navigation = context
        .dependOnInheritedWidgetOfExactType<ScreenScope>()!
        .navigation;
    // The translation in the address's language (`beans.ja.md` next to
    // `beans.md`), when there is one; again when the language changes.
    return ValueListenableBuilder<String?>(
      valueListenable: navigation.languageListenable,
      builder: (context, language, _) =>
          _view(context, route, navigation, content, language),
    );
  }

  Widget _view(
    BuildContext context,
    RouteTemplate route,
    Navigation navigation,
    String content,
    String? language,
  ) {
    final file = fileOf(SpringScope.of(context), navigation, content, language);
    return _FragmentScroll(
      outline: outline,
      fragment: route.uri.fragment,
      file: file,
      page: scrollToTop ? content : null,
      builder: (outline) => MarkdownView.resource(
        file,
        selectable: selectable,
        outline: outline,
        onLink: (href) {
          final target = contentAddress(navigation, file, href);
          if (target != null) {
            route.go(target);
          } else {
            onLink?.call(href);
          }
        },
      ),
    );
  }

  /// The file [content] (a route's `content` for its address) shows in
  /// [language]: `<path>.md`, or `<path>/index.md` when the address is a
  /// folder; its translation `<file>.<language>.md` next to it when there
  /// is one and [language] is not the first of the navigation's.
  static String fileOf(
    ResourceLoader resources,
    Navigation navigation,
    String content,
    String? language,
  ) {
    var file = content;
    if (file.endsWith('.md') &&
        !file.endsWith('/index.md') &&
        !resources.getResource(file).exists()) {
      final folder =
          '${file.substring(0, file.length - '.md'.length)}/index.md';
      if (resources.getResource(folder).exists()) {
        file = folder;
      }
    }
    if (language != null &&
        language != navigation.languages.firstOrNull &&
        file.endsWith('.md')) {
      final translation =
          '${file.substring(0, file.length - '.md'.length)}.$language.md';
      if (resources.getResource(translation).exists()) {
        file = translation;
      }
    }
    return file;
  }

  /// The address of the site that [href], a link of the Markdown resource
  /// [from], points at: a relative `.md` link to a file of a route's
  /// content folder; `null` for anything else.
  static RouteLocation? contentAddress(
    Navigation navigation,
    String from,
    String href,
  ) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.hasScheme ||
        href.startsWith('/') ||
        !uri.path.endsWith('.md')) {
      return null;
    }
    final target = _hierarchical(from).resolve(uri.path);
    var file = target.path;
    // A link to a translation (`beans.ja.md`) is the page of `beans.md`.
    for (final language in navigation.languages.skip(1)) {
      if (file.endsWith('.$language.md')) {
        file = '${file.substring(0, file.length - '.$language.md'.length)}.md';
      }
    }
    for (final screen in navigation.table.screens) {
      final folder = screen.content;
      final rest = screen.restVariable;
      if (folder == null) {
        continue;
      }
      final folderUri = _hierarchical(folder);
      // A folder of another root (`asset:` against `resources:`) is not it.
      if (folderUri.scheme != target.scheme) {
        continue;
      }
      final base = folderUri.path;
      if (!folder.endsWith('/')) {
        if (base == file && rest == null) {
          return RouteLocation(
            screen.pattern.pattern,
            fragment: _fragment(uri),
          );
        }
        continue;
      }
      if (rest == null || !file.startsWith(base)) {
        continue;
      }
      var name = file.substring(base.length, file.length - '.md'.length);
      if (name == 'index') {
        name = '';
      } else if (name.endsWith('/index')) {
        name = name.substring(0, name.length - '/index'.length);
      }
      final pattern = screen.pattern.pattern;
      final prefix = pattern.substring(0, pattern.indexOf('{*'));
      final root = prefix.endsWith('/') && prefix.length > 1
          ? prefix.substring(0, prefix.length - 1)
          : prefix;
      final path = name.isEmpty ? root : '$root/$name';
      return RouteLocation(path.isEmpty ? '/' : path, fragment: _fragment(uri));
    }
    return null;
  }

  static String? _fragment(Uri uri) => uri.hasFragment ? uri.fragment : null;

  // [location] (`resources:content/a.md`, `asset:docs/a.md`) as a URI
  // with a path, so a relative link resolves against it.
  static Uri _hierarchical(String location) {
    final scheme = RegExp(r'^([a-zA-Z][\w+.-]*):(?!/)').firstMatch(location);
    return Uri.parse(
      scheme == null
          ? location
          : location.replaceRange(0, scheme.end, '${scheme[1]}:/'),
    );
  }
}

// Scrolls to the address's [fragment] once the headings of [file] are
// known, again when the address or the file changes.
class _FragmentScroll extends StatefulWidget {
  const _FragmentScroll({
    required this.outline,
    required this.fragment,
    required this.file,
    required this.page,
    required this.builder,
  });

  // The page shown, whatever its language; `null` when another page keeps
  // the scroll position.
  final String? page;

  final MarkdownOutline? outline;
  final String fragment;
  final String file;
  final Widget Function(MarkdownOutline outline) builder;

  @override
  State<_FragmentScroll> createState() => _FragmentScrollState();
}

class _FragmentScrollState extends State<_FragmentScroll> {
  final _own = MarkdownOutline();
  MarkdownOutline? _listened;
  String? _done;

  MarkdownOutline get _outline => widget.outline ?? _own;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(_FragmentScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listen();
    final page = widget.page;
    if (page != null &&
        oldWidget.page != null &&
        page != oldWidget.page &&
        widget.fragment.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final position = Scrollable.maybeOf(context)?.position;
        if (position == null || !position.hasContentDimensions) {
          return;
        }
        final motion = SpringTheme.maybeOf(context)?.scrollToTop;
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (motion == null || reduce || motion.duration == Duration.zero) {
          position.jumpTo(position.minScrollExtent);
        } else {
          unawaited(
            position.animateTo(
              position.minScrollExtent,
              duration: motion.duration,
              curve: motion.curve,
            ),
          );
        }
      });
    }
    if (oldWidget.fragment != widget.fragment ||
        oldWidget.file != widget.file) {
      _done = null;
      _scroll();
    }
  }

  void _listen() {
    if (identical(_listened, _outline)) {
      return;
    }
    _listened?.removeListener(_scroll);
    _listened = _outline..addListener(_scroll);
  }

  void _scroll() {
    final wanted = '${widget.file}#${widget.fragment}';
    if (widget.fragment.isEmpty || _done == wanted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _outline.show(widget.fragment)) {
        _done = wanted;
      }
    });
  }

  @override
  void dispose() {
    _listened?.removeListener(_scroll);
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_outline);
}
