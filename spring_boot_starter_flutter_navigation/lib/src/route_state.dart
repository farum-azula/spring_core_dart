import 'package:flutter/foundation.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter_navigation/src/route_location.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show PathPattern;

/// A query parameter or path variable that does not convert to the type
/// the screen declared (`?page=abc` for an `int`): the navigation shows
/// the route's error screen instead of the screen.
final class RouteValueException implements Exception {
  /// The value [value] of [name] that is no [type].
  RouteValueException(this.name, this.value, this.type, [this.cause]);

  /// The parameter or variable.
  final String name;

  /// The text from the address.
  final String value;

  /// The type the screen declared.
  final Type type;

  /// What the conversion threw.
  final Object? cause;

  @override
  String toString() => 'The value "$value" of "$name" is no $type';
}

/// One opened screen's route: its address, the values the pattern
/// captured, the query parameters converted to the types asked for, the
/// extra object.
///
/// A screen reads it through `context.route`, a singleton through
/// `RouteTemplate` (the screen on top).
///
/// ```dart
/// route.uri;                  // /catalog/books/978-0?page=2
/// route.pattern;              // /catalog/books/{isbn}
/// route.pathVariable('isbn'); // 978-0
/// route.param<int>('page');   // 2
/// route.extra<BookSummary>(); // passed with the navigation, or null
/// ```
@immutable
final class RouteState {
  /// The state of [location] opened on [route] (null: no route matched),
  /// with the [variables] its pattern captured; [conversion] converts the
  /// values, [messages] translates the title.
  const RouteState({
    required this.location,
    required this.route,
    required this.variables,
    required this.conversion,
    this.messages,
    this.error,
  });

  /// Where the screen was opened.
  final RouteLocation location;

  /// The route that matched, or `null` for the not-found screen.
  final ScreenRouteDefinition? route;

  /// The values the pattern captured, percent-decoded.
  final Map<String, String> variables;

  /// Converts the values to the types asked for.
  final ConversionService conversion;

  /// Translates `#{key}` titles; `null` leaves them as written.
  final MessageSource? messages;

  /// Why the route's error screen shows (a value that did not convert, a
  /// filter that threw), or `null`.
  final Object? error;

  /// The address: path, query, fragment.
  Uri get uri => location.uri;

  /// The path of the address.
  String get path => location.path;

  /// The pattern that matched (`/catalog/books/{isbn}`), or `null` when
  /// none did.
  String? get pattern => route?.pattern.pattern;

  /// The route's name, or `null`.
  String? get name => route?.name;

  /// Whether no route matched the address.
  bool get notFound => route == null || route!.notFound;

  /// The route's title, a `#{key}` translated in [locale] (the messages'
  /// default without one), or `null`.
  String? title([String? locale]) {
    final title = route?.title;
    if (title == null) {
      return null;
    }
    final key = _messageKey(title);
    if (key == null || messages == null) {
      return title;
    }
    return messages!.getMessage(key, defaultMessage: key, locale: locale);
  }

  /// The resource the route's `content` names for this address
  /// (`resources:content/docs/core/beans.md` for `/docs/core/beans` on
  /// `resources:content/docs/`), or `null`.
  String? get content {
    final content = route?.content;
    if (content == null) {
      return null;
    }
    if (!content.endsWith('/')) {
      return content;
    }
    final rest = route!.restVariable;
    final value = rest == null ? null : variables[rest];
    // Never a file outside the folder: no `.` / `..` segment, no backslash
    // (the navigation refuses such addresses before; this is the second
    // line).
    if (value != null &&
        (value.contains(r'\') ||
            value.split('/').any((s) => s == '.' || s == '..'))) {
      return null;
    }
    final file = value == null || value.isEmpty || value == '/'
        ? 'index'
        : value.startsWith('/')
        ? value.substring(1)
        : value;
    final trimmed = file.endsWith('/') ? '${file}index' : file;
    return '$content$trimmed.md';
  }

  /// The value [name] the path pattern captured. Throws an [ArgumentError]
  /// when the pattern has no such variable.
  String pathVariable(String name) {
    final value = variables[name];
    if (value == null) {
      throw ArgumentError.value(
        name,
        'name',
        'The route ${pattern ?? path} has no path variable "$name"',
      );
    }
    return value;
  }

  /// The query parameter [name] converted to [T] through the application's
  /// `ConversionService` (its first value), or `null` when absent. Throws a
  /// [RouteValueException] when the value does not convert.
  T? param<T>(String name) {
    final values = location.queryParameters[name];
    if (values == null || values.isEmpty) {
      return null;
    }
    return _convert<T>(name, values.first);
  }

  /// Every value of the query parameter [name] (`?tag=a&tag=b`), converted
  /// to [T]; empty when absent.
  List<T> params<T>(String name) => [
    for (final value in location.queryParameters[name] ?? const <String>[])
      _convert<T>(name, value),
  ];

  /// The extra object when it is a [T], else `null`.
  T? extra<T>() => switch (location.extra) {
    final T value => value,
    _ => null,
  };

  /// The value of a typed key: a path variable, a query parameter or the
  /// extra object.
  T get<T>(RouteKey<T> key) => switch (key) {
    RouteVar(:final name) => _convert<T>(name, pathVariable(name)),
    RouteParam(:final name) =>
      (location.queryParameters[name]?.isNotEmpty ?? false)
          ? _convert<T>(name, location.queryParameters[name]!.first)
          : null as T,
    RouteExtra() => location.extra is T ? location.extra as T : null as T,
  };

  /// The attributes declared with the route.
  Map<String, Object?> get attributes => route?.attributes ?? const {};

  /// Whether the path matches [pattern] (Spring's syntax: `/catalog/**`).
  bool matches(String pattern) => PathPattern.parse(pattern).matches(path);

  /// This state with [location]'s query parameters instead of its own.
  RouteState withLocation(RouteLocation location) => RouteState(
    location: location,
    route: route,
    variables: variables,
    conversion: conversion,
    messages: messages,
  );

  /// Converts every declared parameter (`params` of the route), so a
  /// wrong value is found when the screen opens; throws the
  /// [RouteValueException] of the first that fails.
  void checkDeclared() {
    final declared = route?.params ?? const <String, Type>{};
    for (final MapEntry(:key, :value) in declared.entries) {
      for (final text in location.queryParameters[key] ?? const <String>[]) {
        _convertTo(key, text, value);
      }
    }
  }

  T _convert<T>(String name, String value) {
    if (value is T) {
      return value as T;
    }
    try {
      return conversion.convert<T>(value);
    } on Object catch (e) {
      throw RouteValueException(name, value, T, e);
    }
  }

  void _convertTo(String name, String value, Type type) {
    if (type == String || type == Object) {
      return;
    }
    try {
      conversion.convertTo(value, type);
    } on Object catch (e) {
      throw RouteValueException(name, value, type, e);
    }
  }

  static String? _messageKey(String title) =>
      title.startsWith('#{') && title.endsWith('}')
      ? title.substring(2, title.length - 1)
      : null;

  @override
  String toString() => 'RouteState($location, ${pattern ?? 'not found'})';
}
