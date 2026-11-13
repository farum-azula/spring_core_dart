import 'package:flutter/widgets.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show FlutterAppCustomizer, FlutterAppSettings;
import 'package:spring_boot_starter_flutter_scene/src/widgets/spring_scene_view.dart';

/// Puts the application's scene under every screen of the app
/// (`spring.flutter.scene.app.placement: background`): a
/// `SpringSceneView` below the app's content, so it is a plain widget
/// where scenes do not draw. The screens over it must not paint an opaque
/// background of their own.
final class ApplicationSceneBackground
    implements FlutterAppCustomizer, Ordered {
  /// The background.
  const ApplicationSceneBackground();

  // Inside the debug dock and what else wraps the app later.
  @override
  int get order => 0;

  @override
  void customize(FlutterAppSettings app) {
    final inner = app.builder;
    app.builder = (context, child) {
      final content = inner == null ? child : inner(context, child);
      return Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(child: SpringSceneView(name: 'application')),
          ?content,
        ],
      );
    };
  }
}
