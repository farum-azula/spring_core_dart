import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_filter.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/debug_network_journal.dart';
import 'package:spring_boot_starter_flutter/src/debug/network/network_view.dart';

/// The debug panel's Network tab (`debugNetworkSection`), in its own group:
/// the requests and WebSocket connections of the journal, newest first,
/// filtered by address, method and status, each opened for its headers,
/// body, timings and error ([NetworkView]). The filter is kept here, so
/// the tab opens again as it was left.
final class DebugNetworkSection implements GroupedDebugPanelSection, Ordered {
  /// The tab of [journal].
  DebugNetworkSection(this.journal);

  /// The traffic recorded.
  final DebugNetworkJournal journal;

  /// Which entries show.
  final DebugNetworkFilter filter = DebugNetworkFilter();

  @override
  String get title => 'Network';

  @override
  int get order => 8;

  @override
  String get group => 'Network';

  @override
  Widget build(BuildContext context) =>
      NetworkView(journal: journal, filter: filter);
}
