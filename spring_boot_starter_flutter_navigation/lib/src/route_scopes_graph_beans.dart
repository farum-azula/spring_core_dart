import 'package:flutter/widgets.dart' show LocalKey;
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart'
    show DebugGraphRouteBeans;
import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_scopes.dart';

/// The live `route` beans of [RouteScopes] for the application graph of
/// the debug tools, which groups the beans by route with them
/// (`routeScopesGraphBeans`). It is a bean of a debug module only, so a
/// build without the graph has neither it nor the interface. It reads the
/// scopes when the graph asks and keeps nothing.
final class RouteScopesGraphBeans implements DebugGraphRouteBeans {
  /// The beans of [scopes].
  const RouteScopesGraphBeans(this._scopes);

  final RouteScopes _scopes;

  @override
  Set<String> get routeScopeNames => const {NavigationScopes.route};

  @override
  Map<LocalKey, Map<String, Object>> liveBeansByPage() => {
    for (final MapEntry(key: id, value: beans)
        in _scopes.liveRouteBeans().entries)
      ScreenEntry.pageKeyOf(id): beans,
  };
}
