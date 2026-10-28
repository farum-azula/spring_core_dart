import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/spring_scope.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';

/// Gives any widget below `SpringApplicationWidget` access to the
/// application: a bean with `context.bean<T>()`, a translated text with
/// `context.message('key')`, and the context itself.
///
/// These work in every widget, including plain `StatelessWidget`s and
/// callbacks, so they suit one-off uses: a button that calls a service, a
/// label from the messages files. They do not rebuild the widget when a
/// state bean changes; for beans that a widget shows, declare them in a
/// `SpringStatelessWidget` or `SpringStatefulWidget` instead.
///
/// ```dart
/// // A button that puts a book into the basket, with a translated tooltip.
/// IconButton(
///   onPressed: () => context.bean<Basket>().add(book.isbn),
///   tooltip: context.message('basket.add'),
///   icon: const Icon(Icons.add_shopping_cart),
/// );
/// ```
extension SpringBuildContext on BuildContext {
  /// The application context of the nearest `SpringScope` (the one
  /// `SpringApplicationWidget` puts at the root). The widget is rebuilt
  /// when the context is replaced, after a hot reload that changed beans.
  /// Throws a `FlutterError` when there is no `SpringScope` above.
  ApplicationContext get springContext => SpringScope.of(this);

  /// The bean of type [T]; with [qualifier], the bean of that name, alias
  /// or qualifier. Throws when there is no such bean, or several without a
  /// primary one, like `ApplicationContext.getBean`.
  T bean<T extends Object>({String? qualifier}) =>
      SpringScope.beanOf<T>(this, qualifier: qualifier);

  /// The text of message [code] from the application's messages files
  /// (`lib/resources/messages.properties`, `messages_ja.properties`, ...),
  /// in the app's current locale (the one of `Localizations`, else the
  /// device's), with [args] put into its `{0}`, `{1}`, ... placeholders.
  ///
  /// [defaultMessage] is returned when no file has the code. Without one, a
  /// missing code throws a `NoSuchMessageException` (or gives the code
  /// itself when `spring.messages.use-code-as-default-message=true`).
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
