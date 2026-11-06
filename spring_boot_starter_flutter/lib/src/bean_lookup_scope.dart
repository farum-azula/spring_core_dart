import 'dart:async';

import 'package:flutter/widgets.dart';

/// Runs the bean lookups of the widgets below it (`context.bean<T>()`,
/// the generated getters, the beans records of Spring widgets) with
/// [zoneValues], so a custom scope can tell which part of the app asks.
///
/// The navigation starter puts one around every screen: a bean of the
/// `route` scope looked up by a widget is that widget's screen's, not the
/// one on top. Apps rarely use it directly.
class BeanLookupScope extends InheritedWidget {
  /// Makes the lookups below run with [zoneValues].
  const BeanLookupScope({
    required this.zoneValues,
    required super.child,
    super.key,
  });

  /// The values of the zone the lookups run in.
  final Map<Object?, Object?> zoneValues;

  /// Runs [lookup] in the zone of the nearest [BeanLookupScope] above
  /// [context], or as it is without one.
  static T run<T>(BuildContext context, T Function() lookup) {
    final scope = context.getInheritedWidgetOfExactType<BeanLookupScope>();
    return scope == null
        ? lookup()
        : runZoned(lookup, zoneValues: scope.zoneValues);
  }

  @override
  bool updateShouldNotify(BeanLookupScope oldWidget) => false;
}
