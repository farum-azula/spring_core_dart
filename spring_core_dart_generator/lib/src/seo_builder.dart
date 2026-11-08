import 'dart:convert';
import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:spring_core_dart/core.dart';
import 'package:spring_core_dart_generator/src/package_directory.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:yaml/yaml.dart';

/// Writes the pages search engines, link previews and models read for a
/// Flutter web app (`spring.flutter.web.seo.*`), since the app itself draws
/// on a canvas and its HTML holds no text.
///
/// For every page it writes `web/<path>/index.html`: a copy of
/// `web/index.html` (the page loader included) with the page's `<head>`
/// (title, description, `canonical`, `og:*`, `robots`, the Markdown
/// alternate) and its text in plain HTML in `<main id="spring-content">`,
/// under the loader and then under Flutter's view: never shown, never
/// removed, the same text the app shows (both come from one Markdown
/// file). The root page goes into `web/index.html` itself, between
/// `spring:seo` markers. Next to them: `<path>.md` (the Markdown as
/// written), `sitemap.xml`, `robots.txt`, `llms.txt` (a map of the `.md`
/// pages) and `llms-full.txt` (all of them). `flutter build web` copies
/// them into `build/web`; the files it wrote are listed in
/// `web/.spring-seo`, so a page that is gone is deleted.
///
/// The pages come from:
/// - the screens of `spring_boot_starter_flutter_navigation`
///   (`from-routes: true`): a path without variables, a route's Markdown
///   folder (`content: 'resources:content/docs/'` on `/docs/{*path}`, a
///   page per file), `@RouteInfo(paths: [...])`; not a guarded screen
///   (`@PreAuthorize`) nor one with `@RouteInfo(index: false)` in the
///   sitemap;
/// - the Markdown folders of `content[n]` (`location`, `path`, `exclude`);
/// - `pages[n]` (`path`, `title`, `description`, `image`, `index`), which
///   also override what a route says.
///
/// A Markdown link to another file of the site becomes the site's address
/// (`beans.md#scopes` is `/docs/core/beans#scopes`); a link to a file that
/// is no page fails the build, as do two files on one address.
final class SeoBuilder implements Builder {
  /// The builder; [files] reads and writes the app's own files (on disk
  /// unless given; tests pass files held in memory).
  SeoBuilder({SeoFiles? files, SeoDates? dates})
    : _files = files ?? const _Disk(),
      _dates = dates ?? const _GitDates();

  final SeoFiles _files;
  final SeoDates _dates;

  /// The prefix of the properties read.
  static const prefix = 'spring.flutter.web.seo';

  /// The list of the files the last build wrote, below `web/`.
  static const ledger = 'web/.spring-seo';

  @override
  Map<String, List<String>> get buildExtensions => const {r'$package$': []};

  @override
  Future<void> build(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final resources = await SpringBuilder.resources(buildStep, warn: false);
    final texts = {
      for (final MapEntry(:key, value: (:text, base64: _)) in resources.entries)
        key: ?text,
    };
    final previous = await _files.read(buildStep, package, ledger);
    SeoSettings? settings;
    if (texts.values.any((t) => t.contains('seo'))) {
      try {
        settings = SeoSettings.of(
          readPlatformEnvironment(texts, profiles: const ['web']),
        );
      } on WebDevConfigException catch (e) {
        log.severe('$e\nThe pages of $prefix are not written.');
        return;
      }
    }
    final template = await _files.read(buildStep, package, 'web/index.html');
    if (settings == null || template == null) {
      if (settings != null) {
        log.warning('$prefix.enabled is set but web/index.html is missing.');
      }
      await _clean(buildStep, package, previous, const {});
      if (template != null) {
        final cleaned = SeoPages.withoutRoot(template);
        if (cleaned != template) {
          await _files.write(buildStep, package, 'web/index.html', cleaned);
        }
      }
      return;
    }
    final routes = settings.fromRoutes
        ? await _routes(buildStep, package)
        : const <Map<String, Object?>>[];
    final Map<String, String> output;
    try {
      output = SeoPages(
        settings,
        texts: texts,
        routes: routes,
        template: template,
        modified: settings.lastmod
            ? await _dates.of(package)
            : const <String, String>{},
      ).render();
    } on SeoException catch (e) {
      log.severe('$e');
      return;
    }
    for (final MapEntry(key: path, value: content) in output.entries) {
      await _files.write(buildStep, package, path, content);
    }
    await _clean(buildStep, package, previous, output.keys.toSet());
    await _files.write(
      buildStep,
      package,
      ledger,
      _ledger(output.keys),
    );
  }

  static String _ledger(Iterable<String> written) {
    final paths = [
      for (final path in written)
        if (path != 'web/index.html') path,
    ]..sort();
    return '${paths.join('\n')}\n';
  }

  Future<void> _clean(
    BuildStep buildStep,
    String package,
    String? previous,
    Set<String> written,
  ) async {
    for (final path in LineSplitter.split(previous ?? '')) {
      if (path.trim().isNotEmpty &&
          path.startsWith('web/') &&
          !written.contains(path)) {
        await _files.delete(buildStep, package, path);
      }
    }
    if (written.isEmpty && previous != null) {
      await _files.delete(buildStep, package, ledger);
    }
  }

  Future<List<Map<String, Object?>>> _routes(
    BuildStep buildStep,
    String package,
  ) async {
    final id = AssetId(package, 'lib/spring_gen/spring_metadata.json');
    if (!await buildStep.canRead(id)) {
      return const [];
    }
    final json = jsonDecode(await buildStep.readAsString(id));
    final routes = json is Map ? json['routes'] : null;
    return [
      if (routes is List)
        for (final route in routes)
          if (route is Map) route.cast<String, Object?>(),
    ];
  }
}

