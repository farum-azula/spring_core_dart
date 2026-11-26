import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/debug_isolates.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/memory/memory_block.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/size/size_block.dart';

/// The task manager in the debug panel: the memory on top
/// ([DebugMemoryBlock]), what the page downloaded on the web
/// ([DebugSizeBlock]), then every row in full ([IsolatesView]), read
/// while the tab is open.
final class DebugIsolatesSection implements GroupedDebugPanelSection, Ordered {
  /// The section of [isolates].
  const DebugIsolatesSection(this.isolates);

  /// The task manager.
  final DebugIsolates isolates;

  @override
  String get title => 'Isolates';

  @override
  int get order => 57;

  @override
  String get group => 'Performance';

  @override
  Widget build(BuildContext context) => IsolatesView(
    rows: isolates.rows,
    header: [
      DebugMemoryBlock(memory: isolates.memory),
      const SizedBox(height: 16),
      const DebugSizeBlock(),
      const SizedBox(height: 16),
    ],
  );
}
