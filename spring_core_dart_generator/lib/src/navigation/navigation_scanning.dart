// Scanning for spring_boot_starter_flutter_navigation: `@ScreenRoute`
// widgets (the screens of the app) and `@RouteShell` widgets (the shells
// with a stack per branch). Matched by URL, so the generator does not
// depend on that package.
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';

/// Recognises `@ScreenRoute` of `spring_boot_starter_flutter_navigation`.
const screenRouteChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter_navigation/src/annotations.dart#ScreenRoute',
);

/// Recognises `@RouteShell` of `spring_boot_starter_flutter_navigation`.
const routeShellChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter_navigation/src/annotations.dart#RouteShell',
);

/// Recognises `@RouteInfo` of `spring_boot_starter_flutter_navigation`.
const routeInfoChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter_navigation/src/annotations.dart#RouteInfo',
);

/// Recognises `@PreAuthorize` of `spring_security_core`: on a screen, the
/// expression the user must satisfy to open it.
const preAuthorizeChecker = TypeChecker.fromUrl(
  'package:spring_security_core/src/method/annotations.dart#PreAuthorize',
);

/// Recognises `ShellState`, the parameter of a shell's constructor.
const shellStateChecker = TypeChecker.fromUrl(
  'package:spring_boot_starter_flutter_navigation/src/shell_state.dart#ShellState',
);

/// Recognises Flutter's `Widget`.
const widgetChecker = TypeChecker.fromUrl(
  'package:flutter/src/widgets/framework.dart#Widget',
);

/// A query parameter a screen declares (`params: {'page': int}`).
class RouteParamModel {
  /// The parameter [name] of [type].
  RouteParamModel(this.name, this.type);

  /// The name in the address (`page`, `page-size`).
  final String name;

  /// The type the value converts to.
  final DartType type;
}

/// A `@ScreenRoute` widget: a screen of the app at [path].
///
/// ```dart
/// // Input:
/// @ScreenRoute('/catalog/books/{isbn}', params: {'page': int})
/// class BookPage extends StatelessWidget { ... }
///
/// // Output: the screen in the module's ScreenRoutes bean
/// //   .screen('/catalog/books/{isbn}', (r) => const BookPage(),
/// //       name: 'book-page', params: {'page': int}, source: ...)
/// // and its constants:
/// extension BookPageRoute on BookPage {
///   static const pattern = '/catalog/books/{isbn}';
///   static const isbn = RouteVar<String>('isbn');
///   static const page = RouteParam<int>('page');
///   static RouteLocation to({required String isbn, int? page}) => ...;
/// }
/// ```
class ScreenRouteModel {
  /// The screen [element] at [path].
  ScreenRouteModel({
    required this.element,
    required this.path,
    required this.name,
    required this.constConstructor,
    this.title,
    this.params = const [],
    this.extra,
    this.shell,
    this.branch,
    this.transition,
    this.content,
    this.notFound = false,
    this.preAuthorize,
    this.description,
    this.image,
    this.index = true,
    this.link = true,
    this.paths = const [],
  });

  /// The widget class.
  final ClassElement element;

  /// The path pattern, as written; empty for the not-found screen.
  final String path;

  /// The route's name.
  final String name;

  /// Whether the widget's constructor is const.
  final bool constConstructor;

  /// The title, or `null`.
  final String? title;

  /// The declared query parameters.
  final List<RouteParamModel> params;

  /// The type of the extra object, or `null`.
  final DartType? extra;

  /// The shell named with `shell:`, or `null`.
  final ClassElement? shell;

  /// The branch named with `branch:` (its path), or `null`.
  final String? branch;

  /// The name of the `PageTransition` chosen with `transition:`, or `null`
  /// for the theme's (the default).
  final String? transition;

  /// The resources the screen shows, or `null`.
  final String? content;

  /// Whether this is the screen for unknown addresses.
  final bool notFound;

  /// The expression of `@PreAuthorize` on the screen, or `null`.
  final String? preAuthorize;

  /// `@RouteInfo`'s description, or `null`.
  final String? description;

  /// `@RouteInfo`'s image, or `null`.
  final String? image;

  /// `@RouteInfo`'s index.
  final bool index;

  /// `@RouteInfo`'s link.
  final bool link;

  /// `@RouteInfo`'s paths: addresses of a screen with path variables.
  final List<String> paths;

