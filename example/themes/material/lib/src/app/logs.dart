import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_material/spring_gen/main.spring.dart';

/// Logs the pages the user opens (Spring's logger, never print).
@Component()
@Log(topic: 'theme_showcase_material.pages')
class PageLog {
  void opened(String page) => log.info('page opened', fields: {'page': page});
}

/// Logs every theme the user selects.
@Component()
@Log(topic: 'theme_showcase_material.themes')
class ThemeLog {
  ThemeLog(this._selection) {
    _selection.addListener(
      () => log.info('theme selected', fields: {'theme': _selection.active}),
    );
  }

  final ThemeSelection _selection;
}

/// Logs the screens the navigator opens and closes: a page transition is
/// the `motion.page-transition` of the active theme.
@Component()
@Log(topic: 'theme_showcase_material.navigation')
class RouteLog extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.debug('open ${route.settings.name ?? route.runtimeType}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.debug('close ${route.settings.name ?? route.runtimeType}');
}
