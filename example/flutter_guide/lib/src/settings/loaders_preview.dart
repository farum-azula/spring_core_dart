import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:neon_books_app/spring_gen/main.spring.dart';
import 'package:neon_books_app/src/catalog/book_tile.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// A few lines of the YAML that make the loaders, as a block of Markdown
/// colored by the theme's `styles.code`; a test checks that every line is
/// in `lib/resources/`, so the box cannot drift from the files.
class YamlBox extends StatelessWidget {
  const YamlBox(this.text, {super.key, this.label});

  final String text;

  /// The file the lines come from, shown above them.
  final String? label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (label != null)
        Padding(
          padding: EdgeInsets.only(bottom: context.theme.spacing.s / 2),
          child: Text(
            label!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      MarkdownView.code(text, language: 'yaml'),
    ],
  );
}

/// The loaders of the theme at work: a skeleton of the catalog, a bar with
/// the progress of a fake download (the kind of wait the catalog and the
/// basket have), and the YAML that makes them and the splash.
class LoadersPreview extends StatefulWidget {
  const LoadersPreview({super.key});

  @override
  State<LoadersPreview> createState() => _LoadersPreviewState();
}

class _LoadersPreviewState extends State<LoadersPreview> {
  Timer? _timer;
  double _done = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  // A fake download of three seconds: the skeleton shows and the bar fills.
  void _run() {
    _timer?.cancel();
    setState(() {
      _done = 0;
      _loading = true;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _done = (_done + 50 / 3000).clamp(0.0, 1.0);
        _loading = _done < 1;
      });
      if (_done >= 1) {
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
    final space = theme.spacing.m;
    return Padding(
      padding: EdgeInsets.all(space),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The same skeleton the catalog shows while the server answers.
          SizedBox(
            height: 160,
            child: ThemeSkeleton(
              theme.loaders.card,
              loading: _loading,
              placeholder: const BookTilePlaceholder(count: 2),
              child: const Card(
                child: ListTile(
                  leading: Icon(Icons.menu_book_outlined),
                  title: Text('Spring in Action'),
                  subtitle: Text('Loaded'),
                ),
              ),
            ),
          ),
          SizedBox(height: space),
          // Without progress the bar runs back and forth: only while the
          // wait lasts.
          if (_loading) ...[
            const Text('Waiting for the server'),
            SizedBox(height: theme.spacing.s),
            ThemeLoader(theme.loaders.bar),
            SizedBox(height: space),
          ],
          Text('Download: ${(_done * 100).round()} %'),
          SizedBox(height: theme.spacing.s),
          ThemeLoader(theme.loaders.bar, progress: _done),
          SizedBox(height: space),
          OutlinedButton(
            onPressed: _run,
            child: const Text('Run again'),
          ),
          SizedBox(height: space),
          const YamlBox(
            label: 'application.yml: loaders',
            r'''
card:
  kind: skeleton
  base: $colors.surface-container-high
  highlight: $colors.surface-container-highest
  radius: $shape.medium
  shimmer: { duration: 1.2s, angle: 20 }
bar: { kind: bar, color: $colors.primary, track: { color: $colors.primary, alpha: 20% }, height: 4, width: 220 }''',
          ),
          SizedBox(height: space),
          const YamlBox(
            label: 'application.yml: splash',
            r'''
splash:
  background: { color: $colors.surface }
  logo: { source: assets/images/leaf.png, size: 96 }
  title: NEON Books
  loader: bar
  min-duration: 1s
  exit: { transition: 400ms ease-out }''',
          ),
        ],
      ),
    );
  }
}