  /// The screen for the editor and the site's build, in
  /// `spring_metadata.json`.
  Map<String, Object?> toMetadata() => {
    'path': path,
    'name': name,
    'class': element.name,
    'source': source,
    if (title != null) 'title': title,
    if (params.isNotEmpty)
      'params': {
        for (final param in params) param.name: param.type.getDisplayString(),
      },
    if (extra != null) 'extra': extra!.getDisplayString(),
    if (shell != null) 'shell': shell!.name,
    if (branch != null) 'branch': branch,
    if (content != null) 'content': content,
    if (notFound) 'notFound': true,
    if (preAuthorize != null) 'preAuthorize': preAuthorize,
    if (description != null) 'description': description,
    if (image != null) 'image': image,
    if (!index) 'index': false,
    if (!link) 'link': false,
    if (paths.isNotEmpty) 'paths': paths,
  };

  /// The path variables, in order: `isbn` of `/books/{isbn}`, `path` of
  /// `/docs/{*path}`.
  List<String> get variables => pathVariables(path);

  /// The key of the screen, `package:app/book_page.dart#BookPage`.
  String get source => '${element.library.uri}#${element.name ?? ''}';
}

/// A `@RouteShell` widget with its [branches].
class RouteShellModel {
  /// The shell [element] with [branches].
  RouteShellModel(this.element, this.branches);

  /// The widget class.
  final ClassElement element;

  /// The paths that start the branches.
  final List<String> branches;

  /// The key of the shell, `package:app/main_tabs.dart#MainTabs`.
  String get source => '${element.library.uri}#${element.name ?? ''}';

  /// The shell for the editor, in `spring_metadata.json`.
  Map<String, Object?> toMetadata() => {
    'class': element.name,
    'source': source,
    'branches': branches,
  };
}

final _variable = RegExp(r'\{\*?([A-Za-z_][A-Za-z0-9_]*)(?::[^}]*)?\}');

/// The variables of the path pattern [path], in order.
List<String> pathVariables(String path) => [
  for (final match in _variable.allMatches(path)) match.group(1)!,
];

/// The default name of a route for the class [className]: `BookPage` is
/// `book-page`.
String routeName(String className) => className
    .replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (m) => '${m.group(1)}-${m.group(2)}',
    )
    .toLowerCase();

/// Adds a [ScreenRouteModel] to `module.screens` for an [element] with
/// `@ScreenRoute`, and a [RouteShellModel] to `module.shells` for one with
/// `@RouteShell`.
///
/// Throws `InvalidGenerationSource` when the class is no widget, when a
/// screen has no constructor without required parameters (the router
/// makes it), when a shell's constructor does not take its `ShellState`
/// alone, when a path is malformed, or when a parameter is declared twice
/// or named like a path variable.
void scanNavigation(ClassElement element, ModuleModel module) {
  final screen = screenRouteChecker.firstAnnotationOf(element);
  final shell = routeShellChecker.firstAnnotationOf(element);
  if (screen == null && shell == null) {
    return;
  }
  final className = element.name ?? '?';
  if (!widgetChecker.isAssignableFrom(element)) {
    throw InvalidGenerationSource(
      '$className has @${screen != null ? 'ScreenRoute' : 'RouteShell'} '
      'but is not a widget.',
      element: element,
    );
  }
  if (screen != null && shell != null) {
    throw InvalidGenerationSource(
      '$className cannot be a screen (@ScreenRoute) and a shell '
      '(@RouteShell) at once.',
      element: element,
    );
  }
  if (shell != null) {
    module.shells.add(_shell(element, ConstantReader(shell)));
    return;
  }
  module.screens.add(_screen(element, ConstantReader(screen)));
}

RouteShellModel _shell(ClassElement element, ConstantReader annotation) {
  final className = element.name ?? '?';
  final constructor = element.unnamedConstructor;
  final parameters = constructor?.formalParameters ?? const [];
  final required = [
    for (final p in parameters)
      if (p.isRequired) p,
  ];
  if (constructor == null ||
      required.length != 1 ||
      !required.single.isPositional ||
      !shellStateChecker.isAssignableFromType(required.single.type)) {
    throw InvalidGenerationSource(
      'The shell $className needs an unnamed constructor whose only required '
      'parameter is its ShellState: $className(this.shell, {super.key}).',
      element: element,
    );
  }
  final branches = [
    for (final value in annotation.read('branches').listValue)
      value.toStringValue() ?? '',
  ];
  if (branches.isEmpty) {
    throw InvalidGenerationSource(
      'The shell $className declares no branches.',
      element: element,
    );
  }
  for (final branch in branches) {
    if (!branch.startsWith('/') || branch.contains('{')) {
      throw InvalidGenerationSource(
        'The branch "$branch" of the shell $className must be a path '
        'starting with / and without variables.',
        element: element,
      );
    }
  }
  return RouteShellModel(element, branches);
}

