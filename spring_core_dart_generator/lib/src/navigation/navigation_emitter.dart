// spring_boot_starter_flutter_navigation: the module's `ScreenRoutes` bean,
// made of its `@ScreenRoute` and `@RouteShell` widgets, and the constants
// of each screen (`extension BookPageRoute on BookPage`).
import 'package:code_builder/code_builder.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/core/dart_names.dart';
import 'package:spring_core_dart_generator/src/core/module_emitter.dart';
import 'package:spring_core_dart_generator/src/navigation/navigation_scanning.dart';

const _navigationUrl =
    'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

Reference _nav(String name) => refer(name, _navigationUrl);

// Names the constants of a route extension already use.
const _reservedRouteNames = {'pattern', 'routeName', 'to', 'extra'};

/// Writes the navigation code of one module ([navigation]) through the
/// emitter's [emission].
final class NavigationEmitter {
  /// The navigation code of [navigation], written through [emission].
  NavigationEmitter(this.emission, this.navigation);

  /// The emitter's ways of naming types and values.
  final ModuleEmission emission;

  /// What the navigation part found in the module.
  final NavigationModuleModel navigation;

  /// The `ScreenRoutes` bean of the module's screens and shells, written
  /// with the same builder an app uses in Dart configuration:
  ///
  /// ```dart
  /// ScreenRoutes.route(source: ...)
  ///     .shell((s) => MainTabs(s), (t) => t.branch('/catalog', (b) => b),
  ///         key: MainTabs, source: ...)
  ///     .screen('/catalog/books/{isbn}', (r) => const BookPage(),
  ///         name: 'book-page', params: {'page': int}, source: ...)
  ///     .build()
  /// ```
  ///
  /// Throws `InvalidGenerationSource` for a path two screens of the module
  /// declare, or two not-found screens.
  Expression screenRoutesDefinition() {
    _checkScreens();
    var routes = _nav('ScreenRoutes')
        .property('route')
        .call([], {'source': emission.string(emission.moduleName)});
    for (final shell in navigation.shells) {
      final type = emission.type(shell.element.thisType, shell.element);
      Expression branches = refer('t');
      for (final branch in shell.branches) {
        branches = branches.property('branch').call([
          emission.string(branch),
          emission.closure(['b'], refer('b').code, lambda: true),
        ]);
      }
      routes = routes
          .property('shell')
          .call(
            [
              emission.closure(
                ['s'],
                type.newInstance([refer('s')]).code,
                lambda: true,
              ),
              emission.closure(['t'], branches.code, lambda: true),
            ],
            {'key': type, 'source': emission.string(shell.source)},
          );
    }
    for (final screen in navigation.screens) {
      final type = emission.type(screen.element.thisType, screen.element);
      final widget = screen.constConstructor
          ? type.constInstance([])
          : type.newInstance([]);
      final builder = emission.closure(['r'], widget.code, lambda: true);
      if (screen.notFound) {
        routes = routes.property('notFound').call([builder]);
        continue;
      }
      routes = routes
          .property('screen')
          .call(
            [emission.string(screen.path), builder],
            {
              'name': emission.string(screen.name),
              if (screen.title case final title?)
                'title': emission.string(title),
              if (screen.params.isNotEmpty)
                'params': literalMap({
                  for (final param in screen.params)
                    emission.string(param.name): emission.typeValue(
                      param.type,
                      screen.element,
                    ),
                }),
              if (screen.extra case final extra?)
                'extra': emission.typeValue(extra, screen.element),
              if (screen.shell case final shell?)
                'shell': emission.type(shell.thisType, shell),
              if (screen.branch case final branch?)
                'branch': emission.string(branch),
              if (screen.transition case final transition?)
                'transition': _nav('PageTransition').property(transition),
              if (screen.content case final content?)
                'content': emission.string(content),
              if (!screen.link) 'link': literalFalse,
              if (screen.preAuthorize case final expression?)
                'attributes': literalConstMap({
                  _nav('RouteAttributes')
                      .property('preAuthorize'): emission.string(
                    expression,
                  ),
                }),
              'source': emission.string(screen.source),
            },
          );
    }
    // `BeanDefinition<ScreenRoutes>`: its type is the only one.
    return emission
        .spring('BeanDefinition')
        .newInstance(
          [],
          {
            'name': emission.string('screenRoutes#${emission.moduleName}'),
            'source': emission.string('$_navigationUrl#ScreenRoutes'),
            'create': emission.closure(
              ['r'],
              routes.property('build').call([]).code,
              lambda: true,
            ),
          },
          [_nav('ScreenRoutes')],
        );
  }

