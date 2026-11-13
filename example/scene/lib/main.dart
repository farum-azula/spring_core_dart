// Scene Showcase: 3D scenes among Flutter widgets with
// spring_boot_starter_flutter_scene. Run it with `flutter run -d chrome`
// and read lib/resources/application.yml next to it.
//
// - the application's scene under the page (lib/src/backdrop.dart);
// - a model of the properties in a scene of its own (lib/src/showroom.dart);
// - a scene behind a widget (lib/src/plate_card.dart);
// - the scenes' tab of the debug panel: ⌘⇧D (Ctrl+Shift+D), "Scenes".
import 'package:flutter/widgets.dart';
import 'package:scene_showcase/spring_gen/main.spring.dart';
import 'package:scene_showcase/src/showcase_page.dart';
import 'package:spring_boot_starter_flutter_scene/spring_boot_starter_flutter_scene.dart';

@SpringBootApplication()
void main() => runApp(
  SpringApplicationWidget(
    application: () => springApplication,
    home: const ShowcasePage(),
  ),
);
