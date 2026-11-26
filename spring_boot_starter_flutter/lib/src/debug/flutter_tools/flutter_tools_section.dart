import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/debug_flutter_tools.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/devtools_link.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/flutter_tool_switches.dart';
import 'package:spring_boot_starter_flutter/src/debug/flutter_tools/inspector_selection_view.dart';

/// The debug panel's Flutter tab: Flutter's own debug tools switched in
/// the running app ([DebugFlutterTools]), the inspector's selection, and
/// the address DevTools connects to ([DevToolsLink]). A tool this build
/// cannot run shows why instead of its switch.
final class DebugFlutterToolsSection
    implements GroupedDebugPanelSection, Ordered {
  /// The tab of [tools]; [lookup] finds the VM service's address.
  const DebugFlutterToolsSection(this.tools, {this.lookup = vmServiceAddress});

  /// The tools.
  final DebugFlutterTools tools;

  /// Finds the VM service's address for DevTools.
  final VmServiceLookup lookup;

  @override
  String get title => 'Flutter';

  @override
  int get order => 60;

  @override
  String get group => 'Tools';

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = style.text.copyWith(color: style.muted);
    return SingleChildScrollView(
      child: ListenableBuilder(
        listenable: tools.changes,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final tool in tools.switches)
              _SwitchRow(tool: tool, tools: tools),
            const SizedBox(height: 8),
            Text('Slow animations', style: style.title),
            const SizedBox(height: 6),
            Wrap(
              children: [
                for (final factor in DebugFlutterTools.dilations)
                  DebugChip(
                    '${factor.toStringAsFixed(0)}x',
                    selected: tools.dilation == factor,
                    onTap: () => tools.dilation = factor,
                  ),
              ],
            ),
            Text(
              'timeDilation: every animation this many times slower.',
              style: muted,
            ),
            const SizedBox(height: 16),
            Text('Inspector selection', style: style.title),
            const SizedBox(height: 6),
            if (tools.unavailable(const WidgetInspectorSwitch())
                case final reason?)
              Text(reason, style: muted)
            else
              InspectorSelectionView(),
            const SizedBox(height: 16),
            Text('DevTools', style: style.title),
            const SizedBox(height: 6),
            DevToolsLink(mode: tools.mode, lookup: lookup),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.tool, required this.tools});

  final DebugFlutterSwitch tool;
  final DebugFlutterTools tools;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final muted = style.text.copyWith(color: style.muted);
    final reason = tools.unavailable(tool);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: reason == null
                ? DebugChip(
                    tool.title,
                    selected: tool.on,
                    onTap: () => tools.flip(tool, !tool.on),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      tool.title,
                      style: muted.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(reason ?? tool.hint, style: muted),
            ),
          ),
        ],
      ),
    );
  }
}
