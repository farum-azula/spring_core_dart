import 'package:spring_boot_starter_flutter_navigation/src/navigation.dart';
import 'package:spring_boot_starter_flutter_navigation/src/screen_routes.dart';
import 'package:spring_web_dart/spring_web_dart.dart' show MappingDescriptions;

/// The app's screens for `/actuator/mappings` (`screens`, our addition to
/// Spring's answer) and the editor: one entry per screen with its path,
/// shell and branch, the values it takes and the guard it has.
///
/// ```json
/// {"path": "/catalog/books/{isbn}", "name": "book-page",
///  "shell": "MainTabs", "branch": "/catalog",
///  "variables": ["isbn"], "params": {"page": "int"},
///  "extra": "BookSummary", "security": "isAuthenticated()"}
/// ```
final class ScreenMappings implements MappingDescriptions {
  /// The screens of [navigation].
  ScreenMappings(this.navigation);

  /// The navigation whose routes are described.
  final Navigation navigation;

  @override
  String get mappingsName => 'screens';

  @override
  List<Map<String, Object?>> describeMappings() {
    final table = navigation.table;
    return [
      for (final screen in table.screens)
        {
          'path': screen.pattern.pattern,
          'name': ?screen.name,
          'title': ?screen.title,
          if (table.placeOf(screen) case (final shell, final branch)) ...{
            'shell': _shellName(shell.key),
            if (branch >= 0) 'branch': shell.branches[branch],
          },
          if (_variables(screen) case final variables when variables.isNotEmpty)
            'variables': variables,
          if (screen.params.isNotEmpty)
            'params': {
              for (final MapEntry(:key, :value) in screen.params.entries)
                key: '$value',
            },
          if (screen.extra case final extra?) 'extra': '$extra',
          'content': ?screen.content,
          if (screen.attributes[RouteAttributes.preAuthorize]
              case final String security)
            'security': security,
          if (!screen.link) 'link': false,
          'source': ?screen.source,
        },
    ];
  }

  static List<String> _variables(ScreenRouteDefinition screen) => [
    for (final match in RegExp(
      r'\{\*?([A-Za-z_][A-Za-z0-9_]*)',
    ).allMatches(screen.pattern.pattern))
      match.group(1)!,
  ];

  static String _shellName(Object key) => '$key';
}
