import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/src/markdown/markdown_sections.dart';
import 'package:spring_search_dart/src/search_document.dart';
import 'package:spring_search_dart/src/search_document_source.dart';

/// The Markdown files of a [location] (`resources:content/**/*.md`) as
/// documents: one per section, with the fields `title` (the page's),
/// `heading` and `body`, the link of the page ([link], `{path}` the file's
/// path from the location's directory without `.md`, its language and a
/// last `index`) and the section's anchor (`#why-beans`).
///
/// A file `name.ja.md` is the Japanese of `name.md`. A page without a
/// translation is also searched in the other languages, in its own.
///
/// The attributes: `page` (the page's link, for
/// `spring.search.collapse-by: page`), `section` (the heading) and `path`
/// (the file below `lib/resources/`).
///
/// `spring.search.markdown[n]` makes one per entry; an application makes
/// its own for another link or field.
final class MarkdownSearchSource implements SearchDocumentSource {
  /// The files of [location] but those of [exclude], read by [resources].
  MarkdownSearchSource(
    this.resources, {
    required this.location,
    this.exclude = const [],
    this.link = '/{path}',
    this.defaultLanguage = 'en',
    PathMatcher? matcher,
  }) : _matcher = matcher ?? AntPathMatcher();

  /// Finds and reads the files.
  final ResourcePatternResolver resources;

  /// The files, a pattern.
  final String location;

  /// Files left out, patterns relative to the location's directory.
  final List<String> exclude;

  /// The page's link; `{path}` is replaced.
  final String link;

  /// The language of a file without one in its name.
  final String defaultLanguage;

  final PathMatcher _matcher;

  static final _language = RegExp(
    r'^(.*)\.([a-z]{2,3}(?:[-_][A-Za-z]{2,4})?)$',
  );

  // The directory before the first wildcard, below lib/resources/.
  String get _root {
    final path = location.replaceFirst(RegExp(r'^resources\*?:/?'), '');
    final segments = path.split('/');
    final fixed = segments.takeWhile((s) => !_matcher.isPattern(s)).toList();
    return fixed.isEmpty ? '' : '${fixed.join('/')}/';
  }

  @override
  Stream<SearchDocument> documents() async* {
    final root = _root;
    final pages = <String, Map<String, Resource>>{};
    for (final resource in resources.getResources(location)) {
      final path = resource is ContextResource
          ? resource.pathWithinContext
          : resource.filename ?? '';
      final relative = path.startsWith(root)
          ? path.substring(root.length)
          : path;
      if (!relative.endsWith('.md') ||
          exclude.any((pattern) => _matcher.match(pattern, relative))) {
        continue;
      }
      final stem = relative.substring(0, relative.length - 3);
      final match = _language.firstMatch(stem);
      final (base, language) = match == null
          ? (stem, defaultLanguage)
          : (match[1]!, match[2]!);
      pages.putIfAbsent(base, () => {})[language] = resource;
    }
    final languages = {
      defaultLanguage,
      for (final page in pages.values) ...page.keys,
    };
    for (final MapEntry(key: base, value: files) in pages.entries) {
      final page = _link(link.replaceAll('{path}', _path(base)));
      for (final language in languages) {
        final resource = files[language] ?? files[defaultLanguage];
        if (resource == null) {
          continue;
        }
        final sections = MarkdownSections.parse(
          await resource.readAsString(),
        );
        for (final section in sections.sections) {
          final address = section.anchor == null
              ? page
              : '$page#${section.anchor}';
          yield SearchDocument(
            id: address,
            language: language,
            link: address,
            fields: {
              'title': sections.title,
              'heading': section.heading,
              'body': section.body,
            },
            attributes: {
              'page': page,
              'section': section.heading,
              if (resource case final ContextResource file)
                'path': file.pathWithinContext,
            },
          );
        }
      }
    }
  }

  static String _link(String link) {
    final clean = link.replaceAll(RegExp('/{2,}'), '/');
    return clean.length > 1 && clean.endsWith('/')
        ? clean.substring(0, clean.length - 1)
        : clean;
  }

  static String _path(String base) {
    if (base == 'index') {
      return '';
    }
    return base.endsWith('/index')
        ? base.substring(0, base.length - '/index'.length)
        : base;
  }
}
