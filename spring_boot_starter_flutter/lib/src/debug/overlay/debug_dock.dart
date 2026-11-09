import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show Ordered;
import 'package:spring_boot_starter_flutter/src/debug/debug_panel.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/overlay/debug_overlay.dart';
import 'package:spring_boot_starter_flutter/src/frame_meter/frame_meter.dart';
import 'package:spring_boot_starter_flutter/src/spring_app.dart';

/// The settings of the `debugDock` (`spring.flutter.debug.overlays.*`).
final class DebugDockSettings {
  /// The dock's settings.
  const DebugDockSettings({
    this.layout = DebugOverlayLayout.auto,
    this.maxHeight = 0.4,
    this.margin = EdgeInsets.zero,
  });

  /// How the overlays of a corner are put together.
  final DebugOverlayLayout layout;

  /// The room of a corner for `auto`, a fraction of the screen's height.
  final double maxHeight;

  /// Kept free around the overlays (a header under the top corners), past
  /// the screen's safe area.
  final EdgeInsets margin;
}

/// Puts the debug overlays shown over the app ([DebugDock]); hidden while
/// the debug panel is open ([hiddenWhile]), which shows them itself.
final class DebugDockCustomizer implements FlutterAppCustomizer, Ordered {
  /// The dock of [overlays] with [settings].
  const DebugDockCustomizer(
    this.overlays, {
    this.settings = const DebugDockSettings(),
    this.placement,
    this.hiddenWhile,
  });

  /// The overlays.
  final List<DebugOverlay> overlays;

  /// How they are put together.
  final DebugDockSettings settings;

  /// Where moved overlays are; `null` without the `drag` feature.
  final DebugOverlayPlacement? placement;

  /// While it is true the dock shows nothing (the debug panel is open).
  final ValueListenable<bool>? hiddenWhile;

  /// Applied early: the timeline's view (`200`) and the debug panel wrap
  /// it and cover it, and so do the app's own wrappers, whose theme it
  /// uses.
  @override
  int get order => 100;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) => DebugDock(
      overlays: overlays,
      settings: settings,
      placement: placement,
      hiddenWhile: hiddenWhile,
      child: inner == null ? child! : inner(context, child),
    );
  }
}

/// [child] with the debug [overlays] shown over it: those of one corner
/// one under the other, or one at a time with dots to swipe between, as
/// [settings] say; a freely moved one where it was left.
class DebugDock extends StatelessWidget {
  /// The dock over [child].
  const DebugDock({
    required this.overlays,
    required this.child,
    this.settings = const DebugDockSettings(),
    this.placement,
    this.hiddenWhile,
    super.key,
  });

  /// The overlays.
  final List<DebugOverlay> overlays;

  /// The app.
  final Widget child;

  /// How the overlays are put together.
  final DebugDockSettings settings;

  /// Where moved overlays are.
  final DebugOverlayPlacement? placement;

