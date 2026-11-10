import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/debug_isolates.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';

/// The task manager in the debug panel: its small table shown on screen
/// or not, and every row in full ([IsolatesView]), read while the tab is
/// open.
final class DebugIsolatesSection implements DebugPanelSection, Ordered {
  /// The section of [isolates].
  const DebugIsolatesSection(this.isolates);

  /// The task manager.
  final DebugIsolates isolates;

  @override
  String get title => 'Isolates';

  @override
  int get order => 57;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: isolates,
          builder: (context, _) => Row(
            children: [
              Text(
                'Show on screen ',
                style: style.text.copyWith(color: style.muted),
              ),
              const SizedBox(width: 6),
              DebugChip(
                isolates.shown ? 'On' : 'Off',
                selected: isolates.shown,
                onTap: () => isolates.shown = !isolates.shown,
              ),
            ],
          ),
        ),
        Expanded(child: IsolatesView(rows: isolates.rows)),
      ],
    );
  }
}
