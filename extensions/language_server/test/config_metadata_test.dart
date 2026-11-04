// application.yml / .properties and theme YAML, against Spring metadata
// (lib/spring_gen/spring_metadata.json of the package and its
// dependencies): key and value completion, hovers, go to definition and
// diagnostics.
import 'dart:convert';
import 'dart:io';

import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

void main() {
  late EditorFixture fixture;

  setUp(() => fixture = EditorFixture.create());
  tearDown(() => fixture.dispose());

  List<String> labels(String path, String marker, String text) {
    final result = fixture.workspace.completion(path, at(text, marker));
    return [
      for (final item in result?.items ?? const <Completion>[]) item.label,
    ];
  }

  group('completion', () {
    test('nested YAML keys come from the metadata of the dependencies', () {
      const text = 'starter:\n  mail:\n    \n';
      final path = fixture.open('lib/resources/application.yml', text);
      expect(
        labels(path, '    |\n', text),
        unorderedEquals(['host', 'port', 'mode', 'enabled']),
      );
    });

    test('top-level keys offer the first segments, with a colon', () {
      const text = 'sta\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final result = fixture.workspace.completion(path, at(text, 'sta|'))!;
      final item = result.items.firstWhere((i) => i.label == 'starter');
      expect(item.insertText, startsWith('starter:'));
      expect(labels(path, 'sta|', text), contains('app'));
    });

    test('a dotted key in YAML and a .properties key', () {
      const text = 'starter.mail.\n';
      final path = fixture.open('lib/resources/application.yml', text);
      expect(labels(path, 'mail.|', text), contains('host'));
      const props = 'starter.mail.mo\n';
      final file = fixture.open('lib/resources/application.properties', props);
      expect(labels(file, 'mo|', props), contains('mode'));
    });

    test('values: enum hints, booleans and the profiles provider', () {
      const text =
          'starter:\n  mail:\n    mode: \n    enabled: \n'
          'spring:\n  profiles:\n    active: \n';
      final path = fixture.open('lib/resources/application.yml', text);
      expect(labels(path, 'mode: |', text), ['plain', 'tls']);
      expect(labels(path, 'enabled: |', text), ['true', 'false']);
      expect(labels(path, 'active: |', text), containsAll(['dev', 'prod']));
    });

    test(r'theme keys: sections, colors roles and $ references', () {
      const text =
          'spring:\n  flutter:\n    theme:\n      themes:\n'
          '        neon:\n          colors:\n            primary: \$\n'
          '            secondary: \$neon.\n'
          '            error: \$colors.pri\n          \n';
      final path = fixture.open('lib/resources/themes/neon.yml', text);
      expect(labels(path, '\$|\n', text), containsAll(['colors', 'tokens']));
      expect(labels(path, r'$neon.|', text), contains('cyan'));
      expect(
        labels(path, r'$colors.pri|', text),
        containsAll(['primary', 'primary-container']),
      );
      expect(
        labels(path, '          |\n', text),
        containsAll(['brightness', 'colors', 'components', 'extends']),
      );
    });

    test('a color object offers its parts', () {
      const text =
          'spring:\n  flutter:\n    theme:\n      colors:\n'
          '        primary:\n          \n';
      final path = fixture.open('lib/resources/application.yml', text);
      // `primary` is a color: its object parts are `color`, `alpha`, `mix`.
      final result = fixture.workspace.completion(
        path,
        at(text, '          |\n'),
      );
      expect(
        [for (final i in result?.items ?? const <Completion>[]) i.label],
        containsAll(['color', 'alpha', 'mix']),
      );
    });

    test('a placeholder completes property keys', () {
      const text = 'app:\n  title: \${starter.m}\n';
      final path = fixture.open('lib/resources/application.yml', text);
      expect(
        labels(path, 'starter.m|', text),
        containsAll(['starter.mail.host', 'starter.mail.mode']),
      );
    });
  });

  group('hover', () {
    test('a key shows description, type, default and source', () {
      const text = 'starter:\n  mail:\n    host: example.org\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final hover = fixture.workspace.hover(path, at(text, 'ho|st'))!;
      expect(hover, contains('starter.mail.host'));
      expect(hover, contains('The mail server.'));
      expect(hover, contains('Type: `String`'));
      expect(hover, contains('Default: `localhost`'));
      expect(hover, contains('package:starter/src/mail.dart'));
    });

    test('values show enum hints and range', () {
      const text = 'starter:\n  mail:\n    mode: tls\n    port: 25\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final mode = fixture.workspace.hover(path, at(text, 'mo|de'))!;
      expect(mode, contains('`tls`: Encrypted.'));
      final port = fixture.workspace.hover(path, at(text, 'po|rt'))!;
      expect(port, contains('Range: 1 to 65535'));
    });

    test('theme keys say what they set', () {
      const text =
          'spring:\n  flutter:\n    theme:\n      components:\n'
          '        app-bar:\n          background-color: red\n'
          '        filled-button:\n          background-color: red\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final hover = fixture.workspace.hover(path, at(text, 'background|'))!;
      expect(hover, contains('AppBarTheme.backgroundColor'));
      final states = fixture.workspace.hover(
        path,
        at(text, 'filled-button:\n          background|'),
      )!;
      expect(states, contains('a value per state'));
    });

    test(r'a $ reference shows where it is declared', () {
      const text =
          'spring:\n  flutter:\n    theme:\n      themes:\n'
          '        night:\n          seed-color: \$neon.cyan\n';
      final path = fixture.open('lib/resources/themes/night.yml', text);
      final hover = fixture.workspace.hover(path, at(text, r'$neon.cy|an'))!;
      expect(hover, contains('neon.cyan'));
      expect(hover, contains('#00E5FF'));
    });

    test('a placeholder lists its value per profile file', () {
      fixture
        ..open('lib/resources/application.properties', 'app.title=Shop\n')
        ..open('lib/resources/application-dev.properties', 'app.title=Dev\n');
      const text = 'greeting: "Hi \${app.title}"\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final hover = fixture.workspace.hover(path, at(text, 'app.ti|tle'))!;
      expect(hover, contains('`application`: `Shop`'));
      expect(hover, contains('`application-dev`: `Dev`'));
      expect(hover, contains('The title.'));
    });
  });

  group('definition', () {
    test('a theme reference leads into the dependency theme', () {
      const text =
          'spring:\n  flutter:\n    theme:\n      themes:\n'
          '        night:\n          seed-color: \$neon.cyan\n'
          '          secondary: \$colors.primary\n';
      final path = fixture.open('lib/resources/themes/night.yml', text);
      final cyan = fixture.workspace.definition(path, at(text, r'$neon.cy|an'));
      expect(cyan, hasLength(1));
      expect(
        cyan.single.path,
        endsWith('neon_ui/lib/resources/themes/neon.yml'),
      );
      expect(cyan.single.startLine, 9);
      final primary = fixture.workspace.definition(
        path,
        at(text, 'colors.pri|mary'),
      );
      expect(primary.single.path, endsWith('neon.yml'));
    });

    test('a placeholder leads to each profile file', () {
      fixture
        ..open('lib/resources/application.properties', 'app.title=Shop\n')
        ..open('lib/resources/application-dev.properties', 'app.title=Dev\n');
      const text = 'greeting: "Hi \${app.title}"\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final ranges = fixture.workspace.definition(path, at(text, 'app.ti|tle'));
      expect(
        [for (final r in ranges) r.path.split('/').last],
        ['application.properties', 'application-dev.properties'],
      );
    });
  });

  group('diagnostics', () {
    List<String> check(String name, String text) =>
        messages(fixture.workspace.problems(fixture.open(name, text)));

    test('an unknown key gets a did-you-mean', () {
      final found = check(
        'lib/resources/application.yml',
        'starter:\n  mail:\n    hosst: a\n    host: b\n',
      );
      expect(found, hasLength(1));
      expect(found.single, startsWith("2: Unknown property 'hosst'"));
      expect(found.single, contains("Did you mean 'host'?"));
    });

    test('wrong type, out of range and a value to avoid', () {
      final found = check(
        'lib/resources/application.yml',
        'starter:\n  mail:\n    port: abc\n    enabled: maybe\n'
            '    mode: ssl\n',
      );
      expect(found, [
        contains("Expected a whole number, got 'abc'"),
        contains("Expected true or false, got 'maybe'"),
        contains("'ssl' is not allowed here"),
      ]);
      expect(
        check(
          'lib/resources/application.yml',
          'starter:\n  mail:\n    port: 70000\n',
        ),
        [contains('out of range: 1 to 65535')],
      );
      final warn = fixture.workspace.problems(
        fixture.open(
          'lib/resources/application.yml',
          'starter:\n  mail:\n    port: 5060\n',
        ),
      );
      expect(warn.single.message, contains('browsers refuse it'));
      expect(warn.single.error, isFalse);
    });

    test('.properties files are checked the same way', () {
      final found = check(
        'lib/resources/application.properties',
        'starter.mail.portt=25\nstarter.mail.port=x\n',
      );
      expect(found, hasLength(2));
      expect(found.first, contains("Did you mean 'port'?"));
    });

    test('map and list keys are open below a pattern', () {
      expect(
        check(
          'lib/resources/application.yml',
          'logging:\n  level:\n    com.acme: debug\n'
              'starter:\n  tags:\n    - a\n',
        ),
        isEmpty,
      );
    });

    test('theme keys: unknown key, bad color, one-line forms are gone', () {
      final found = check(
        'lib/resources/application.yml',
        'spring:\n  flutter:\n    theme:\n      brigthness: dark\n'
            '      colors:\n        primary: nope\n'
            '        secondary: \$colors.primary alpha 12%\n'
            '        tertiary: on-surface\n',
      );
      expect(found[0], contains("Unknown theme key 'brigthness'"));
      expect(found[0], contains("Did you mean 'brightness'?"));
      expect(found[1], contains("'nope' is not a color"));
      expect(found[2], contains('one-line color forms are gone'));
      expect(found[3], contains('no bare role names'));
    });

    test('the color object form is valid, its parts are checked', () {
      expect(
        check(
          'lib/resources/application.yml',
          'spring:\n  flutter:\n    theme:\n      colors:\n'
              '        primary: "#F2E35B"\n'
              '        primary-container:\n          color: \$colors.primary\n'
              '          alpha: 12%\n'
              '          mix: { with: white, amount: 14% }\n',
        ).where((m) => !m.contains('Unknown')),
        isEmpty,
      );
      final bad = check(
        'lib/resources/application.yml',
        'spring:\n  flutter:\n    theme:\n      colors:\n'
            '        primary-container:\n          color: \$colors.primary\n'
            '          alpha: lots\n',
      );
      expect(bad, [contains('Expected a percentage')]);
      expect(
        check(
          'lib/resources/application.yml',
          'spring:\n  flutter:\n    theme:\n      colors:\n'
              '        primary-container:\n          color: red\n'
              '          alpha: 0.12\n',
        ),
        isEmpty,
      );
    });

    test(r'a broken $ reference names the closest declared one', () {
      final found = check(
        'lib/resources/themes/night.yml',
        'spring:\n  flutter:\n    theme:\n      themes:\n        night:\n'
            '          seed-color: \$neon.cyna\n'
            '          colors:\n            primary: \$colors.primary\n'
            '            secondary: \$neon.cyan\n',
      );
      expect(found, hasLength(1));
      expect(found.single, contains(r'Unknown reference $neon.cyna'));
      expect(found.single, contains(r'Did you mean $neon.cyan?'));
    });

    test(r'${key} without a default needs a defined key', () {
      final found = check(
        'lib/resources/application.yml',
        'a: \${app.title}\nb: \${nothing.here}\nc: \${nothing.here:x}\n'
            'd: \${starter.mail.host}\n',
      );
      expect(found, [contains("Cannot resolve property 'nothing.here'")]);
    });
  });

  group('missing metadata', () {
    test('one info says to run build_runner', () {
      fixture.dispose();
      fixture = EditorFixture.create(withAppMetadata: false);
      final path = fixture.open('lib/resources/application.yml', 'a: 1\n');
      final notes = fixture.workspace.metadataNotes(path);
      expect(notes, hasLength(1));
      expect(notes.single.info, isTrue);
      expect(notes.single.message, contains('run build_runner'));
    });

    test('a dependency without metadata: unknown keys are not reported', () {
      fixture.open(
        'pubspec.yaml',
        'name: app\ndependencies:\n  spring_core_dart: any\n'
            '  starter: any\n  neon_ui: any\n  old_lib: any\n',
      );
      fixture.workspace.refresh(force: true);
      final path = fixture.open(
        'lib/resources/application.yml',
        'old:\n  lib:\n    key: 1\nstarter:\n  mail:\n    hosst: a\n',
      );
      expect(fixture.workspace.problems(path), isEmpty);
      final notes = fixture.workspace.metadataNotes(path);
      expect(notes.single.message, contains('old_lib'));
    });

    test('without the theme metadata no theme key is reported', () {
      final file = File(
        '${fixture.root.path}/starter/lib/spring_gen/spring_metadata.json',
      );
      final json = jsonDecode(file.readAsStringSync()) as Map..remove('theme');
      file.writeAsStringSync(jsonEncode(json));
      fixture.workspace.refresh(force: true);
      final theme = fixture.open(
        'lib/resources/themes/t.yml',
        'spring:\n  flutter:\n    theme:\n      brigthness: dark\n',
      );
      expect(fixture.workspace.problems(theme), isEmpty);
    });

    test('no note when every package has its metadata', () {
      final path = fixture.open('lib/resources/application.yml', 'a: 1\n');
      expect(fixture.workspace.metadataNotes(path), isEmpty);
    });
  });
}