/// A configuration the build cannot make pages of.
final class SeoException implements Exception {
  /// The problem, [message].
  SeoException(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => message;
}

/// A Markdown folder of the configuration: `content[n]`.
typedef ContentGroup = ({String location, String path, List<String> exclude});

/// A page of the configuration: `pages[n]`.
typedef PageOverride = ({
  String path,
  String? title,
  String? description,
  String? image,
  bool? index,
});

/// How the SEO build names a page's file (`spring.flutter.web.seo.page-files`).
enum SeoPageFiles {
  /// `<path>/index.html`: any static host serves it, after a redirect from
  /// `<path>` to `<path>/`; the page's addresses end with `/`.
  directory,

  /// `<path>.html`: Cloudflare Pages, GitHub Pages and Netlify serve it at
  /// `<path>` itself, with no redirect; the addresses have no `/` at the
  /// end.
  html,
}

/// `spring.flutter.web.seo.*` as the app reads it in a browser.
final class SeoSettings {
  SeoSettings._({
    required this.siteUrl,
    required this.fromRoutes,
    required this.title,
    required this.description,
    required this.image,
    required this.siteName,
    required this.content,
    required this.pages,
    required this.sitemap,
    required this.llms,
    required this.markdown,
    this.lastmod = true,
    this.exclude = const [],
    this.pageFiles = SeoPageFiles.directory,
    this.languages = const [],
  });

