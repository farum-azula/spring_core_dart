// A Flutter app with a 3D scene among its widgets: a model named in the
// properties, shown in a scene of its own, with a status line that says
// what is being loaded. The generator writes example.spring.dart
// (`dart run build_runner build`).
import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

import 'spring_gen/example.spring.dart';

/// The page: the model in its scene, and the scenes' status under it.
class Showroom extends StatelessWidget {
  /// The showroom.
  const Showroom({super.key});

  @override
  Widget build(BuildContext context) {
    // No bean when the app runs with spring.flutter.scene.enabled=false:
    // the scene below is then its placeholder, and there is no status.
    final status = context.springContext
        .getBeanProvider<SceneStatus>()
        .getIfAvailable();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 320,
          height: 320,
          // A scene that owns itself. Where scenes do not draw (turned
          // off, no WebGL2, the engine failed) only the placeholder is
          // built.
          child: SpringSceneView.declarative(
            name: 'showroom',
            placeholder: Center(child: Text('hero')),
            // spring.flutter.scene.models.hero: loaded once, a clone here.
            children: [SpringSceneModel('hero')],
          ),
        ),
        if (status != null)
          ValueListenableBuilder(
            valueListenable: status,
            // "Compiling shaders", "Loading hero, 1 of 1", then nothing.
            builder: (context, step, _) => Text(status.text ?? ''),
          ),
      ],
    );
  }
}

/// Counts the models as they come: every step of the scenes' start is an
/// application event.
@Service()
class LoadedModels {
  /// The names of the models loaded so far.
  final List<String> names = [];

  /// Hears each model that finished loading.
  @EventListener()
  void onLoaded(SceneModelLoadedEvent event) => names.add(event.name);
}

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const Showroom(),
  ),
);
