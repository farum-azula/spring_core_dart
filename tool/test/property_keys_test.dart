// Every property key the code of a package reads with a literal name
// (`environment.getProperty('x.y')`, `@Value('${x.y}')`,
// `@ConditionalOnProperty('x.y')`, a `'spring.…'` constant) is in that
// package's lib/spring_gen/spring_metadata.json, so the editor knows it.
//
// Every key must be bound by a `@ConfigurationProperties` class of the
// package or of a package it depends on (documented there with `///`, an
// enum, a default). A key only named by `@Value` / `@ConditionalOnProperty`
// is in the metadata without a description, so it does not count: move it
// onto a `@ConfigurationProperties` class.
//
// A key the code builds at run time (`'$prefix.url'`) is not a literal and
// is not checked. A literal that is not a property (a logger name, a
// renamed prefix, a session key) or a truly dynamic read goes in
// [_notProperties] with the reason.
//
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Literals that look like keys but are not properties, by
/// "package:key", with the reason. (Names in capitals are environment
/// variables and are skipped by the rules below; a literal on a line with
/// `Log` in it is a logger name.)
const _notProperties = <String, String>{
  'spring_boot_starter_edge:spring.supabase.anon-key':
      "the Supabase starter's property, which the starter reads in a "
      'Supabase Edge Function without depending on that starter',
  'spring_boot_starter_supabase:spring.security.oauth2.resourceserver.jwt':
      "the prefix of the security starter's properties, whose defaults the "
      'starter sets without depending on it',
  'spring_boot_dart:spring.web.server': 'a logger name (debug loggers)',
  'spring_boot_dart:spring.web': 'a logger group (logging.level.web)',
  'spring_boot_dart:spring.websocket': 'a logger group (logging.level.web)',
  'spring_boot_dart:logging.level':
      'the scalar logging.level is the root '
      'level; logging.level.* is described',
  'spring_boot_dart:spring.cloud.openfeign':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_boot_dart:spring.feign': 'a renamed prefix (renamed_properties.dart)',
  'spring_boot_dart:spring.jackson':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_boot_dart:spring.json': 'the prefix of the JSON settings',
  'spring_boot_dart:spring.servlet.multipart':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_boot_dart:spring.web.multipart':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_boot_dart:server.servlet':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_boot_dart:spring.flyway':
      'a renamed prefix (renamed_properties.dart)',
  'spring_boot_dart:spring.sql.migration':
      'a renamed prefix '
      '(renamed_properties.dart)',
  'spring_core_dart:spring.profiles': 'the pre-2.4 key, rejected on purpose',
  'spring_boot_starter_data:spring.jdbc.sqlite': 'a logger name',
  'spring_boot_starter_web:spring.web.session': 'a request attribute name',
  'spring_boot_actuator:spring.boot.actuate.endpoint.target':
      'a request attribute name',
  'spring_boot_starter_web:server.ports': 'the name of a property source',
  'spring_core_dart:spring.beans.instantiate':
      'a startup step name (ApplicationStartup)',
  'spring_boot_starter_flutter:spring.beans.instantiate':
      'a startup step name (ApplicationStartup)',
  'spring_boot_starter_flutter:spring.event':
      'a startup step name (ApplicationStartup)',
  'spring_boot_dart:spring.boot.application.starting':
      'a startup step name (ApplicationStartup)',
  'spring_boot_dart:spring.boot.application.environment-prepared':
      'a startup step name (ApplicationStartup)',
  'spring_boot_dart:spring.boot.application.context':
      'a startup step name (ApplicationStartup)',
  'spring_boot_starter_flutter_security:'
          'spring.security.oauth2.authorization-request':
      'a session storage key',
};

final String _root =
    Directory.current.path.endsWith('tool/test') ||
        Directory.current.path.endsWith('tool')
    ? Directory.current.parent.path
    : Directory.current.path;

// Calls of the environment and the binder with a literal first argument.
final _reads = RegExp(
  r'''\b(?:getProperty|getRequiredProperty|containsProperty|getPropertyOrNull|getList|getBool|getInt|getString)\s*(?:<[^>()]*>)?\(\s*(?:name:\s*)?r?(['"])([^'"$]+)\1''',
);

// Annotation conditions with a literal name.
final _conditions = RegExp(
  r'''ConditionalOn(?:Boolean)?Property\(\s*(?:name:\s*)?r?(['"])([^'"$]+)\1(?:[^)]*?prefix:\s*(['"])([^'"$]*)\3)?''',
);

// A whole-string constant such as 'spring.cache.type'.
final _constants = RegExp(
  r'''(['"])((?:spring|server|logging|management)\.[a-z0-9\-]+(?:\.[a-z0-9\-]+)*\.?)\1''',
);

final _placeholder = RegExp(r'\$\{([A-Za-z][A-Za-z0-9_.\-]*)(?::[^}]*)?\}');

