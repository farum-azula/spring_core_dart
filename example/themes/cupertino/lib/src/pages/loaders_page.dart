import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';
import 'package:theme_showcase_cupertino/src/widgets/page_frame.dart';
import 'package:theme_showcase_cupertino/src/widgets/section.dart';
import 'package:theme_showcase_cupertino/src/widgets/yaml_box.dart';

/// Loaders in the iOS look: a pulse and dots while something is fetched, a
/// thin bar with the progress of a fake upload, a skeleton of a list, and
/// the splash of the app.
@ScreenRoute('/loaders', title: '#{nav.loaders}', branch: '/more')
class LoadersPage extends StatelessWidget {
  const LoadersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: context.messages.nav.loaders,
      intro:
          'Loaders are written in the theme and shown by ThemeLoader and '
          'ThemeSkeleton. The app started with its splash, a logo with '
          'dots; on the web the page showed it before Flutter ran.',
      children: [
        const Section(
          title: 'A pulse and dots: fetching',
          note:
              'No progress is known, so they go on until the work is done '
              '(a fake fetch of 1.5 seconds).',
          child: _Fetch(),
        ),
        const Section(
          title: 'A bar: a fake upload',
          note:
              'The bar fills with the progress you give it, from 0 to 1; '
              'without progress it runs back and forth.',
          child: _Upload(),
        ),
        const Section(
          title: 'A skeleton',
          note:
              'The shape of the content shows, with a quiet highlight '
              'crossing it, until the list is there.',
          child: _Books(),
        ),
        const Section(
          title: 'The loaders, written',
          child: YamlBox(
            label: 'application.yml: loaders',
            r'''
pulse: { kind: pulse, color: $colors.primary, size: 28, animation: { duration: 1.2s, curve: ease-in-out, repeat: reverse } }
dots: { kind: dots, color: $colors.primary, size: 8, count: 3 }
bar: { kind: bar, color: $colors.primary, track: { color: $colors.primary, alpha: 20% }, height: 4, width: 220, radius: 2 }
card:
  kind: skeleton
  base: { color: $colors.on-surface, alpha: 8% }
  highlight: { color: $colors.on-surface, alpha: 16% }
  radius: 10
  shimmer: { duration: 1.4s, angle: 20 }''',
          ),
        ),
        const Section(
          title: 'The splash, written',
          note:
              'min-duration keeps it at least that long; exit is the fade '
              'out when the app is ready.',
          child: YamlBox(
            label: 'application.yml: splash',
            r'''
splash:
  background: { color: $colors.surface }
  logo: { source: assets/images/badge.png, size: 96 }
  title: Theme Showcase
  loader: dots
  min-duration: 1.2s
  exit: { transition: 400ms ease-out }''',
          ),
        ),
        Section(
          title: 'In Dart',
          child: MarkdownView.code(
            'ThemeLoader(context.theme.loaders.pulse)\n'
            'ThemeLoader(context.theme.loaders.bar, progress: sent)\n'
            'ThemeSkeleton(context.theme.loaders.card, loading: !loaded, '
            'child: list)',
            language: 'dart',
          ),
        ),
      ],
    );
  }
}

class _Fetch extends StatefulWidget {
  const _Fetch();

  @override
  State<_Fetch> createState() => _FetchState();
}

class _FetchState extends State<_Fetch> {
  Timer? _timer;
  bool _busy = false;

  void _fetch() {
    _timer?.cancel();
    setState(() => _busy = true);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return Row(
      children: [
        CupertinoButton.tinted(
          onPressed: _busy ? null : _fetch,
          child: const Text('Fetch'),
        ),
        SizedBox(width: space.l),
        if (_busy) ...[
          ThemeLoader(theme.loaders.pulse),
          SizedBox(width: space.l),
          ThemeLoader(theme.loaders.dots),
        ] else
          Text(
            'Up to date',
            style: CupertinoTheme.of(context).textTheme.textStyle,
          ),
      ],
    );
  }
}

class _Upload extends StatefulWidget {
  const _Upload();

  @override
  State<_Upload> createState() => _UploadState();
}

class _UploadState extends State<_Upload> {
  Timer? _timer;
  double _sent = 0;

  void _run() {
    _timer?.cancel();
    setState(() => _sent = 0);
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _sent = (_sent + 50 / 3000).clamp(0.0, 1.0));
      if (_sent >= 1) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Waiting for the server', style: theme.typography.labelLarge),
        SizedBox(height: space.s),
        ThemeLoader(theme.loaders.bar),
        SizedBox(height: space.m),
        Text(
          'Upload: ${(_sent * 100).round()} %',
          style: theme.typography.labelLarge,
        ),
        SizedBox(height: space.s),
        ThemeLoader(theme.loaders.bar, progress: _sent),
        SizedBox(height: space.m),
        CupertinoButton.tinted(
          onPressed: _run,
          child: const Text('Fake upload'),
        ),
      ],
    );
  }
}

class _Books extends StatefulWidget {
  const _Books();

  @override
  State<_Books> createState() => _BooksState();
}

class _BooksState extends State<_Books> {
  static const _titles = ['First volume', 'Second volume', 'Third volume'];
  Timer? _timer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _timer?.cancel();
    setState(() => _loaded = false);
    _timer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _loaded = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final space = theme.spacing;
    // The placeholder is painted in the skeleton's color: any opaque fill.
    const fill = Color(0xFFFFFFFF);
    Widget row(String? title) => Padding(
      padding: EdgeInsets.symmetric(vertical: space.s),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: title == null ? fill : theme.colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          SizedBox(width: space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title == null)
                  Container(height: 14, width: 140, color: fill)
                else
                  Text(title, style: theme.typography.bodyLarge),
                SizedBox(height: space.xs),
                if (title == null)
                  Container(height: 10, width: 200, color: fill)
                else
                  Text(
                    'A line about the book',
                    style: theme.typography.code.copyWith(
                      color: theme.colors.onSurface,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThemeSkeleton(
          theme.loaders.card,
          loading: !_loaded,
          placeholder: Column(
            children: [for (var i = 0; i < 3; i++) row(null)],
          ),
          child: Column(
            key: const Key('books-loaded'),
            children: [for (final title in _titles) row(title)],
          ),
        ),
        SizedBox(height: space.s),
        CupertinoButton.tinted(
          onPressed: _load,
          child: const Text('Load again'),
        ),
      ],
    );
  }
}
