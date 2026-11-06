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
  const RouteContentView({this.onLink, this.selectable = true, super.key});

  /// Called with a link to no Markdown file of the site.
  final void Function(String href)? onLink;

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
    var file = content;
    if (language != null &&
        language != navigation.languages.firstOrNull &&
        content.endsWith('.md')) {
      final translation =
          '${content.substring(0, content.length - '.md'.length)}.$language.md';
      if (SpringScope.of(context).getResource(translation).exists()) {
        file = translation;
      }
    }
    return MarkdownView.resource(
      file,
      key: ValueKey(file),
      selectable: selectable,
      onLink: (href) {
        final target = contentAddress(navigation, content, href);
        if (target != null) {
          route.go(target);
        } else {
          onLink?.call(href);
        }
      },
    );
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
    var file = Uri.parse(from.replaceFirst('resources:', 'resources:/'))
        .resolve(uri.path)
        .path;
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
      final base = Uri.parse(
        folder.replaceFirst('resources:', 'resources:/'),
      ).path;
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
}
