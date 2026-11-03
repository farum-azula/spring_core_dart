import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dart_spring_language_server/src/workspace.dart';

/// A small pub setup in a temp directory, with Spring metadata:
///
/// - `app`: the package under test; its own metadata, `application.yml`,
///   `application-dev.properties` and Dart files are written by the test;
/// - `starter`: a dependency with properties, hints, beans and the real
///   theme keys of the Flutter starter;
/// - `neon_ui`: a dependency with a theme in `lib/resources`;
/// - `spring_core_dart`: the framework, with empty metadata;
/// - `old_lib`: a dependency on the framework without a metadata file.
final class EditorFixture {
  EditorFixture._(this.root, this.workspace);

  /// Builds the packages and a workspace over `app`.
  factory EditorFixture.create({bool withAppMetadata = true}) {
    final root = Directory.systemTemp.createTempSync('editor_fixture');
    void write(String path, String content) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    void metadata(String package, Map<String, Object?> json) => write(
      '$package/lib/spring_gen/spring_metadata.json',
      jsonEncode({'version': 1, 'package': package, ...json}),
    );

    write(
      'app/pubspec.yaml',
      'name: app\n'
          'dependencies:\n'
          '  spring_core_dart: any\n'
          '  starter: any\n'
          '  neon_ui: any\n',
    );
    for (final package in ['starter', 'neon_ui', 'old_lib']) {
      write(
        '$package/pubspec.yaml',
        'name: $package\ndependencies:\n  spring_core_dart: any\n',
      );
    }
    write('spring_core_dart/pubspec.yaml', 'name: spring_core_dart\n');
    metadata('spring_core_dart', {});
    final config = {
      'configVersion': 2,
      'packages': [
        for (final name in [
          'app',
          'starter',
          'neon_ui',
          'old_lib',
          'spring_core_dart',
        ])
          {
            'name': name,
            'rootUri': '../../$name',
            'packageUri': 'lib/',
          },
      ],
    };
    write('app/.dart_tool/package_config.json', jsonEncode(config));
    write(
      'app/pubspec.yaml',
      'name: app\n'
          'dependencies:\n'
          '  spring_core_dart: any\n'
          '  starter: any\n'
          '  neon_ui: any\n',
    );

    metadata('starter', {
      'properties': [
        {
          'name': 'starter.mail.host',
          'type': 'String',
          'description': 'The mail server.',
          'default': 'localhost',
          'source': 'package:starter/src/mail.dart',
          'line': 7,
          'class': 'MailProperties',
        },
        {
          'name': 'starter.mail.port',
          'type': 'int',
          'description': 'The mail port.',
          'default': 25,
        },
        {'name': 'starter.mail.mode', 'type': 'MailMode'},
        {'name': 'starter.mail.enabled', 'type': 'bool', 'default': true},
        {'name': 'starter.tags[*]', 'type': 'String'},
        {'name': 'logging.level.*', 'type': 'String'},
        {'name': 'spring.profiles.active', 'type': 'String'},
      ],
      'hints': [
        {
          'name': 'starter.mail.mode',
          'values': [
            {'value': 'plain', 'description': 'No encryption.'},
            {'value': 'tls', 'description': 'Encrypted.'},
          ],
        },
        {
          'name': 'starter.mail.port',
          'range': [1, 65535],
          'warn': [
            {
              'values': [5060, 5061],
              'message': 'browsers refuse it',
            },
          ],
        },
        {'name': 'spring.profiles.active', 'provider': 'profiles'},
      ],
      'beans': [
        {
          'name': 'mailer',
          'type': 'Mailer',
          'types': ['Mailer', 'Sender'],
          'scope': 'singleton',
          'primary': false,
          'qualifiers': <String>[],
          'profiles': <String>[],
          'conditions': <String>[],
          'source': 'package:starter/src/mailer.dart',
          'line': 12,
          'injects': <Object?>[],
          'members': [
            {'name': 'host', 'kind': 'getter', 'type': 'String'},
            {'name': 'sent', 'kind': 'getter', 'type': 'int'},
            {
              'name': 'send',
              'kind': 'method',
              'type': 'void',
              'parameters': ['String to'],
            },
          ],
        },
        for (final name in ['smsNotifier', 'pushNotifier'])
          {
            'name': name,
            'type': 'Notifier',
            'types': ['Notifier'],
            'scope': 'singleton',
            'primary': false,
            'qualifiers': <String>[],
            'profiles': name == 'smsNotifier' ? <String>[] : ['dev'],
            'conditions': <String>[],
            'source': 'package:starter/src/$name.dart',
            'line': 3,
            'injects': <Object?>[],
            'members': <Object?>[],
          },
      ],
      'profiles': ['dev'],
      // The real theme keys, as the Flutter starter publishes them.
      'theme': _realTheme(),
    });
    metadata('neon_ui', {});
    if (withAppMetadata) {
      metadata('app', {
        'properties': [
          {
            'name': 'app.title',
            'type': 'String',
            'description': 'The title.',
            'default': 'Shop',
          },
        ],
        'profiles': ['dev', 'prod'],
        'beans': <Object?>[],
      });
    }
    write(
      'neon_ui/lib/resources/themes/neon.yml',
      'spring:\n'
          '  flutter:\n'
          '    theme:\n'
          '      themes:\n'
          '        neon:\n'
          '          colors:\n'
          "            primary: '#F2E35B'\n"
          '          tokens:\n'
          '            neon:\n'
          "              cyan: '#00E5FF'\n",
    );

    final workspace = SpringWorkspace(['${root.path}/app'])
      ..refresh(force: true);
    return EditorFixture._(root, workspace);
  }

  /// The temp directory holding every package.
  final Directory root;

  /// A workspace over `app`.
  final SpringWorkspace workspace;

  /// The absolute path of [relative] inside the package `app`.
  String app(String relative) => '${root.path}/app/$relative';

  /// Writes [relative] of `app` as an unsaved document (an overlay) and
  /// returns its path.
  String open(String relative, String text) {
    final path = app(relative);
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
    workspace
      ..setOverlay(path, text)
      ..refresh(force: true);
    return path;
  }

  /// Removes the temp directory.
  void dispose() => root.deleteSync(recursive: true);
}

/// The offset of [marker] in [text]; `|` in [marker] is the cursor: the
/// result points there. Without `|`, the start of the marker.
int at(String text, String marker) {
  final bar = marker.indexOf('|');
  final clean = marker.replaceFirst('|', '');
  final index = text.indexOf(clean);
  if (index < 0) {
    throw ArgumentError('"$clean" is not in the text');
  }
  return index + (bar < 0 ? 0 : bar);
}

/// The messages of [problems] with their line, for compact expectations.
List<String> messages(List<Problem> problems) => [
  for (final p in problems) '${p.range.startLine}: ${p.message}',
];

// The `theme` section of the Flutter starter's own metadata.
Map<String, Object?> _realTheme() {
  // Found from the package's own place, not the working directory (some
  // tests change it).
  final lib = Isolate.resolvePackageUriSync(
    Uri.parse('package:dart_spring_language_server/'),
  )!.toFilePath();
  final file = File(
    '$lib/../../../spring_boot_starter_flutter/'
    'lib/spring_gen/spring_metadata.json',
  );
  final json = jsonDecode(file.readAsStringSync()) as Map;
  return (json['theme']! as Map).cast<String, Object?>();
}
