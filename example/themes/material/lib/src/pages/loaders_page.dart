import 'dart:async';

import 'package:flutter/material.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';
import 'package:theme_showcase_material/src/widgets/page_frame.dart';
import 'package:theme_showcase_material/src/widgets/section.dart';
import 'package:theme_showcase_material/src/widgets/yaml_box.dart';

/// Loaders: a spinner for a refresh, a bar with the progress of a fake
/// upload, a skeleton of a list, and the splash of the app.
class LoadersPage extends StatelessWidget {
  const LoadersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: context.messages.nav.loaders,
      intro:
          'Loaders are written in the theme and shown by ThemeLoader and '
          'ThemeSkeleton. The app started with its splash, a logo with a '
          'bar that followed the start; on the web the page showed it '
          'before Flutter ran.',
      children: const [
        Section(
          title: 'A spinner: refresh',
          note:
              'No progress is known, so the spinner turns until the work is '
              'done (a fake refresh of 1.5 seconds).',
          child: _Refresh(),
        ),
        Section(
          title: 'A bar: a fake upload',
          note:
              'The bar fills with the progress you give it, from 0 to 1; '
              'without progress it runs back and forth.',
          child: _Upload(),
        ),
        Section(
          title: 'A skeleton',
          note:
              'The shape of the content shows, with a highlight crossing it, '
              'until the list is there.',
          child: _Books(),
        ),
        Section(
          title: 'The loaders, written',
          child: YamlBox(
            label: 'application.yml: loaders',
            r'''
spinner: { kind: spinner, size: 32, stroke: 3, track: { color: $colors.primary, alpha: 20% } }
bar: { kind: bar, color: $colors.primary, track: { color: $colors.primary, alpha: 20% }, height: 4, width: 240 }
card:
  kind: skeleton
  base: $colors.surface-container-high
  highlight: $colors.surface-container-highest
  radius: $shape.medium
  shimmer: { duration: 1.2s, angle: 20 }''',
          ),
        ),
        Section(
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
  loader: bar
  min-duration: 1.2s
  exit: { transition: 400ms ease-out }''',
          ),
        ),
        Section(
          title: 'In Dart',
          child: SelectableText(
            'ThemeLoader(context.theme.loaders.spinner)\n'
            'ThemeLoader(context.theme.loaders.bar, progress: sent)\n'
            'ThemeSkeleton(context.theme.loaders.card, loading: !loaded, '
            'child: list)',
          ),
        ),
      ],
    );
  }
}

class _Refresh extends StatefulWidget {
  const _Refresh();

  @override
  State<_Refresh> createState() => _RefreshState();
}

class _RefreshState extends State<_Refresh> {
  Timer? _timer;
  bool _busy = false;

  void _refresh() {
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
    final space = context.theme.spacing;
    return Row(
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
        SizedBox(width: space.l),
        if (_busy)
          ThemeLoader(context.theme.loaders.spinner)
        else
          Text(
            'Up to date',
            style: Theme.of(context).textTheme.bodyMedium,
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
    final space = context.theme.spacing;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Waiting for the server', style: text.labelMedium),
        SizedBox(height: space.s),
        ThemeLoader(context.theme.loaders.bar),
        SizedBox(height: space.m),
        Text(
          'Upload: ${(_sent * 100).round()} %',
          key: const Key('upload-text'),
          style: text.labelMedium,
        ),
        SizedBox(height: space.s),
        ThemeLoader(context.theme.loaders.bar, progress: _sent),
        SizedBox(height: space.m),
        OutlinedButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.upload),
          label: const Text('Fake upload'),
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
    final space = context.theme.spacing;
    Widget tile(String? title) => ListTile(
      leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
      title: title == null
          ? Container(height: 14, width: 140, color: Colors.white)
          : Text(title),
      subtitle: title == null
          ? Padding(
              padding: EdgeInsets.only(top: space.xs),
              child: Container(height: 10, width: 200, color: Colors.white),
            )
          : const Text('A line about the book'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: ThemeSkeleton(
            context.theme.loaders.card,
            loading: !_loaded,
            placeholder: Column(
              children: [for (var i = 0; i < 3; i++) tile(null)],
            ),
            child: Column(
              key: const Key('books-loaded'),
              children: [for (final title in _titles) tile(title)],
            ),
          ),
        ),
        SizedBox(height: space.s),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.replay),
          label: const Text('Load again'),
        ),
      ],
    );
  }
}
