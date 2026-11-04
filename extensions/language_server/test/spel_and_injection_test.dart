// Beans from the metadata (a dependency's auto-configuration among them):
// SpEL #{@bean.member} completion, hovers, definition and errors, in Dart
// annotations and in config values; injection points; @Profile.
import 'package:dart_spring_language_server/src/config_editor.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

import 'support/editor_fixture.dart';

const _shop = '''
import 'package:spring_core_dart/spring_core_dart.dart';

abstract class Notifier {}
abstract class Printer {}

@Service()
class Checkout {
  Checkout(this._notifier, this._printer, this._mailer);

  final Notifier _notifier;
  final Printer _printer;
  final Mailer _mailer;

  @Value(r'#{@mailer.host}')
  late String host;

  @Value(r'#{@mailer.hots}')
  late String typo;

  @Value(r'#{@mailr.host}')
  late String noBean;

  @Value(r'#{@mailer.sent + 1}')
  late int count;
}

@Service()
class Picky {
  Picky(@Qualifier('smsNotifier') Notifier notifier);
}

@Service()
class Named {
  Named(Notifier smsNotifier);
}

@Service()
@Profile('dev')
class OnlyDev {}

@Service()
@Profile('stagng')
class Typo {}
''';

void main() {
  late EditorFixture fixture;
  late String shop;

  setUp(() {
    fixture = EditorFixture.create();
    shop = fixture.open('lib/shop.dart', _shop);
  });
  tearDown(() => fixture.dispose());

  group('beans of the dependencies', () {
    test('the metadata beans join the workspace beans', () {
      final names = [for (final b in fixture.workspace.beans) b.name];
      expect(names, containsAll(['checkout', 'mailer', 'smsNotifier']));
      final mailer = fixture.workspace.beansNamed('mailer').single;
      expect(mailer.fromMetadata, isTrue);
      expect(mailer.providedTypes, containsAll(['Mailer', 'Sender']));
    });
  });

  group('injection points', () {
    test('go to definition lists the candidates, also from dependencies', () {
      final ranges = fixture.workspace.definition(
        shop,
        at(_shop, 'final Notif|ier _notifier'),
      );
      expect(
        [for (final r in ranges) r.path.split('/').last],
        unorderedEquals(['smsNotifier.dart', 'pushNotifier.dart']),
      );
      expect(ranges.first.startLine, 2); // line 3 of the metadata, zero based
    });

    test('hover lists them with their profiles and where they are', () {
      final hover = fixture.workspace.hover(
        shop,
        at(_shop, 'final Notif|ier _notifier'),
      )!;
      expect(hover, contains("bean 'smsNotifier': Notifier"));
      expect(hover, contains('@Profile([dev])'));
      expect(hover, contains('package:starter/src/pushNotifier.dart'));
    });

    test('none is an error, several without @Primary a warning', () {
      final problems = fixture.workspace.problems(shop);
      final none = problems.singleWhere(
        (p) => p.message.startsWith('No bean of type Printer'),
      );
      expect(none.error, isTrue);
      expect(none.message, contains('all profiles considered: dev, prod'));
      final several = problems.singleWhere(
        (p) => p.message.startsWith('Several beans of type Notifier'),
      );
      expect(several.error, isFalse);
      expect(several.message, contains('pushNotifier (profile dev)'));
      expect(several.message, contains('@Qualifier'));
      expect(several.message, contains('all profiles considered'));
      // a qualifier, a parameter named like a bean, a bean of a dependency
      expect(problems.where((p) => p.message.contains('Mailer')), isEmpty);
      expect(
        problems.where(
          (p) => p.range.startLine == 31 || p.range.startLine == 36,
        ),
        isEmpty,
      );
    });

    test('an unknown dependency bean is only a warning without metadata', () {
      final root = fixture.root.path;
      fixture
        ..open('../old_lib/lib/x.dart', '')
        ..open(
          'pubspec.yaml',
          'name: app\ndependencies:\n'
              '  spring_core_dart: any\n  starter: any\n  neon_ui: any\n'
              '  old_lib: any\n',
        );
      fixture.workspace.refresh(force: true);
      final problems = fixture.workspace.problems(shop);
      final none = problems.singleWhere(
        (p) => p.message.startsWith('No bean of type Printer'),
      );
      expect(none.error, isFalse);
      expect(none.message, contains('without Spring metadata'));
      final notes = fixture.workspace.metadataNotes(shop);
      expect(notes.single.message, contains('old_lib'));
      expect(root, isNotEmpty);
    });
  });

  group('profile expressions', () {
    test('are evaluated against a set of active profiles', () {
      expect(profilesActive([], {}), isTrue);
      expect(profilesActive(['dev'], {'dev'}), isTrue);
      expect(profilesActive(['dev'], {'prod'}), isFalse);
      expect(profilesActive(['!web'], {}), isTrue);
      expect(profilesActive(['sso & !web'], {'sso'}), isTrue);
      expect(profilesActive(['sso & !web'], {'sso', 'web'}), isFalse);
      expect(profilesActive(['a | (b & c)'], {'b', 'c'}), isTrue);
      expect(profilesActive(['a | (b & c)'], {'b'}), isFalse);
      expect(profilesActive(['a', 'b'], {'b'}), isTrue);
    });
  });

  group('@Profile', () {
    test('an unknown profile is a warning, a known one is not', () {
      final found = messages(fixture.workspace.problems(shop))
          .where((m) => m.contains('Unknown profile'))
          .toList();
      expect(found, hasLength(1));
      expect(found.single, contains("Unknown profile 'stagng'"));
    });

    test('profile names complete from the metadata and the files', () {
      fixture.open('lib/resources/application-qa.properties', 'a=1\n');
      const text = "@Profile('')\nclass A {}\n";
      final path = fixture.open('lib/a.dart', text);
      final result = fixture.workspace.completion(path, at(text, "'|'"))!;
      expect(
        [for (final i in result.items) i.label],
        containsAll(['dev', 'prod', 'qa']),
      );
    });
  });

  group('SpEL', () {
    test('completion of beans after @ and of members after a dot', () {
      const text = """
@Value(r'#{@}')
late String a;
@Value(r'#{@mailer.}')
late String b;
@Value(r'#{@mailer.sent.}')
late String c;
""";
      final path = fixture.open('lib/c.dart', text);
      List<String> labels(String marker) => [
        for (final i
            in fixture.workspace.completion(path, at(text, marker))?.items ??
                const <Completion>[])
          i.label,
      ];
      expect(labels('@|}'), containsAll(['mailer', 'smsNotifier']));
      expect(labels('@mailer.|}'), containsAll(['host', 'sent', 'send']));
      expect(labels('@mailer.sent.|}'), isEmpty);
    });

    test('completion in a config value', () {
      const text = 'a: "#{@mailer.}"\n';
      final path = fixture.open('lib/resources/application.yml', text);
      final result = fixture.workspace.completion(path, at(text, 'mailer.|'))!;
      expect([for (final i in result.items) i.label], contains('host'));
      // The replaced span is just the typed member name (nothing here).
      expect(result.replace.startColumn, result.replace.endColumn);
    });

    test('hover shows the bean and the type of a member', () {
      final bean = fixture.workspace.hover(shop, at(_shop, '@mai|ler.host'))!;
      expect(bean, contains("bean 'mailer': Mailer"));
      final member = fixture.workspace.hover(shop, at(_shop, 'mailer.ho|st'))!;
      expect(member, contains('String host (getter)'));
      final sent = fixture.workspace.hover(shop, at(_shop, 'mailer.se|nt +'))!;
      expect(sent, contains('int sent (getter)'));
    });

    test('go to definition on a bean leads to its declaration', () {
      final ranges = fixture.workspace.definition(
        shop,
        at(_shop, '@mai|ler.host'),
      );
      expect(ranges.single.path, endsWith('starter/lib/src/mailer.dart'));
      expect(ranges.single.startLine, 11);
    });

    test('an unknown bean or member is an error, with did-you-mean', () {
      final found = messages(fixture.workspace.problems(shop));
      expect(
        found,
        contains(contains("Unknown member 'hots' of bean 'mailer'")),
      );
      expect(found, contains(contains("Did you mean 'host'?")));
      expect(found, contains(contains("Unknown bean 'mailr'")));
      expect(found, contains(contains("Did you mean '@mailer'?")));
      expect(
        found.where((m) => m.contains('Unknown') && m.contains('sent')),
        isEmpty,
      );
    });

    test('config values are checked the same way', () {
      final found = messages(
        fixture.workspace.problems(
          fixture.open(
            'lib/resources/application.yml',
            'a: "#{@mailer.hots}"\nb: "#{@mailer.host}"\nc: "#{@nobody.x}"\n',
          ),
        ),
      );
      expect(found, hasLength(2));
      expect(found[0], startsWith("0: Unknown member 'hots'"));
      expect(found[1], startsWith("2: Unknown bean 'nobody'"));
    });

    test('syntax errors are still reported by the parser', () {
      final found = messages(
        fixture.workspace.problems(
          fixture.open('lib/resources/application.yml', 'a: "#{1 +}"\n'),
        ),
      );
      expect(found.single, contains('SpEL'));
    });
  });

  group('Dart strings', () {
    test('a placeholder completes property keys', () {
      const text = "@Value(r'\${star}')\nlate String a;\n";
      final path = fixture.open('lib/d.dart', text);
      final result = fixture.workspace.completion(path, at(text, 'star|'))!;
      expect(
        [for (final i in result.items) i.label],
        contains('starter.mail.host'),
      );
    });
  });
}
