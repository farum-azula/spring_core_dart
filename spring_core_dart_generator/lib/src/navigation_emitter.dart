part of 'module_emitter.dart';

// spring_boot_starter_flutter_navigation: the module's `ScreenRoutes` bean,
// made of its `@ScreenRoute` and `@RouteShell` widgets, and the constants
// of each screen (`extension BookPageRoute on BookPage`).

const _navigationUrl =
    'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';

Reference _nav(String name) => refer(name, _navigationUrl);

// Names the constants of a route extension already use.
const _reservedRouteNames = {'pattern', 'routeName', 'to', 'extra'};

extension _NavigationEmitter on ModuleEmitter {
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
  Expression screenRoutesDefinition(String moduleName) {
    _checkScreens();
    var routes = _nav(
      'ScreenRoutes',
    ).property('route').call([], {'source': _str(moduleName)});
    for (final shell in _module.shells) {
      final type = _type(shell.element.thisType, shell.element);
      Expression branches = refer('t');
      for (final branch in shell.branches) {
        branches = branches.property('branch').call([
          _str(branch),
          _closure(['b'], refer('b').code, lambda: true),
        ]);
      }
      routes = routes
          .property('shell')
          .call(
            [
              _closure(
                ['s'],
                type.newInstance([refer('s')]).code,
                lambda: true,
              ),
              _closure(['t'], branches.code, lambda: true),
            ],
            {'key': type, 'source': _str(shell.source)},
          );
    }
    for (final screen in _module.screens) {
      final type = _type(screen.element.thisType, screen.element);
      final widget = screen.constConstructor
          ? type.constInstance([])
          : type.newInstance([]);
      final builder = _closure(['r'], widget.code, lambda: true);
      if (screen.notFound) {
        routes = routes.property('notFound').call([builder]);
        continue;
      }
      routes = routes
          .property('screen')
          .call(
            [_str(screen.path), builder],
            {
              'name': _str(screen.name),
              if (screen.title case final title?) 'title': _str(title),
              if (screen.params.isNotEmpty)
                'params': literalMap({
                  for (final param in screen.params)
                    _str(param.name): _typeValue(param.type, screen.element),
                }),
              if (screen.extra case final extra?)
                'extra': _typeValue(extra, screen.element),
              if (screen.shell case final shell?)
                'shell': _type(shell.thisType, shell),
              if (screen.branch case final branch?) 'branch': _str(branch),
              if (screen.transition case final transition?)
                'transition': _nav('PageTransition').property(transition),
              if (screen.content case final content?) 'content': _str(content),
              if (!screen.link) 'link': literalFalse,
              if (screen.preAuthorize case final expression?)
                'attributes': literalConstMap({
                  _nav('RouteAttributes').property('preAuthorize'): _str(
                    expression,
                  ),
                }),
              'source': _str(screen.source),
            },
          );
    }
    // `BeanDefinition<ScreenRoutes>`: its type is the only one.
    return _spring('BeanDefinition').newInstance(
      [],
      {
        'name': _str('screenRoutes#$moduleName'),
        'source': _str('$_navigationUrl#ScreenRoutes'),
        'create': _closure(
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
        ..on = _type(element.thisType, element)
        ..fields.addAll([
          constant('pattern', _str(screen.path), '/// The path pattern.'),
          constant('routeName', _str(screen.name), "/// The route's name."),
          for (final MapEntry(key: variable, value: name) in variables.entries)
            constant(
              name,
              _nav('RouteVar').constInstance([_str(variable)], {}, [string]),
              '/// The path variable `$variable`.',
            ),
          for (final MapEntry(key: param, value: name) in params.entries)
            constant(
              name,
              _nav(
                'RouteParam',
              ).constInstance(
                [_str(param.name)],
                {},
                [
                  _type(param.type, element),
                ],
              ),
              '/// The query parameter `${param.name}`.',
            ),
          if (extra != null)
            constant(
              'extra',
              _nav('RouteExtra').constInstance([], {}, [_type(extra, element)]),
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
                      ..type = _nullable(_type(param.type, element)),
                  ),
                if (extra != null)
                  Parameter(
                    (p) => p
                      ..name = 'extra'
                      ..named = true
                      ..type = _nullable(_type(extra, element)),
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
                            _str(variable): refer(name),
                        }),
                      if (params.isNotEmpty)
                        'params': literalMap({
                          for (final MapEntry(key: param, value: name)
                              in params.entries)
                            _str(param.name): refer(name),
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
    for (final screen in _module.screens) {
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
  if (identifier.isEmpty || RegExp('^[0-9]').hasMatch(identifier)) {
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
