// @Configurable: an object the container did not create (e.g. a Flutter
// State) gets its @Autowired / @Value members injected via autowireBean.
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/catalog/catalog.dart';

@Configurable()
class CatalogScreen {
  @Autowired()
  late final CatalogService catalog;

  @Value(r'${app.name}')
  late final String title;
}