ScreenRouteModel _screen(ClassElement element, ConstantReader annotation) {
  final className = element.name ?? '?';
  final constructor = element.unnamedConstructor;
  if (constructor == null ||
      constructor.formalParameters.any((p) => p.isRequired)) {
    throw InvalidGenerationSource(
      'The screen $className needs an unnamed constructor without required '
      'parameters: the router makes it. It reads its values from '
      'context.route.',
      element: element,
    );
  }
  final notFound = annotation.read('notFound').boolValue;
  final path = annotation.read('path').stringValue;
  if (!notFound) {
    _checkPath(path, element);
  }
  final variables = pathVariables(path);
  final params = <RouteParamModel>[];
  final declared = annotation.read('params');
  if (!declared.isNull) {
    for (final MapEntry(:key, :value) in declared.mapValue.entries) {
      final name = key?.toStringValue() ?? '';
      final type = value?.toTypeValue();
      if (name.isEmpty || type == null) {
        throw InvalidGenerationSource(
          'The screen $className declares a parameter without a name or type.',
          element: element,
        );
      }
      if (variables.contains(name)) {
        throw InvalidGenerationSource(
          'The screen $className declares the parameter "$name", which is '
          'also a path variable of $path.',
          element: element,
        );
      }
      params.add(RouteParamModel(name, type));
    }
  }
  final shellType = annotation.peek('shell')?.typeValue;
  final shellElement = shellType?.element;
  final info = routeInfoChecker.firstAnnotationOf(element);
  final infoReader = info == null ? null : ConstantReader(info);
  return ScreenRouteModel(
    element: element,
    path: path,
    name: annotation.peek('name')?.stringValue ?? routeName(className),
    constConstructor: constructor.isConst,
    title: annotation.peek('title')?.stringValue,
    params: params,
    extra: annotation.peek('extra')?.typeValue,
    shell: shellElement is ClassElement ? shellElement : null,
    branch: annotation.peek('branch')?.stringValue,
    transition: switch (annotation
        .peek('transition')
        ?.objectValue
        .getField('_name')
        ?.toStringValue()) {
      null || 'theme' => null,
      final name => name,
    },
    content: annotation.peek('content')?.stringValue,
    notFound: notFound,
    preAuthorize: switch (preAuthorizeChecker.firstAnnotationOf(element)) {
      final annotation? => ConstantReader(annotation).read('value').stringValue,
      null => null,
    },
    description: infoReader?.peek('description')?.stringValue,
    image: infoReader?.peek('image')?.stringValue,
    index: infoReader?.peek('index')?.boolValue ?? true,
    link: infoReader?.peek('link')?.boolValue ?? true,
    paths: [
      for (final DartObject value
          in infoReader?.peek('paths')?.listValue ?? const <DartObject>[])
        ?value.toStringValue(),
    ],
  );
}

// The checks the build can make of a pattern (the start parses it fully):
// a leading `/`, balanced braces, a `{*rest}` only at the end, no variable
// twice.
void _checkPath(String path, ClassElement element) {
  final className = element.name ?? '?';
  void fail(String why) => throw InvalidGenerationSource(
    'The path "$path" of the screen $className $why.',
    element: element,
  );
  if (!path.startsWith('/')) {
    fail('must start with /');
  }
  var depth = 0;
  for (final char in path.split('')) {
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
    }
    if (depth < 0 || depth > 1) {
      fail('has unbalanced braces');
    }
  }
  if (depth != 0) {
    fail('has unbalanced braces');
  }
  final rest = RegExp(r'\{\*').firstMatch(path);
  if (rest != null && !RegExp(r'\{\*[^}]*\}$').hasMatch(path)) {
    fail('has {*name} before its end');
  }
  final variables = pathVariables(path);
  if (variables.toSet().length != variables.length) {
    fail('uses a variable twice');
  }
}