  /// The constants of [screen]: `extension BookPageRoute on BookPage` with
  /// its `pattern`, `routeName`, a typed key per path variable, query
  /// parameter and the extra object, and `to(...)`, the location with its
  /// values. A renamed path, variable, parameter or type breaks the code
  /// that uses them.
  Extension routeExtension(ScreenRouteModel screen) {
    final element = screen.element;
    final className = element.name ?? '';
    final variables = {
      for (final variable in screen.variables)
        variable: _routeIdentifier(variable, screen),
    };
    final params = {
      for (final param in screen.params)
        param: _routeIdentifier(param.name, screen),
    };
    final taken = <String>{};
    for (final name in [...variables.values, ...params.values]) {
      if (!taken.add(name)) {
        throw InvalidGenerationSource(
          'The screen $className has two values named "$name" (a path '
          'variable or a parameter); rename one.',
          element: element,
        );
      }
    }
    final string = refer('String');
    Field constant(String name, Expression value, String doc) => Field(
      (f) => f
        ..docs.add(doc)
        ..static = true
        ..modifier = FieldModifier.constant
        ..name = name
        ..assignment = value.code,
    );
    final extra = screen.extra;
    return Extension(
      (e) => e
        ..docs.add(
          '/// The route of [$className]: its path, name, values and `to`.',
        )
        ..name = '${className}Route'
        ..on = emission.type(element.thisType, element)
        ..fields.addAll([
          constant(
            'pattern',
            emission.string(screen.path),
            '/// The path pattern.',
          ),
          constant(
            'routeName',
            emission.string(screen.name),
            "/// The route's name.",
          ),
          for (final MapEntry(key: variable, value: name) in variables.entries)
            constant(
              name,
              _nav('RouteVar')
                  .constInstance([emission.string(variable)], {}, [string]),
              '/// The path variable `$variable`.',
            ),
          for (final MapEntry(key: param, value: name) in params.entries)
            constant(
              name,
              _nav(
                'RouteParam',
              ).constInstance(
                [emission.string(param.name)],
                {},
                [
                  emission.type(param.type, element),
                ],
              ),
              '/// The query parameter `${param.name}`.',
            ),
          if (extra != null)
            constant(
              'extra',
              _nav('RouteExtra')
                  .constInstance([], {}, [emission.type(extra, element)]),
              '/// The extra object, not in the address.',
            ),
        ])
        ..methods.add(
          Method(
            (m) => m
              ..docs.add(
                '/// The location of this screen with these values.',
              )
              ..static = true
              ..returns = _nav('RouteLocation')
              ..name = 'to'
              ..optionalParameters.addAll([
                for (final name in variables.values)
                  Parameter(
                    (p) => p
                      ..name = name
                      ..named = true
                      ..required = true
                      ..type = string,
                  ),
                for (final MapEntry(key: param, value: name) in params.entries)
                  Parameter(
                    (p) => p
                      ..name = name
                      ..named = true
                      ..type = _nullable(emission.type(param.type, element)),
                  ),
                if (extra != null)
                  Parameter(
                    (p) => p
                      ..name = 'extra'
                      ..named = true
                      ..type = _nullable(emission.type(extra, element)),
                  ),
              ])
              ..lambda = true
              ..body = _nav('RouteLocation')
                  .property('expand')
                  .call(
                    [refer('pattern')],
                    {
                      if (variables.isNotEmpty)
                        'pathVariables': literalMap({
                          for (final MapEntry(key: variable, value: name)
                              in variables.entries)
                            emission.string(variable): refer(name),
                        }),
                      if (params.isNotEmpty)
                        'params': literalMap({
                          for (final MapEntry(key: param, value: name)
                              in params.entries)
                            emission.string(param.name): refer(name),
                        }),
                      if (extra != null) 'extra': refer('extra'),
                    },
                  )
                  .code,
          ),
        ),
    );
  }

  void _checkScreens() {
    final byPath = <String, ScreenRouteModel>{};
    ScreenRouteModel? notFound;
    for (final screen in navigation.screens) {
      if (screen.notFound) {
        if (notFound != null) {
          throw InvalidGenerationSource(
            'Two not-found screens: ${notFound.element.name} and '
            '${screen.element.name}.',
            element: screen.element,
          );
        }
        notFound = screen;
        continue;
      }
      final twin = byPath[screen.path];
      if (twin != null) {
        throw InvalidGenerationSource(
          'The path ${screen.path} is declared twice: ${twin.element.name} '
          'and ${screen.element.name}.',
          element: screen.element,
        );
      }
      byPath[screen.path] = screen;
    }
  }

  TypeReference _nullable(TypeReference type) =>
      (type.toBuilder()..isNullable = true).build();
}

// A Dart name for the value [name] of [screen]'s route: `page-size` is
// `pageSize`. Throws for a name the extension uses already or one that
// makes no identifier.
String _routeIdentifier(String name, ScreenRouteModel screen) {
  final parts = name.split(RegExp('[^A-Za-z0-9_]+'))
    ..removeWhere((p) => p.isEmpty);
  final identifier = [
    ...parts.take(1),
    for (final part in parts.skip(1))
      '${part[0].toUpperCase()}${part.substring(1)}',
  ].join();
  final className = screen.element.name ?? '';
  // A reserved word names no constant, and a private name no parameter of
  // `to()`.
  if (identifier.isEmpty ||
      RegExp('^[0-9_]').hasMatch(identifier) ||
      DartNames.isReserved(identifier)) {
    throw InvalidGenerationSource(
      'The value "$name" of the screen $className makes no Dart name for its '
      'constant; rename it.',
      element: screen.element,
    );
  }
  if (_reservedRouteNames.contains(identifier)) {
    throw InvalidGenerationSource(
      'The value "$name" of the screen $className clashes with the '
      'constant $className'
      'Route.$identifier; rename it.',
      element: screen.element,
    );
  }
  return identifier;
}
