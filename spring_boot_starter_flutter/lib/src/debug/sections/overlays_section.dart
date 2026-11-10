import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';

/// The debug panel's Overlays tab: each debug overlay on screen or not,
/// and, with the `drag` feature, every moved one put back in its corner.
final class DebugOverlaysSection implements DebugPanelSection, Ordered {
  /// The tab of [overlays]; [placement] when they can be moved.
  const DebugOverlaysSection(this.overlays, {this.placement});

  /// The overlays of the app's debug features.
  final List<DebugOverlay> overlays;

  /// Where moved overlays are; `null` without the `drag` feature.
  final DebugOverlayPlacement? placement;

  @override
  String get title => 'Overlays';

  @override
  int get order => 15;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    if (overlays.isEmpty) {
      return Text(
        'No debug feature with an overlay is in this build '
        '(spring.flutter.debug.frame-meter.enabled, '
        'spring.flutter.debug.timeline.enabled, '
        'spring.flutter.debug.isolates.enabled).',
        style: style.text.copyWith(color: style.muted),
      );
    }
    final placement = this.placement;
    return ListenableBuilder(
      listenable: Listenable.merge([...overlays, ?placement]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('On screen', style: style.title),
          const SizedBox(height: 8),
          Wrap(
            children: [
              for (final overlay in overlays)
                DebugChip(
                  overlay.title,
                  selected: overlay.shown,
                  onTap: () => overlay.shown = !overlay.shown,
                ),
            ],
          ),
          if (placement != null) ...[
            const SizedBox(height: 12),
            DebugChip('Back to their corners', onTap: placement.reset),
          ],
        ],
      ),
    );
  }
}
