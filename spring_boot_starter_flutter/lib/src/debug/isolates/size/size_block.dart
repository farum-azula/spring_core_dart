import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/big_number.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/size/page_resources.dart';

/// The size block of the debug panel's Isolates tab. On the web, what the
/// page downloaded, from the browser's Resource Timing: the total bytes
/// transferred and decoded, the totals by kind ([pageResourceKinds]) and
/// the [top] heaviest downloads, a cross-origin one whose sizes the
/// browser hides marked. Read when the block shows and on Refresh,
/// nothing in between. Elsewhere, where to find a build's size.
class DebugSizeBlock extends StatefulWidget {
  /// The block of [resources], the browser's by default.
  const DebugSizeBlock({this.resources, this.top = 10, super.key});

  /// Where the downloads are read; `null`: the browser's
  /// ([PageResources.platform]), none outside a browser.
  final PageResources? resources;

  /// How many of the heaviest downloads are listed.
  final int top;

  @override
  State<DebugSizeBlock> createState() => _DebugSizeBlockState();
}

class _DebugSizeBlockState extends State<DebugSizeBlock> {
  PageResources? _source;
  List<PageResource> _resources = const [];

  @override
  void initState() {
    super.initState();
    _source = widget.resources ?? PageResources.platform();
    _read();
  }

  void _read() => _resources = _source?.read() ?? const [];

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final source = _source;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Size', style: style.title)),
            if (source != null)
              DebugChip('Refresh', onTap: () => setState(_read)),
          ],
        ),
        const SizedBox(height: 8),
        if (source == null)
          Text(
            'Build size: on the web only; use '
            '`flutter build <platform> --analyze-size`.',
            style: style.text.copyWith(color: style.muted),
          )
        else
          _Downloads(_resources, top: widget.top, full: source.full),
      ],
    );
  }
}

class _Downloads extends StatelessWidget {
  const _Downloads(this.resources, {required this.top, required this.full});

  final List<PageResource> resources;
  final int top;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = style.text.copyWith(color: style.muted, fontSize: 11);
    final heaviest = [...resources]
      ..sort((a, b) => b.weight.compareTo(a.weight));
    final hidden = resources.where((resource) => resource.hidden).length;
    final kinds = <String, List<PageResource>>{
      for (final kind in pageResourceKinds) kind.name: [],
      'other': [],
    };
    for (final resource in resources) {
      kinds[pageResourceKindOf(resource)]!.add(resource);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _Figure(
              'transferred',
              DebugBigNumber.bytes(_sum(resources, (r) => r.transferSize)),
            ),
            _Figure(
              'decoded',
              DebugBigNumber.bytes(_sum(resources, (r) => r.decodedBodySize)),
            ),
            _Figure('downloads', DebugBigNumber('${resources.length}')),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'What the page downloaded, from the browser\'s Resource Timing: '
          'transferred over the network (0 from the cache), and the bodies '
          'decoded (unzipped).',
          style: muted,
        ),
        if (full)
          Text(
            'The browser\'s list of downloads was full: the ones past it '
            'are missing.',
            style: style.text.copyWith(color: style.warning, fontSize: 11),
          ),
        if (hidden > 0)
          Text(
            '$hidden from other origins without Timing-Allow-Origin report '
            '0 (marked hidden).',
            style: style.text.copyWith(color: style.warning, fontSize: 11),
          ),
        const SizedBox(height: 10),
        _Line(
          name: 'kind',
          cells: const ['count', 'transferred', 'decoded'],
          style: style.code.copyWith(color: style.muted),
        ),
        for (final MapEntry(key: kind, value: of) in kinds.entries)
          _Line(
            name: kind,
            cells: [
              '${of.length}',
              formatIsolateMemory(_sum(of, (r) => r.transferSize)),
              formatIsolateMemory(_sum(of, (r) => r.decodedBodySize)),
            ],
            style: style.code,
          ),
        const SizedBox(height: 10),
        _Line(
          name: 'heaviest',
          cells: const ['kind', 'transferred', 'decoded'],
          style: style.code.copyWith(color: style.muted),
        ),
        for (final resource in heaviest.take(top))
          _Line(
            name: _shortName(resource),
            fullName: PageResource.masked(resource.name),
            cells: [
              pageResourceKindOf(resource),
              resource.hidden
                  ? 'hidden'
                  : resource.cached
                  ? 'cache'
                  : formatIsolateMemory(resource.transferSize),
              resource.hidden
                  ? 'hidden'
                  : formatIsolateMemory(resource.decodedBodySize),
            ],
            style: style.code,
          ),
      ],
    );
  }

  static int _sum(
    Iterable<PageResource> resources,
    int Function(PageResource) size,
  ) => resources.fold(0, (sum, resource) => sum + size(resource));

  static String _shortName(PageResource resource) {
    final uri = Uri.tryParse(resource.name);
    final segments = uri?.pathSegments.where((s) => s.isNotEmpty);
    return segments == null || segments.isEmpty
        ? (uri?.host ?? resource.name)
        : segments.last;
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.number);

  final String label;
  final DebugBigNumber number;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: style.text.copyWith(color: style.muted)),
        number,
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.name,
    required this.cells,
    required this.style,
    this.fullName,
  });

  static const _widths = [56.0, 84.0, 84.0];

  final String name;
  final List<String> cells;
  final TextStyle style;
  final String? fullName;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 3),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            label: fullName,
            child: Text(
              name,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        for (final (i, cell) in cells.indexed)
          SizedBox(
            width: _widths[i],
            child: Text(
              cell,
              style: style,
              maxLines: 1,
              textAlign: TextAlign.end,
            ),
          ),
      ],
    ),
  );
}
