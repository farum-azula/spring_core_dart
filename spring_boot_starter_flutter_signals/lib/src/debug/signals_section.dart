import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugPanelSection, DebugStyle;
import 'package:spring_boot_starter_flutter_signals/src/signal_bean.dart';
import 'package:spring_boot_starter_flutter_signals/src/signal_members.dart';

/// The state's tab of the debug panel: every bean with followed state
/// that lives now, by its class, with its members by name.
///
/// - A `@Signal` field: its value and how often it was assigned.
/// - A `@Computed` value: what it is now; for an asynchronous one, where
///   the load is and how often it ran.
/// - An `@Effect` method: how often it ran. An effect that runs far more
///   often than its state changes reads something it should not follow.
///
/// A member shows once it was first used: a field nobody read is not
/// followed yet. A field marked `@Signal(hidden: true)` shows no value.
final class SignalsDebugSection implements DebugPanelSection, Ordered {
  /// The tab over the state kept in [beans].
  const SignalsDebugSection(this.beans);

  /// The beans with followed state.
  final SignalBeans beans;

  @override
  String get title => 'State';

  @override
  int get order => 59;

  @override
  Widget build(BuildContext context) => _SignalsDebugView(beans);

  /// What the tab says of [member]: its value and how often it changed;
  /// nothing of a hidden one's value, and what a computed value that
  /// fails threw.
  @visibleForTesting
  static String describe(SignalMember member) => switch (member) {
    ValueMember(unset: true) => 'late, not assigned yet',
    ValueMember(hidden: true, :final changes) =>
      'hidden, assigned $changes ${changes == 1 ? 'time' : 'times'}',
    ValueMember(:final changes) =>
      '${_short(member.peek())}, assigned $changes '
          '${changes == 1 ? 'time' : 'times'}',
    AsyncMember(:final loads) =>
      '${member.stateNow}, loaded $loads ${loads == 1 ? 'time' : 'times'}',
    ComputedMember() => _computed(member),
  };

  static String _computed(ComputedMember member) {
    try {
      return 'computed: ${_short(member.peek())}';
    } on Object catch (error) {
      return 'failed: ${_short(error)}';
    }
  }

  static String _short(Object? value) {
    final text = '$value'.replaceAll('\n', ' ');
    return text.length <= 120 ? text : '${text.substring(0, 117)}...';
  }
}

class _SignalsDebugView extends StatefulWidget {
  const _SignalsDebugView(this.beans);

  final SignalBeans beans;

  @override
  State<_SignalsDebugView> createState() => _SignalsDebugViewState();
}

class _SignalsDebugViewState extends State<_SignalsDebugView> {
  // The values move with the app: read twice a second, without following
  // them (the tab must not become a reader of the state it shows).
  late final Timer _refresh = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _refresh;
  }

  @override
  void dispose() {
    _refresh.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final beans = widget.beans.live.toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (beans.isEmpty)
            Text(
              'No bean with a @Signal, @Computed or @Effect member lives now.',
              style: style.text.copyWith(color: style.muted),
            ),
          for (final bean in beans) ...[
            Text(bean.label, style: style.title),
            const SizedBox(height: 6),
            for (final member in bean.members.values)
              _row(
                style,
                member.name.split('.').last,
                SignalsDebugSection.describe(member),
              ),
            for (final MapEntry(key: name, value: runs)
                in bean.effectRuns.entries)
              _row(
                style,
                '$name()',
                'effect, ran $runs ${runs == 1 ? 'time' : 'times'}',
              ),
            if (bean.members.isEmpty && bean.effectRuns.isEmpty)
              Text(
                'Nothing read yet.',
                style: style.text.copyWith(color: style.muted),
              ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  static Widget _row(DebugStyle style, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 160,
          child: Text(label, style: style.text.copyWith(color: style.muted)),
        ),
        Expanded(child: Text(value, style: style.code)),
      ],
    ),
  );
}
