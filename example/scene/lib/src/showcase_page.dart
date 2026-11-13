import 'package:flutter/widgets.dart';
import 'package:scene_showcase/src/plate_card.dart';
import 'package:scene_showcase/src/showroom.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

/// The one page: the application's scene shows through it (the page
/// paints no background of its own), the showroom and the card over it.
class ShowcasePage extends StatelessWidget {
  /// The page.
  const ShowcasePage({super.key});

  static const _text = TextStyle(color: Color(0xFFE6EAF2), fontSize: 15);

  @override
  Widget build(BuildContext context) {
    // No bean when the app runs with spring.flutter.scene.enabled: false.
    final status = context.springContext
        .getBeanProvider<SceneStatus>()
        .getIfAvailable();
    return DefaultTextStyle(
      style: _text,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scene Showcase',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              const Showroom(),
              const SizedBox(height: 32),
              const SizedBox(
                width: 360,
                child: PlateCard(
                  child: Text(
                    'A scene behind a widget: the plate is a mesh of this '
                    "card's own size, the text an ordinary widget.",
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (status != null)
                ValueListenableBuilder(
                  valueListenable: status,
                  builder: (context, _, _) => Text(
                    status.text ?? 'The scenes are ready.',
                    key: const ValueKey('status'),
                    style: const TextStyle(color: Color(0xFF8A93A6)),
                  ),
                )
              else
                const Text('Scenes are turned off.'),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => context.springContext
                    .getBeanProvider<DebugPanel>()
                    .ifAvailable((panel) => panel.toggle()),
                child: const Text(
                  'Debug panel: Ctrl/⌘ + Shift + D, tab "Scenes"',
                  style: TextStyle(
                    color: Color(0xFF22E6FF),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
