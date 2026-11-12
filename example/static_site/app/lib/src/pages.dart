import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:static_site_app/src/server_info.dart';

/// The frame of every page: the site's name and its three links.
class SiteFrame extends StatelessWidget {
  const SiteFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = context.route;
    Widget link(String label, String path) => TextButton(
      onPressed: route.matches(path) ? null : () => route.go(path),
      child: Text(label),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Static site'),
        actions: [
          link('Home', '/'),
          link('Guide', '/guide'),
          link('Server', '/server'),
          const SizedBox(width: 8),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: child,
        ),
      ),
    );
  }
}

/// The Markdown of the page's route: a link to another Markdown file
/// opens its page, a link to a path (`/server`) opens that page.
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

/// `/`: the Markdown of `lib/resources/content/home.md`.
@ScreenRoute('/', title: 'Home', content: 'resources:content/home.md')
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => const SiteFrame(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: SiteContent(),
    ),
  );
}

/// `/guide`: how the site is built and served, in Markdown.
@ScreenRoute('/guide', title: 'Guide', content: 'resources:content/guide.md')
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) => const SiteFrame(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: SiteContent(),
    ),
  );
}

/// `/server`: the answer of the server's `/api/info`, the same origin as
/// the page.
@ScreenRoute('/server', title: 'Server')
class ServerPage extends SpringStatefulWidget<(ServerInfoClient,)> {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends SpringState<ServerPage, (ServerInfoClient,)> {
  late Future<ServerInfo> _info = beans.$1.fetch();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SiteFrame(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FutureBuilder(
          future: _info,
          builder: (context, info) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GET /api/info', style: text.headlineSmall),
              const SizedBox(height: 16),
              if (info.hasData) ...[
                Text('Served by ${info.requireData.name}'),
                Text('Server time ${info.requireData.time.toIso8601String()}'),
              ] else if (info.hasError)
                Text(
                  'No answer: ${info.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                const LinearProgressIndicator(),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _info = beans.$1.fetch()),
                child: const Text('Ask again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Any other address: the server sent `index.html` (its SPA fallback),
/// the app has no such page.
@ScreenRoute.notFound()
class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => SiteFrame(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('No page at ${context.route.uri.path}'),
    ),
  );
}
