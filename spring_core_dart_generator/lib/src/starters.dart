import 'package:spring_core_dart_generator/src/actuator/actuator_generation.dart';
import 'package:spring_core_dart_generator/src/cache/cache_generation.dart';
import 'package:spring_core_dart_generator/src/core/starter_generation.dart';
import 'package:spring_core_dart_generator/src/data/data_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/change_notifier_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_generation.dart';
import 'package:spring_core_dart_generator/src/json_schemas/json_schemas_generation.dart';
import 'package:spring_core_dart_generator/src/navigation/navigation_generation.dart';
import 'package:spring_core_dart_generator/src/scheduling/scheduling_generation.dart';
import 'package:spring_core_dart_generator/src/security/security_generation.dart';
import 'package:spring_core_dart_generator/src/signals/signals_generation.dart';
import 'package:spring_core_dart_generator/src/web/web_generation.dart';
import 'package:spring_core_dart_generator/src/websocket/websocket_generation.dart';

/// The starters' parts of the module build that the generator ships, in
/// the order the builders ask them: that order is the order of what they
/// write (the `SpringWidgetBindings` bean before the `ScreenRoutes` bean,
/// the `BuildContext` getters before the screens' constants, the Flutter
/// starter's part files before the JSON Schemas') and of the errors they
/// report.
///
/// The data starter has two: its metadata (the entities and repositories
/// of `spring_metadata.json`) comes first, right after the core's
/// entries; its module part comes last, so its beans (the entities'
/// introspections, the drivers') follow the Flutter and navigation beans,
/// and its checks of the module follow theirs.
///
/// The web, WebSocket, scheduling, security and cache parts write nothing:
/// they say what their annotations do with the values of a bean's methods
/// (which classes the build describes, and for what), and the cache's
/// checks a proxy. The actuator's adds `build-info.properties` to an
/// application's resources.
///
/// The builder factories of `lib/builder.dart` pass this list to the
/// builders; a new starter's part is one more entry here.
const List<StarterGeneration> starterGenerations = [
  DataMetadataGeneration(),
  FlutterGeneration(),
  NavigationGeneration(),
  ChangeNotifierGeneration(),
  SignalsGeneration(),
  WebGeneration(),
  WebSocketGeneration(),
  SchedulingGeneration(),
  SecurityGeneration(),
  CacheGeneration(),
  ActuatorGeneration(),
  JsonSchemasGeneration(),
  DataGeneration(),
];