  /// While it is true nothing shows.
  final ValueListenable<bool>? hiddenWhile;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([...overlays, ?placement, ?hiddenWhile]),
    child: child,
    builder: (context, app) {
      final shown = [
        if (hiddenWhile?.value != true)
          for (final overlay in overlays)
            if (overlay.shown) overlay,
      ]..sort((a, b) => a.order.compareTo(b.order));
      if (shown.isEmpty) {
        return app!;
      }
      final byCorner = <DebugOverlayCorner, List<DebugOverlay>>{};
      final free = <(DebugOverlay, Offset)>[];
      for (final overlay in shown) {
        if (placement?.freeOf(overlay) case final at?) {
          free.add((overlay, at));
        } else {
          (byCorner[placement?.cornerOf(overlay) ?? overlay.corner] ??= []).add(
            overlay,
          );
        }
      }
      return Stack(
        textDirection: TextDirection.ltr,
        children: [
          app!,
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: settings.margin.add(const EdgeInsets.all(8)),
                child: LayoutBuilder(
                  builder: (context, room) => Stack(
                    children: [
                      for (final MapEntry(key: corner, value: list)
                          in byCorner.entries)
                        _corner(corner, list, room),
                      for (final (overlay, at) in free)
                        Positioned(
                          left: at.dx * room.maxWidth,
                          top: at.dy * room.maxHeight,
                          child: _overlay(context, overlay),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _overlay(BuildContext context, DebugOverlay overlay) {
    final built = overlay.build(context);
    return placement?.movable(overlay, built) ?? built;
  }

  Widget _corner(
    DebugOverlayCorner corner,
    List<DebugOverlay> list,
    BoxConstraints room,
  ) {
    final top =
        corner == FrameMeterPosition.topLeft ||
        corner == FrameMeterPosition.topRight;
    final left =
        corner == FrameMeterPosition.topLeft ||
        corner == FrameMeterPosition.bottomLeft;
    const gap = 8.0;
    final height =
        list.fold(0.0, (sum, o) => sum + o.size.height) +
        gap * (list.length - 1);
    final width = list.fold(
      0.0,
      (most, o) => o.size.width > most ? o.size.width : most,
    );
    final fits =
        height <= room.maxHeight * settings.maxHeight &&
        width <= room.maxWidth / 2;
    final pages =
        list.length > 1 &&
        (settings.layout == DebugOverlayLayout.pages ||
            (settings.layout == DebugOverlayLayout.auto && !fits));
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: left ? 0 : null,
      right: left ? null : 0,
      child: pages
          ? _Pages(
              key: ValueKey(corner),
              overlays: list,
              top: top,
              left: left,
              build: _overlay,
            )
          : Builder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: left
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                verticalDirection: top
                    ? VerticalDirection.down
                    : VerticalDirection.up,
                children: [
                  for (final (i, overlay) in list.indexed) ...[
                    if (i > 0) const SizedBox(height: gap),
                    _overlay(context, overlay),
                  ],
                ],
              ),
            ),
    );
  }
}

// The overlays of a corner one at a time: a horizontal swipe, a wheel turn
// or a dot changes the page. The dots are on the screen's side, so they
// never go under its edge.
class _Pages extends StatefulWidget {
  const _Pages({
    required this.overlays,
    required this.top,
    required this.left,
    required this.build,
    super.key,
  });

  final List<DebugOverlay> overlays;
  final bool top;
  final bool left;
  final Widget Function(BuildContext context, DebugOverlay overlay) build;

  @override
  State<_Pages> createState() => _PagesState();
}

class _PagesState extends State<_Pages> {
  String? _shown;
  DateTime _turned = DateTime(0);

  int get _index {
    final i = widget.overlays.indexWhere((o) => o.id == _shown);
    return i < 0 ? 0 : i;
  }

  void _go(int by) {
    final count = widget.overlays.length;
    setState(() => _shown = widget.overlays[(_index + by) % count].id);
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    final now = DateTime.now();
    // One turn of a wheel or a trackpad's swipe is many events: one page.
    if (now.difference(_turned) < const Duration(milliseconds: 400)) {
      return;
    }
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta.abs() > 4) {
      _turned = now;
      _go(delta > 0 ? 1 : -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    final index = _index;
    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, overlay) in widget.overlays.indexed)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _shown = overlay.id),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index
                      ? style.foreground
                      : style.foreground.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
      ],
    );
    return Listener(
      onPointerSignal: _wheel,
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity.abs() > 100) {
            _go(velocity < 0 ? 1 : -1);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.left
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          verticalDirection: widget.top
              ? VerticalDirection.down
              : VerticalDirection.up,
          children: [
            KeyedSubtree(
              key: ValueKey(widget.overlays[index].id),
              child: widget.build(context, widget.overlays[index]),
            ),
            dots,
          ],
        ),
      ),
    );
  }
}

/// Whether [panel] is open, as a [ValueListenable]: the dock hides while
/// it is.
final class DebugPanelOpen extends ChangeNotifier
    implements ValueListenable<bool> {
  /// Follows [panel].
  DebugPanelOpen(this.panel) {
    panel.addListener(notifyListeners);
  }

  /// The debug panel.
  final DebugPanel panel;

  @override
  bool get value => panel.isOpen;

  @override
  void dispose() {
    panel.removeListener(notifyListeners);
    super.dispose();
  }
}