  /// The settings in [environment]; `null` unless `enabled` is `true`.
  /// Throws [WebDevConfigException] without a site URL.
  static SeoSettings? of(PropertyResolver environment) {
    String? string(String name) {
      final value = environment
          .getProperty('${SeoBuilder.prefix}.$name')
          ?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    bool flag(String name, bool fallback) =>
        switch (string(name)?.toLowerCase()) {
          'true' => true,
          'false' => false,
          _ => fallback,
        };

    List<String> list(String name) {
      final whole = string(name);
      return [
        if (whole != null)
          for (final part in whole.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        for (var i = 0; string('$name[$i]') != null; i++) string('$name[$i]')!,
      ];
    }

    if (!flag('enabled', false)) {
      return null;
    }
    // The languages with their own addresses, the navigation's
    // (`spring.flutter.navigation.languages`): the first is the default.
    final languages = <String>[];
    final whole = environment
        .getProperty('spring.flutter.navigation.languages')
        ?.trim();
    if (whole != null && whole.isNotEmpty) {
      languages.addAll([
        for (final part in whole.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ]);
    }
    for (var i = 0; ; i++) {
      final one = environment
          .getProperty('spring.flutter.navigation.languages[$i]')
          ?.trim();
      if (one == null || one.isEmpty) {
        break;
      }
      languages.add(one);
    }
    for (final language in languages) {
      if (!RegExp(r'^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$').hasMatch(language)) {
        throw WebDevConfigException(
          'spring.flutter.navigation.languages: "$language" is no language '
          'tag (en, ja, pt-BR).',
        );
      }
    }
    final files = string('page-files')?.toLowerCase();
    if (files != null && files != 'directory' && files != 'html') {
      throw WebDevConfigException(
        '${SeoBuilder.prefix}.page-files: "$files" is directory '
        '(<path>/index.html) or html (<path>.html).',
      );
    }
    final site = string('site-url');
    final uri = site == null ? null : Uri.tryParse(site);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw WebDevConfigException(
        "${SeoBuilder.prefix}.site-url must be the site's address "
        '(https://spring-dart.dev) when ${SeoBuilder.prefix}.enabled is true.',
      );
    }
    return SeoSettings._(
      siteUrl: uri,
      fromRoutes: flag('from-routes', false),
      exclude: list('exclude'),
      title: string('title') ?? '{title}',
      description: string('description'),
      image: string('image'),
      siteName: string('site-name'),
      content: [
        for (var i = 0; string('content[$i].location') != null; i++)
          (
            location: string('content[$i].location')!,
            path: string('content[$i].path') ?? '/',
            exclude: [
              ...list('content[$i].exclude'),
              ...list('exclude'),
            ],
          ),
      ],
      pages: [
        for (var i = 0; string('pages[$i].path') != null; i++)
          (
            path: string('pages[$i].path')!,
            title: string('pages[$i].title'),
            description: string('pages[$i].description'),
            image: string('pages[$i].image'),
            index: switch (string('pages[$i].index')?.toLowerCase()) {
              'true' => true,
              'false' => false,
              _ => null,
            },
          ),
      ],
      sitemap: flag('sitemap', true),
      llms: flag('llms', true),
      markdown: flag('markdown', true),
      lastmod: flag('lastmod', true),
      pageFiles: files == 'html' ? SeoPageFiles.html : SeoPageFiles.directory,
      languages: languages,
    );
  }

  /// The site's address; its path is where the app is served.
  final Uri siteUrl;

  /// Whether the screens of the navigation make pages.
  final bool fromRoutes;

  /// Files of every Markdown folder, the routes' and `content[n]`'s, that
  /// make no page (`exclude`: globs from the folder, `**/contents*.md`):
  /// a table of contents a site reads for its menu.
  final List<String> exclude;

  /// The `<title>` pattern, `{title}` the page's.
  final String title;

  /// The description of a page that has none.
  final String? description;

  /// The preview image of a page that has none.
  final String? image;

  /// The site's name in a link preview (`og:site_name`).
  final String? siteName;

  /// The Markdown folders.
  final List<ContentGroup> content;

  /// The pages by hand.
  final List<PageOverride> pages;

  /// Whether `sitemap.xml` and `robots.txt` are written.
  final bool sitemap;

  /// Whether `llms.txt` and `llms-full.txt` are written.
  final bool llms;

  /// Whether `<path>.md` is written next to a Markdown page.
  final bool markdown;

  /// Whether the sitemap gives each Markdown page its `lastmod`: the day
  /// of the last commit that changed its file (`git log`).
  final bool lastmod;

  /// How a page's file is named (`page-files`).
  final SeoPageFiles pageFiles;

  /// The file of the page at [path] under `web/`: `<path>/index.html` or
  /// `<path>.html`.
  String fileOf(String path) =>
      pageFiles == SeoPageFiles.html ? 'web$path.html' : 'web$path/index.html';

  /// The absolute address of the page at [path], as the host serves its
  /// file without a redirect: a static host answers `<path>` with
  /// `<path>/index.html` only after a redirect to `<path>/`, and serves
  /// `<path>.html` at `<path>` itself. The canonical address, `og:url`,
  /// the languages' links and the sitemap use it.
  String pageUrl(String path) =>
      pageFiles == SeoPageFiles.directory && path != '/'
      ? '${url(path)}/'
      : url(path);

  /// The languages with their own addresses, the default first
  /// (`spring.flutter.navigation.languages`); empty for one language.
  final List<String> languages;

  /// The language of the addresses without a prefix, or `null`.
  String? get defaultLanguage => languages.firstOrNull;

  /// The languages under `/<language>/...`.
  List<String> get otherLanguages => languages.skip(1).toList();

  /// The path the app is served under, starting and ending with `/`.
  String get basePath {
    final path = siteUrl.path;
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.endsWith('/') ? path : '$path/';
  }

  /// The absolute address of the site's [path].
  String url(String path) {
    final base = Uri(
      scheme: siteUrl.scheme,
      host: siteUrl.host,
      port: siteUrl.hasPort ? siteUrl.port : null,
    );
    final prefix = basePath == '/'
        ? ''
        : basePath.substring(0, basePath.length - 1);
    return '${base.toString().replaceAll(RegExp(r'/$'), '')}$prefix'
        '${path == '/' ? '/' : path}';
  }
}

// One page of the site.
final class _Page {
  _Page(this.path);

  final String path;
  String? title;
  String? description;
  String? image;
  bool index = true;
  // The Markdown of the page, its file below lib/resources/, its front
  // matter left out.
  String? markdown;
  String? file;
  // The title and description as written (`#{key}` not yet translated),
  // for the other languages.
  String? titleSource;
  String? descriptionSource;
  // A page of another language without its own Markdown: written with the
  // default language's text, its canonical address the default page's,
  // out of the sitemap and of the alternates.
  bool fallback = false;
}

/// Makes the files of the pages of [settings].
final class SeoPages {
  /// The pages of [settings] from the config files [texts] (below
  /// `lib/resources/`), the [routes] of the metadata and [template], the
  /// app's `web/index.html`.
  SeoPages(
    this.settings, {
    required this.texts,
    required this.routes,
    required this.template,
    this.modified = const {},
  });

  /// The day each file below `lib/resources/` last changed (`2026-11-08`),
  /// for the sitemap's `lastmod`; a file without one has none.

  /// What to make.
  final SeoSettings settings;

  /// The files of `lib/resources/`.
  final Map<String, String> texts;

  /// The screens (`spring_metadata.json`).
  final List<Map<String, Object?>> routes;

  /// The app's page.
  final String template;

  /// See the constructor.
  final Map<String, String> modified;

  static const String _headStart = WebPageHead.seoHeadStart;
  static const _headEnd = '<!-- spring:seo:head:end -->';
  static const _bodyStart = '<!-- spring:seo:content:start -->';
  static const _bodyEnd = '<!-- spring:seo:content:end -->';

  /// [html] without the blocks the build put into the root page.
  static String withoutRoot(String html) => html
      .replaceAll(
        RegExp(
          '[ \\t]*${RegExp.escape(_headStart)}[\\s\\S]*?'
          '${RegExp.escape(_headEnd)}\\n?',
        ),
        '',
      )
      .replaceAll(
        RegExp(
          '[ \\t]*${RegExp.escape(_bodyStart)}[\\s\\S]*?'
          '${RegExp.escape(_bodyEnd)}\\n?',
        ),
        '',
      );

  // The Markdown page of each file, by the file's path below
  // lib/resources/.
  final _byFile = <String, _Page>{};

  /// The files to write, by their path in the package.
  Map<String, String> render() {
    final pages = <String, _Page>{};
    void add(_Page page, String origin) {
      final twin = pages[page.path];
      if (twin != null &&
          twin.file != null &&
          page.file != null &&
          twin.file != page.file) {
        throw SeoException(
          'Two files make the page ${page.path}: ${twin.file} and '
          '${page.file}.',
        );
      }
      pages[page.path] = twin ?? page;
      if (page.file case final file?) {
        final other = _byFile[file];
        if (other != null && other.path != page.path) {
          throw SeoException(
            'The file $file makes two pages: ${other.path} and ${page.path} '
            '($origin).',
          );
        }
        _byFile[file] = pages[page.path]!;
      }
    }

    if (settings.fromRoutes) {
      for (final route in routes) {
        for (final page in _routePages(route)) {
          add(page, 'the route ${route['path']}');
        }
      }
    }
    for (final group in settings.content) {
      for (final page in _folder(group.location, group.path, group.exclude)) {
        add(page, 'content ${group.location}');
      }
    }
    for (final override in settings.pages) {
      final page = pages[override.path] ?? _Page(override.path);
      page
        ..title = _text(override.title) ?? page.title
        ..description = _text(override.description) ?? page.description
        ..titleSource = override.title ?? page.titleSource
        ..descriptionSource = override.description ?? page.descriptionSource
        ..image = override.image ?? page.image
        ..index = override.index ?? page.index;
      pages[override.path] = page;
    }
    // The pages of the other languages, by language and path.
    final translated = <String, Map<String, _Page>>{
      for (final language in settings.otherLanguages)
        language: {
          for (final page in pages.values)
            page.path: _translated(page, language),
        },
    };
    // The addresses of [path] in every language that has its text.
    Map<String, String> alternates(String path) => {
      ?settings.defaultLanguage: settings.pageUrl(path),
      for (final MapEntry(key: language, value: byPath) in translated.entries)
        if (byPath[path] case final page? when !page.fallback)
          language: settings.pageUrl(_prefixed(language, path)),
    };

    final headings = _headings(pages);
    final translatedHeadings = {
      for (final MapEntry(key: language, value: byPath) in translated.entries)
        language: _headings(byPath),
    };

    final base = _baseTemplate();
    final files = <String, String>{};
    var root = withoutRoot(template);
    for (final page in pages.values) {
      final body = page.markdown == null ? null : _html(page);
      final links = alternates(page.path);
      final crumbs = _crumbs(page.path, pages, (at) => at);
      if (page.path == '/') {
        root = _page(
          root,
          page,
          body,
          root: true,
          language: settings.defaultLanguage,
          alternates: links,
          heading: headings[page.path],
        );
        if (settings.markdown && page.markdown != null) {
          files['web${_markdownAt('/')}'] = page.markdown!;
        }
        continue;
      }
      files[settings.fileOf(page.path)] = _page(
        base,
        page,
        body,
        language: settings.defaultLanguage,
        alternates: links,
        heading: headings[page.path],
        crumbs: crumbs,
      );
      if (settings.markdown && page.markdown != null) {
        files['web${_markdownAt(page.path)}'] = page.markdown!;
      }
    }
    for (final MapEntry(key: language, value: byPath) in translated.entries) {
      for (final page in byPath.values) {
        final address = _prefixed(language, page.path);
        final body = page.markdown == null
            ? null
            : _html(page, language: language);
        files[settings.fileOf(address)] = _page(
          base,
          page,
          body,
          language: language,
          address: address,
          alternates: page.fallback ? const {} : alternates(page.path),
          canonical: page.fallback ? settings.pageUrl(page.path) : null,
          heading: translatedHeadings[language]![page.path],
          crumbs: page.fallback
              ? const []
              : _crumbs(
                  page.path,
                  byPath,
                  (at) => _prefixed(language, at),
                ),
        );
        if (settings.markdown && page.markdown != null && !page.fallback) {
          files['web${_markdownAt(address)}'] = page.markdown!;
        }
      }
    }
    if (root != template) {
      files['web/index.html'] = root;
    }
    if (settings.sitemap) {
      files['web/sitemap.xml'] = _sitemap(pages.values, translated, alternates);
      files['web/robots.txt'] =
          'User-agent: *\nAllow: /\n\nSitemap: ${settings.url('/sitemap.xml')}\n';
    }
    if (settings.llms) {
      final markdownPages = [
        for (final page in pages.values)
          if (page.markdown != null && page.index) page,
      ]..sort((a, b) => a.path.compareTo(b.path));
      files['web/llms.txt'] = _llms(pages['/'], markdownPages);
      files['web/llms-full.txt'] = [
        for (final page in markdownPages)
          '<!-- ${settings.pageUrl(page.path)} -->\n${page.markdown!.trim()}\n',
      ].join('\n');
    }
    return files;
  }

  // The pages of one route of the metadata.
  List<_Page> _routePages(Map<String, Object?> route) {
    final path = route['path'] as String? ?? '';
    if (route['notFound'] == true || path.isEmpty) {
      return const [];
    }
    final guarded = route['preAuthorize'] != null;
    final index = route['index'] != false && !guarded;
    _Page described(String at) => _Page(at)
      ..title = _text(route['title'] as String?)
      ..description = _text(route['description'] as String?)
      ..titleSource = route['title'] as String?
      ..descriptionSource = route['description'] as String?
      ..image = route['image'] as String?
      ..index = index;
    final content = route['content'] as String?;
    final variables = RegExp(r'\{[^}]*\}').allMatches(path).toList();
    if (content != null && content.endsWith('/')) {
      final rest = RegExp(r'\{\*[A-Za-z_][A-Za-z0-9_]*\}$').firstMatch(path);
      if (rest == null || variables.length != 1) {
        throw SeoException(
          'The route $path shows the folder $content: its path must end with '
          '{*name}, its only variable.',
        );
      }
      final prefix = path.substring(0, rest.start);
      return [
        for (final page in _folder(content, prefix, settings.exclude))
          page
            ..title ??= _text(route['title'] as String?)
            ..description ??= _text(route['description'] as String?)
            ..titleSource ??= route['title'] as String?
            ..descriptionSource ??= route['description'] as String?
            ..image ??= route['image'] as String?
            ..index = index && page.index,
      ];
    }
    if (variables.isEmpty) {
      final page = described(path);
      if (content != null) {
        _withFile(page, _location(content));
      }
      return [page];
    }
    return [
      for (final at in (route['paths'] as List?) ?? const [])
        if (at is String) described(at),
    ];
  }

  // A page per Markdown file below [location] (resources:...), at [base]
  // and the file's path (`index.md` is the folder's address).
  List<_Page> _folder(String location, String base, List<String> exclude) {
    final folder = _location(location);
    final prefix = folder.isEmpty || folder.endsWith('/') ? folder : '$folder/';
    final files = [
      for (final file in texts.keys)
        if (file.startsWith(prefix) &&
            file.endsWith('.md') &&
            _languageOf(file) == null)
          file,
    ]..sort();
    if (files.isEmpty) {
      throw SeoException(
        'The Markdown folder $location (lib/resources/$prefix) has no .md '
        'file.',
      );
    }
    final pages = <_Page>[];
    for (final file in files) {
      final relative = file.substring(prefix.length);
      if (exclude.any((pattern) => _glob(pattern).hasMatch(relative))) {
        continue;
      }
      final name = relative.substring(0, relative.length - '.md'.length);
      final under = name == 'index'
          ? ''
          : name.endsWith('/index')
          ? '/${name.substring(0, name.length - '/index'.length)}'
          : '/$name';
      final root = base.endsWith('/') && base.length > 1
          ? base.substring(0, base.length - 1)
          : base;
      final path = '${root == '/' ? '' : root}$under';
      pages.add(_withFile(_Page(path.isEmpty ? '/' : path), file));
    }
    return pages;
  }

  _Page _withFile(_Page page, String file) {
    final text = texts[file];
    if (text == null) {
      throw SeoException('lib/resources/$file is missing.');
    }
    final (front, body) = _frontMatter(text, file);
    page
      ..file = file
      ..markdown = body
      ..title = _text(front['title']) ?? _firstHeading(body) ?? page.title
      ..description = _text(front['description']) ?? page.description
      ..image = front['image'] ?? page.image;
    if (front['index'] == 'false') {
      page.index = false;
    }
    return page;
  }

  // `#{key}` from the messages of [language] (`messages_ja.properties`),
  // else the default ones; else as written.
  String? _text(String? value, {String? language}) {
    if (value == null) {
      return null;
    }
    final key = RegExp(r'^#\{(.+)\}$').firstMatch(value)?.group(1);
    if (key == null) {
      return value;
    }
    for (final file in [
      if (language != null)
        'messages_${language.replaceAll('-', '_')}.properties',
      if (language != null && language.contains('-'))
        'messages_${language.split('-').first}.properties',
      'messages.properties',
    ]) {
      final messages = texts[file];
      if (messages == null) {
        continue;
      }
      for (final line in LineSplitter.split(messages)) {
        final match = RegExp(
          r'^\s*([^=:#!\s]+)\s*[=:]\s*(.*)$',
        ).firstMatch(line);
        if (match != null && match.group(1) == key) {
          return match.group(2)!.trim();
        }
      }
    }
    return key;
  }

  // The other language a Markdown file is the translation into
  // (`beans.ja.md`), or `null` for a default language's file.
  String? _languageOf(String file) {
    for (final language in settings.otherLanguages) {
      if (file.endsWith('.$language.md')) {
        return language;
      }
    }
    return null;
  }

  // The translation of [file] into [language]: `beans.md` → `beans.ja.md`.
  static String _translationOf(String file, String language) =>
      '${file.substring(0, file.length - '.md'.length)}.$language.md';

  // [path] in [language]: `/ja/docs`, `/ja` for the root.
  static String _prefixed(String language, String path) =>
      '/$language${path == '/' ? '' : path}';

  // [page] in [language]: its translated Markdown when there is one (its
  // front matter for the title and description), `#{key}` from that
  // language's messages; without a translation of its Markdown, a fallback
  // with the default text.
  _Page _translated(_Page page, String language) {
    final result = _Page(page.path)
      ..image = page.image
      ..index = page.index
      ..title = _text(page.titleSource, language: language) ?? page.title
      ..description =
          _text(page.descriptionSource, language: language) ?? page.description;
    final file = page.file;
    if (file == null) {
      return result;
    }
    final translation = _translationOf(file, language);
    final text = texts[translation];
    if (text == null) {
      // The default language's text, so its title and description too.
      return result
        ..title = page.title
        ..description = page.description
        ..fallback = true
        ..index = false
        ..file = file
        ..markdown = page.markdown;
    }
    final (front, body) = _frontMatter(text, translation);
    result
      ..file = translation
      ..markdown = body
      ..title =
          _text(front['title'], language: language) ??
          _firstHeading(body) ??
          result.title
      ..description =
          _text(front['description'], language: language) ?? result.description
      ..image = front['image'] ?? result.image;
    if (front['index'] == 'false') {
      result.index = false;
    }
    return result;
  }

  static (Map<String, String>, String) _frontMatter(String text, String file) {
    final match = RegExp(
      r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?',
    ).firstMatch(text);
    if (match == null) {
      return (const {}, text);
    }
    final Object? yaml;
    try {
      yaml = loadYaml(match.group(1)!);
    } on YamlException catch (e) {
      throw SeoException('The front matter of lib/resources/$file: $e');
    }
    return (
      {
        if (yaml is YamlMap)
          for (final MapEntry(:key, :value) in yaml.entries) '$key': '$value',
      },
      text.substring(match.end),
    );
  }

  static String? _firstHeading(String markdown) => RegExp(
    r'^#\s+(.+?)\s*#*\s*$',
    multiLine: true,
  ).firstMatch(markdown)?.group(1);

  static String _location(String location) {
    final path = location.startsWith('resources:')
        ? location.substring('resources:'.length)
        : location;
    return path.startsWith('/') ? path.substring(1) : path;
  }

  // `*` within a folder, `**` across folders; `**/` also matches no
  // folder at all (`**/contents.md` is a folder's `contents.md` at any
  // depth, its own included).
  static RegExp _glob(String pattern) {
    String part(String text) => [
      for (final piece in text.split('**'))
        piece.split('*').map(RegExp.escape).join('[^/]*'),
    ].join('.*');
    return RegExp('^${pattern.split('**/').map(part).join('(?:.*/)?')}\$');
  }

  // The page's Markdown as HTML, links to the site's files made addresses
  // (in [language] for a page of another language).
  String _html(_Page page, {String? language}) {
    final document = md.Document(extensionSet: _markdownSyntax);
    final nodes = document.parse(page.markdown!);
    final file = page.file!;
    void visit(List<md.Node> nodes) {
      for (final node in nodes) {
        if (node is md.Element) {
          final href = node.attributes['href'];
          if (node.tag == 'a' && href != null) {
            node.attributes['href'] = _address(href, file, language);
          }
          visit(node.children ?? const []);
        }
      }
    }

    visit(nodes);
    return md.HtmlRenderer().render(nodes);
  }

  // [href] of the Markdown file [file] as an address of the site.
  String _address(String href, String file, [String? language]) {
    final uri = Uri.tryParse(href);
    if (uri == null ||
        uri.hasScheme ||
        href.startsWith('#') ||
        href.startsWith('/')) {
      return href;
    }
    final target = uri.path;
    if (!target.endsWith('.md')) {
      return href;
    }
    var resolved = p.url.normalize(p.url.join(p.url.dirname(file), target));
    // A translation links to `beans.md` or `beans.ja.md`: the same page.
    if (language != null && resolved.endsWith('.$language.md')) {
      final stem = resolved.length - '.$language.md'.length;
      resolved = '${resolved.substring(0, stem)}.md';
    }
    final page = _byFile[resolved];
    if (page == null) {
      throw SeoException(
        'lib/resources/$file links to $target, which is no page of the site '
        '(lib/resources/$resolved).',
      );
    }
    final path = language == null ? page.path : _prefixed(language, page.path);
    final address = settings.basePath == '/'
        ? path
        : '${settings.basePath.substring(0, settings.basePath.length - 1)}'
              '$path';
    return uri.hasFragment ? '$address#${uri.fragment}' : address;
  }

  // The template for the pages below the root: the root page's blocks out,
  // the base address written (Flutter fills `$FLUTTER_BASE_HREF` in
  // web/index.html only).
  String _baseTemplate() => withoutRoot(
    template,
  ).replaceAll(r'$FLUTTER_BASE_HREF', settings.basePath);

  String _page(
    String html,
    _Page page,
    String? body, {
    bool root = false,
    String? language,
    String? address,
    Map<String, String> alternates = const {},
    String? canonical,
    String? heading,
    List<(String, String)> crumbs = const [],
  }) {
    final title = settings.title.replaceAll(
      '{title}',
      heading ?? page.title ?? '',
    );
    final description = page.description ?? settings.description;
    final image = page.image ?? settings.image;
    final at = address ?? page.path;
    final url = settings.pageUrl(at);
    final head = [
      _headStart,
      if (description != null)
        '<meta name="description" content="${_attr(description)}">',
      '<link rel="canonical" href="${_attr(canonical ?? url)}">',
      if (alternates.length > 1) ...[
        for (final MapEntry(key: tag, value: href) in alternates.entries)
          '<link rel="alternate" hreflang="$tag" href="${_attr(href)}">',
        if (alternates[settings.defaultLanguage] case final first?)
          _xDefault(first),
      ],
      if (!page.index) '<meta name="robots" content="noindex">',
      '<meta property="og:title" content="${_attr(page.title ?? title)}">',
      if (description != null)
        '<meta property="og:description" content="${_attr(description)}">',
      '<meta property="og:url" content="${_attr(url)}">',
      '<meta property="og:type" content="website">',
      if (settings.siteName case final name?)
        '<meta property="og:site_name" content="${_attr(name)}">',
      if (image != null)
        '<meta property="og:image" content="${_attr(_imageUrl(image))}">',
      '<meta name="twitter:card" content="${_card(image)}">',
      '<meta name="twitter:title" content="${_attr(page.title ?? title)}">',
      if (description != null)
        '<meta name="twitter:description" content="${_attr(description)}">',
      if (image != null)
        '<meta name="twitter:image" content="${_attr(_imageUrl(image))}">',
      if (settings.markdown && page.markdown != null && !page.fallback)
        _alternate(settings.url(_markdownAt(at))),
      if (crumbs.length > 1) _breadcrumbs(crumbs),
      _headEnd,
    ].join('\n  ');
    var result = html;
    if (language != null) {
      result = result.replaceFirstMapped(
        RegExp(r'<html\b([^>]*)>'),
        (match) {
          final attributes = match
              .group(1)!
              .replaceAll(RegExp(r'\s+lang="[^"]*"'), '');
          return '<html lang="$language"$attributes>';
        },
      );
    }
    // One description: the page's replaces the template's.
    if (description != null) {
      result = result.replaceAll(
        RegExp(r'[ \t]*<meta\s+name="description"[^>]*>\n?'),
        '',
      );
    }
    if (page.title != null) {
      result = result.replaceFirstMapped(
        RegExp(r'<title>[\s\S]*?</title>'),
        (_) => '<title>${_text2(title)}</title>',
      );
    }
    result = result.replaceFirst('</head>', '  $head\n</head>');
    if (body != null) {
      final main = [
        _bodyStart,
        // Under the loader, then under Flutter's view: never shown, never
        // removed (search engines read the page after its scripts ran).
        _mainTag,
        body.trimRight(),
        '</main>',
        _bodyEnd,
      ].join('\n');
      // Before Flutter's bootstrap script (the text first in the
      // document), else at the end of the body.
      final bootstrap = RegExp(
        r'[ \t]*<script[^>]*flutter_bootstrap\.js',
      ).firstMatch(result);
      result = bootstrap != null
          ? result.replaceRange(
              bootstrap.start,
              bootstrap.start,
              '$main\n',
            )
          : result.replaceFirst(
              RegExp(r'</body>(?![\s\S]*</body>)'),
              '$main\n</body>',
            );
    }
    return result;
  }

  // The `<title>` of each page of [byPath]: its title, and where another
  // page has the same one (`All properties` of several packages), the
  // titles of its nearest ancestor pages after it until it is unique
  // (`All properties · spring_boot_starter_data`). Search engines show one
  // of two pages with one title.
  // Only the pages search engines index count; the root page, whose title
  // is the site's, is no ancestor that tells two pages apart.
  static Map<String, String> _headings(Map<String, _Page> byPath) {
    List<String> ancestors(String path) => [
      for (final (at, page) in _ancestors(path, byPath))
        if (at != '/') ?page.title,
    ].reversed.toList();
    final result = {
      for (final page in byPath.values)
        if (page.index && !page.fallback) page.path: ?page.title,
    };
    for (var depth = 1; depth <= 8; depth++) {
      final byTitle = <String, List<String>>{};
      for (final MapEntry(key: path, value: title) in result.entries) {
        (byTitle[title] ??= []).add(path);
      }
      final repeated = [
        for (final paths in byTitle.values)
          if (paths.length > 1) ...paths,
      ];
      if (repeated.isEmpty) {
        break;
      }
      for (final path in repeated) {
        final above = ancestors(path);
        if (above.length >= depth) {
          result[path] = [
            byPath[path]!.title!,
            ...above.take(depth),
          ].join(' · ');
        }
      }
    }
    return result;
  }

  // The pages above [path] in [byPath], the root first: `/a/b/c` has `/`,
  // `/a`, `/a/b` where they are pages.
  static List<(String, _Page)> _ancestors(
    String path,
    Map<String, _Page> byPath,
  ) {
    final result = <(String, _Page)>[];
    var at = path;
    while (at != '/' && at.isNotEmpty) {
      final cut = at.lastIndexOf('/');
      at = cut <= 0 ? '/' : at.substring(0, cut);
      if (byPath[at] case final page?) {
        result.insert(0, (at, page));
      }
    }
    return result;
  }

  // The breadcrumbs of the page at [path]: each page above it with a
  // title, then the page, with their addresses ([address] puts a path in
  // the page's language).
  List<(String, String)> _crumbs(
    String path,
    Map<String, _Page> byPath,
    String Function(String path) address,
  ) {
    final page = byPath[path];
    if (page?.title == null || path == '/') {
      return const [];
    }
    return [
      for (final (at, above) in _ancestors(path, byPath))
        if (above.title case final title?)
          (title, settings.pageUrl(address(at))),
      (page!.title!, settings.pageUrl(address(path))),
    ];
  }

  // A `BreadcrumbList` (schema.org) of [crumbs], name and address each:
  // search results show the path above a page's title.
  static String _breadcrumbs(List<(String, String)> crumbs) {
    final json = jsonEncode({
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      'itemListElement': [
        for (final (i, (name, url)) in crumbs.indexed)
          {'@type': 'ListItem', 'position': i + 1, 'name': name, 'item': url},
      ],
    });
    return '<script type="application/ld+json">'
        '${json.replaceAll('</', r'<\/')}</script>';
  }

  // A large card where a preview has a picture (messengers, X, Slack...).
  static String _card(String? image) =>
      image == null ? 'summary' : 'summary_large_image';

  String _imageUrl(String image) {
    if (Uri.tryParse(image)?.hasScheme == true &&
        !image.startsWith('resources:')) {
      return image;
    }
    // A resource is a Flutter asset of the build.
    final path = _location(image);
    return settings.url('/assets/lib/resources/$path');
  }

  String _sitemap(
    Iterable<_Page> pages,
    Map<String, Map<String, _Page>> translated,
    Map<String, String> Function(String path) alternates,
  ) {
    String entry(String url, String path, String? file) {
      final links = alternates(path);
      final day = file == null ? null : modified[file];
      if (links.length < 2 && day == null) {
        return '  <url><loc>${_text2(url)}</loc></url>';
      }
      return [
        '  <url>',
        '    <loc>${_text2(url)}</loc>',
        if (day != null) '    <lastmod>$day</lastmod>',
        if (links.length > 1)
          for (final MapEntry(key: tag, value: href) in links.entries)
            '    <xhtml:link rel="alternate" hreflang="$tag" href="${_text2(href)}"/>',
        '  </url>',
      ].join('\n');
    }

    final sorted = pages.toList()..sort((a, b) => a.path.compareTo(b.path));
    final entries = [
      for (final page in sorted)
        if (page.index)
          entry(settings.pageUrl(page.path), page.path, page.file),
      for (final MapEntry(key: language, value: byPath) in translated.entries)
        for (final page in sorted)
          if (byPath[page.path] case final local?
              when local.index && !local.fallback)
            entry(
              settings.pageUrl(_prefixed(language, page.path)),
              page.path,
              local.file,
            ),
    ];
    final xhtml = translated.isEmpty
        ? ''
        : ' xmlns:xhtml="http://www.w3.org/1999/xhtml"';
    return '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"$xhtml>\n'
        '${entries.join('\n')}\n'
        '</urlset>\n';
  }

  String _llms(_Page? root, List<_Page> pages) {
    final lines = <String>[
      '# ${root?.title ?? settings.siteUrl.host}',
      '',
      if (root?.description ?? settings.description case final d?) ...[
        '> $d',
        '',
      ],
    ];
    String? section;
    for (final page in pages) {
      final segments = page.path.split('/')..removeWhere((s) => s.isEmpty);
      final group = segments.isEmpty ? '' : segments.first;
      if (group != section) {
        section = group;
        lines
          ..add('## ${_section(group)}')
          ..add('');
      }
      final description = page.description == null
          ? ''
          : ': ${page.description}';
      final markdown = settings.url(_markdownAt(page.path));
      lines.add('- [${page.title ?? page.path}]($markdown)$description');
    }
    return '${lines.join('\n')}\n';
  }

  static String _section(String group) =>
      group.isEmpty ? 'Home' : group[0].toUpperCase() + group.substring(1);

  static String _xDefault(String url) =>
      '<link rel="alternate" hreflang="x-default" href="${_attr(url)}">';

  static String _alternate(String url) =>
      '<link rel="alternate" type="text/markdown" href="${_attr(url)}">';

  static const _mainTag =
      '<main id="spring-content" style="position:absolute; top:0; left:0; '
      'width:100%; z-index:-1; overflow:hidden">';

  static String _attr(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

  static String _text2(String value) =>
      const HtmlEscape(HtmlEscapeMode.element).convert(value);
}

// GitHub's Markdown, HTML written in it kept as text: the app does not
// draw it, and the page's text must be the app's.
final _markdownSyntax = md.ExtensionSet(
  [const _HtmlAsText(), ...md.ExtensionSet.gitHubWeb.blockSyntaxes],
  [
    for (final syntax in md.ExtensionSet.gitHubWeb.inlineSyntaxes)
      if (syntax is! md.InlineHtmlSyntax) syntax,
  ],
);

// An HTML block of the Markdown as a paragraph of its text.
final class _HtmlAsText extends md.HtmlBlockSyntax {
  const _HtmlAsText();

  @override
  md.Node parse(md.BlockParser parser) {
    final html = super.parse(parser);
    return html is md.Text
        ? md.Element('p', [
            md.Text(
              const HtmlEscape(HtmlEscapeMode.element).convert(html.text),
            ),
          ])
        : html;
  }
}

/// The day each file below `lib/resources/` last changed, for the
/// sitemap's `lastmod`.
abstract interface class SeoDates {
  /// The days of [package]'s files, by their path below `lib/resources/`
  /// (`content/docs/beans.md`), as `2026-11-08`.
  Future<Map<String, String>> of(String package);
}

// The day of the last commit that changed each file (`git log`); none
// where the package is no Git checkout. A shallow clone has one commit,
// whose day every file gets: a CI checkout needs its history
// (`fetch-depth: 0`).
final class _GitDates implements SeoDates {
  const _GitDates();

  @override
  Future<Map<String, String>> of(String package) async {
    final directory = PackageDirectories.current
        .file(AssetId(package, 'lib/resources/x'))
        ?.parent
        .path;
    if (directory == null || !io.Directory(directory).existsSync()) {
      return const {};
    }
    try {
      final result = await io.Process.run('git', [
        '-C',
        directory,
        'log',
        '--format=@%cs',
        '--name-only',
        '--relative',
        '.',
      ]);
      if (result.exitCode != 0) {
        return const {};
      }
      final days = <String, String>{};
      String? day;
      for (final line in LineSplitter.split('${result.stdout}')) {
        if (line.startsWith('@')) {
          day = line.substring(1);
        } else if (line.isNotEmpty && day != null) {
          days.putIfAbsent(line, () => day!);
        }
      }
      return days;
    } on io.ProcessException {
      return const {};
    }
  }
}

/// Reads, writes and deletes the app's own files (below the package
/// directory).
abstract interface class SeoFiles {
  /// The text of [path] below [package]'s directory, or `null`.
  Future<String?> read(BuildStep buildStep, String package, String path);

  /// Writes [content] to [path], making its directory.
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  );

  /// Deletes [path] if it exists.
  Future<void> delete(BuildStep buildStep, String package, String path);
}

final class _Disk implements SeoFiles {
  const _Disk();

  io.File? _file(String package, String path) =>
      PackageDirectories.current.file(AssetId(package, path));

  @override
  Future<String?> read(BuildStep buildStep, String package, String path) async {
    final file = _file(package, path);
    return file != null && file.existsSync() ? await file.readAsString() : null;
  }

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async {
    final file = _file(package, path);
    if (file == null) {
      log.warning(
        'The directory of $package is not found; $path is not '
        'written.',
      );
      return;
    }
    if (file.existsSync() && await file.readAsString() == content) {
      return;
    }
    await io.Directory(file.parent.path).create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> delete(BuildStep buildStep, String package, String path) async {
    final file = _file(package, path);
    if (file != null && file.existsSync()) {
      await file.delete();
    }
  }
}

// The Markdown copy of the page at [address]: `<path>.md`, and
// `/index.md` for the root page, which has no path to add `.md` to.
String _markdownAt(String address) =>
    address == '/' ? '/index.md' : '$address.md';
