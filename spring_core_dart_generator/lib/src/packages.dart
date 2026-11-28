import 'package:spring_core_dart_generator/src/actuator/actuator_generation.dart';
import 'package:spring_core_dart_generator/src/cache/cache_generation.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_generation.dart';
import 'package:spring_core_dart_generator/src/data/data_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/change_notifier_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/debug_console_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/debug_widget_fields_generation.dart';
import 'package:spring_core_dart_generator/src/flutter/flutter_generation.dart';
import 'package:spring_core_dart_generator/src/navigation/navigation_generation.dart';
import 'package:spring_core_dart_generator/src/restclient/http_service_generation.dart';
import 'package:spring_core_dart_generator/src/scheduling/scheduling_generation.dart';
import 'package:spring_core_dart_generator/src/security/security_generation.dart';
import 'package:spring_core_dart_generator/src/signals/signals_generation.dart';
import 'package:spring_core_dart_generator/src/supabase/supabase_generation.dart';
import 'package:spring_core_dart_generator/src/web/web_generation.dart';
import 'package:spring_core_dart_generator/src/websocket/websocket_generation.dart';

/// The packages' parts of the module build that the generator ships, in
/// the order the builders ask them: that order is the order of what they
/// write (the `SpringWidgetBindings` bean before the `ScreenRoutes` bean,
/// the `BuildContext` getters before the screens' constants) and of the
/// errors they report. A part is a package's: a starter's
/// (`spring_boot_starter_flutter`) or a library's (`spring_web_dart`,
/// `spring_security_core`, `spring_boot_actuator`). What `spring_core_dart`
/// itself brings (the JSON Schemas of `spring.json.schemas`) is the core's,
/// not a part, so its part files come after the parts'.
///
/// The data starter has two: its metadata (the entities and repositories
/// of `spring_metadata.json`) comes first, right after the core's
/// entries; its module part comes last, so its beans (the entities'
/// introspections, the drivers') follow the Flutter and navigation beans,
/// and its checks of the module follow theirs.
///
/// The RestClient starter's part writes the class of each HTTP service
/// interface (`@ImportHttpServices`) and the beans of their groups.
///
/// The web, WebSocket, scheduling, security and cache parts write nothing:
/// they say what their annotations do with the values of a bean's methods
/// (which classes the build describes, and for what), and the cache's
/// checks a proxy. The actuator's adds `build-info.properties` to an
/// application's resources.
///
/// The builder factories of `lib/builder.dart` pass this list to the
/// builders; a new package's part is one more entry here.
const List<PackageGeneration> packageGenerations = [
  DataMetadataGeneration(),
  FlutterGeneration(),
  NavigationGeneration(),
  ChangeNotifierGeneration(),
  DebugConsoleGeneration(),
  DebugWidgetFieldsGeneration(),
  SignalsGeneration(),
  WebGeneration(),
  WebSocketGeneration(),
  SchedulingGeneration(),
  SecurityGeneration(),
  CacheGeneration(),
  ActuatorGeneration(),
  SupabaseGeneration(),
  HttpServiceGeneration(),
  DataGeneration(),
];