void main() {
  final packages = [
    for (final entity in Directory(_root).listSync())
      if (entity is Directory &&
          File('${entity.path}/lib/spring_gen/spring_metadata.json')
              .existsSync())
        entity,
  ]..sort((a, b) => a.path.compareTo(b.path));

  test('there are packages to check', () {
    expect(packages.length, greaterThan(10));
  });

  for (final package in packages) {
    final name = package.path.split('/').last;
    test('$name: every literal property key is in its metadata', () {
      // The package's keys and those of the workspace packages it
      // depends on (spring.profiles.active belongs to the core, say).
      final names = [
        for (final dependency in _closure(name))
          ..._propertyNames(
            jsonDecode(
              File(
                '$_root/$dependency/lib/spring_gen/spring_metadata.json',
              ).readAsStringSync(),
            ) as Map<String, Object?>,
          ),
      ];
      final missing = <String>[];
      for (final MapEntry(:key, :value) in _literalKeys(package).entries) {
        if (_notProperties.containsKey('$name:$key') || _covered(key, names)) {
          continue;
        }
        missing.add('$key  ($value)');
      }
      if (missing.isNotEmpty) {
        fail(
          'Not bound by a @ConfigurationProperties class of $name or its '
          'dependencies. Add them to one (with /// docs):\n'
          '${missing.join('\n')}',
        );
      }
    });
  }
}

// The names of a metadata file, with the theme keys written in full. A
// property without a description is one that code only reads (`@Value`,
// `@ConditionalOnProperty`): a bound property has its `///`.
List<String> _propertyNames(Map<String, Object?> metadata) => [
  for (final p in metadata['properties']! as List)
    if (p case {'description': != null, 'name': final String name}) ...[
      name,
      // A map property holds any key below it.
      if (p['type'] case final String type when type.startsWith('Map<'))
        '$name.*',
    ],
  if (metadata['theme'] case final Map<String, Object?> theme)
    for (final p in theme['properties']! as List)
      'spring.flutter.theme.${(p! as Map<String, Object?>)['name']}',
];

// [name] and the workspace packages it depends on, directly or not, that
// have a metadata file.
Set<String> _closure(String name) {
  final result = <String>{};
  void visit(String package) {
    if (!result.add(package)) {
      return;
    }
    final pubspec = File('$_root/$package/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return;
    }
    final text = pubspec.readAsStringSync();
    final end = text.indexOf('\ndev_dependencies:');
    final dependencies = end < 0 ? text : text.substring(0, end);
    for (final m in RegExp(
      r'^  (spring_\w+):',
      multiLine: true,
    ).allMatches(dependencies)) {
      if (File(
        '$_root/${m[1]}/lib/spring_gen/spring_metadata.json',
      ).existsSync()) {
        visit(m[1]!);
      }
    }
  }

  visit(name);
  return result;
}

// A key is known when a property has that name (`*` and `[*]` match one
// segment), or when the key is a prefix of properties (a whole group read
// at once, or a prefix constant that ends with a dot).
bool _covered(String key, List<String> names) {
  final prefix = key.endsWith('.') ? key : '$key.';
  for (final name in names) {
    if (name == key || name.startsWith(prefix) || name.startsWith('$key[')) {
      return true;
    }
    if (name.contains('*')) {
      final escaped = RegExp.escape(name)
          .replaceAll(r'\[\*\]', r'\[\d+\]')
          .replaceAll(r'\*', '[^.]+');
      final pattern = RegExp('^$escaped\$');
      if (pattern.hasMatch(key)) {
        return true;
      }
    }
  }
  return false;
}

// The literal keys in lib/ of [package], each with "file:line".
Map<String, String> _literalKeys(Directory package) {
  final found = <String, String>{};
  final lib = Directory('${package.path}/lib');
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    final path = file.path;
    if (!path.endsWith('.dart') ||
        path.endsWith('.spring.dart') ||
        path.endsWith('.g.dart') ||
        path.contains('/spring_gen/')) {
      continue;
    }
    final shown = path.substring(package.path.length + 1);
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // A `'name'.toJS` is the name of a JavaScript property (`window`
      // reads in the web hand-off), not a configuration property.
      if (line.trimLeft().startsWith('//') || line.contains('.toJS')) {
        continue;
      }
      void add(String key) {
        // NAMES_IN_CAPITALS are environment variables, not properties.
        if (key == key.toUpperCase() && !key.contains('.')) {
          return;
        }
        found.putIfAbsent(key, () => '$shown:${i + 1}');
      }

      for (final m in _reads.allMatches(line)) {
        add(m[2]!);
      }
      for (final m in _conditions.allMatches(line)) {
        final prefix = m[4] ?? '';
        add(
          prefix.isEmpty
              ? m[2]!
              : '${prefix.endsWith('.') ? prefix : '$prefix.'}${m[2]}',
        );
      }
      if (line.contains('@Value(')) {
        for (final m in _placeholder.allMatches(line)) {
          add(m[1]!);
        }
      }
      // Logger names look like keys ('spring.jdbc.sqlite').
      if (!RegExp('[Ll]og').hasMatch(line)) {
        for (final m in _constants.allMatches(line)) {
          add(m[2]!);
        }
      }
    }
  }
  return found;
}
