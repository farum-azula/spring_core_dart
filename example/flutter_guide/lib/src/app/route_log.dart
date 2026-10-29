import 'package:flutter/widgets.dart';
import 'package:neon_books_app/main.spring.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

/// Every `NavigatorObserver` bean becomes an observer of the app widget's
/// navigator (`SpringApp`): this one logs the screens opened and closed.
@Component()
@Log(topic: 'neon.navigation')
class RouteLog extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.debug('open ${_name(route)}');

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.debug('close ${_name(route)}');

  static String _name(Route<dynamic> route) =>
      route.settings.name ?? route.runtimeType.toString();
}
