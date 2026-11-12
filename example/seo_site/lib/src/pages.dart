import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

/// The frame of every page: the site's name and its links.
class SiteFrame extends StatelessWidget {
  const SiteFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = context.route;
    Widget link(String label, String path, String pattern) => TextButton(
      onPressed: route.matches(pattern) ? null : () => route.go(path),
      child: Text(label),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumen'),
        actions: [
          link('Home', '/', '/'),
          link('Docs', '/docs', '/docs/**'),
          link('Blog', '/blog/hello', '/blog/**'),
          link('Books', '/books/1', '/books/**'),
          link('About', '/about', '/about'),
          // The same page in the other language: /ja/... or back.
          TextButton(
            onPressed: () =>
                route.switchLanguage(route.language == 'ja' ? 'en' : 'ja'),
            child: Text(route.language == 'ja' ? 'EN' : '日本語'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A Markdown view whose links to a path (`/about`) open that page; links
/// to another Markdown file open its page by themselves.
class SiteContent extends StatelessWidget {
  const SiteContent({super.key});

  @override
  Widget build(BuildContext context) => RouteContentView(
    onLink: (href) {
      if (href.startsWith('/')) {
        context.route.go(href);
      }
    },
  );
}

/// `/`: its page's title comes from `pages[0]` of application-web.yml,
/// which says it longer than the screen.
@ScreenRoute('/', title: 'Home')
@RouteInfo(description: 'Lumen, a small library, and its documentation.')
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => SiteFrame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Lumen', style: Theme.of(context).textTheme.displaySmall),
        const SizedBox(height: 16),
        const Text(
          'A small library, and a site whose every page a search engine '
          'can read.',
        ),
      ],
    ),
  );
}

/// `/docs/...`: a page per Markdown file of `content/docs/`
/// (`index.md` is `/docs`, `guides/routing.md` is `/docs/guides/routing`).
@ScreenRoute('/docs/{*path}', title: 'Docs', content: 'resources:content/docs/')
class DocsPage extends StatelessWidget {
  const DocsPage({super.key});

  @override
  Widget build(BuildContext context) => const SiteFrame(child: SiteContent());
}

/// `/blog/...`: the posts, with their own preview pictures (front matter).
@ScreenRoute('/blog/{*path}', title: 'Blog', content: 'resources:content/blog/')
class BlogPage extends StatelessWidget {
  const BlogPage({super.key});

  @override
  Widget build(BuildContext context) => const SiteFrame(child: SiteContent());
}

/// `/legal/...`: reads its Markdown itself, so the build cannot know its
/// pages from the route; `content[0]` of application-web.yml lists them.
@ScreenRoute('/legal/{*path}', title: 'Legal')
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) => SiteFrame(
    child: MarkdownView.resource(
      'resources:content/legal/${context.route.pathVariable('path')}.md',
      key: ValueKey(context.route.uri.path),
    ),
  );
}

/// `/books/{id}`: a path variable, so the build knows its pages only from
/// `@RouteInfo(paths:)`.
@ScreenRoute('/books/{id}', title: 'Book')
@RouteInfo(
  description: 'A book about Lumen.',
  image: 'resources:images/book.png',
  paths: ['/books/1', '/books/2'],
)
class BookPage extends StatelessWidget {
  const BookPage({super.key});

  @override
  Widget build(BuildContext context) => SiteFrame(
    child: Text('Book ${context.route.pathVariable('id')}'),
  );
}

/// `/about`: the title and the description from messages.properties.
@ScreenRoute('/about', title: '#{about.title}')
@RouteInfo(description: '#{about.description}')
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) =>
      SiteFrame(child: Text(context.message('about.description')));
}

/// `/account`: a page for signed-in readers; `noindex`, not in the
/// sitemap.
@ScreenRoute('/account', title: 'Account')
@RouteInfo(index: false)
class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const SiteFrame(child: Text('Your account'));
}

/// Any other address.
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) =>
      SiteFrame(child: Text('No page at ${context.route.uri.path}'));
}
