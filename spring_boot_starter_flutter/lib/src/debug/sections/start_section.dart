import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_stages.dart';

/// The start: when each stage of the start was reached (the web page, the
/// engine, the splash, the beans, the tasks, the app).
final class DebugStartSection implements DebugPanelSection, Ordered {
  /// The section of [stages]; `null` outside `SpringApplicationWidget`.
  const DebugStartSection(this.stages);

  /// The stages reached.
  final SplashStages? stages;

  @override
  String get title => 'Start';

  @override
  int get order => 50;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final stages = this.stages;
    if (stages == null) {
      return Text(
        'No stages: the app runs without its widget.',
        style: style.text,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final MapEntry(key: stage, value: at) in stages.reached.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${stage.name.padRight(10)} ${at.inMilliseconds} ms',
              style: style.code,
            ),
          ),
      ],
    );
  }
}
