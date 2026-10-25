import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Beans and messages of the application from any widget below
/// `SpringApplicationWidget`.
///
/// ```dart
/// IconButton(
///   onPressed: () => context.bean<Basket>().add(book.isbn),
///   tooltip: context.message('basket.add'),
///   icon: const Icon(Icons.add_shopping_cart),
/// );
/// ```
extension SpringBuildContext on BuildContext {
  /// The running application context (see `SpringScope.of`).
  ApplicationContext get springContext => SpringScope.of(this);

  /// The bean of type [T]; with [qualifier], the bean of that name, alias
  /// or qualifier. Like `ApplicationContext.getBean`.
  T bean<T extends Object>({String? qualifier}) =>
      SpringScope.beanOf<T>(this, qualifier: qualifier);

  /// The message [code] of the application's `MessageSource`
  /// (`lib/resources/messages_{locale}.properties`) in the app's current
  /// locale (`Localizations`, else the device's), formatted with [args];
  /// [defaultMessage] when there is no such message.
  ///
  /// ```dart
  /// // messages.properties: basket.total=Total: {0}
  /// Text(context.message('basket.total', args: [total]));
  /// ```
  String message(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
  }) => springContext.getMessage(
    code,
    args: args,
    defaultMessage: defaultMessage,
    locale:
        (Localizations.maybeLocaleOf(this) ??
                PlatformDispatcher.instance.locale)
            .toString(),
  );
}
