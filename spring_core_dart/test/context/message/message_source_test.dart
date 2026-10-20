import 'dart:typed_data';
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

void main() {
  group('Locales', () {
    test('normalize and candidates', () {
      expect(Locales.normalize('ru-ru'), 'ru_RU');
      expect(Locales.normalize('EN'), 'en');
      expect(
        Locales.normalize('sr_latn_RS'.replaceAll('latn', 'Latn')),
        'sr_LATN_RS',
      );
      expect(Locales.normalize(null), '');
      expect(Locales.normalize(' '), '');
      expect(Locales.candidates('ru_RU'), ['ru_RU', 'ru']);
      expect(Locales.candidates(''), isEmpty);
    });
  });

  group('StaticMessageSource', () {
    late StaticMessageSource source;
    setUp(() {
      source = StaticMessageSource()
        ..addMessages({'greeting': 'Hello {0}', 'plain': "It's raw"}, '')
        ..addMessage('greeting', 'ru', 'Привет {0}')
        ..addMessage('greeting', 'ru_UA', 'Вітаю {0}')
        ..addMessage('only.de', 'de', 'Hallo');
    });

    test('locale fallback chain', () {
      expect(source.getMessage('greeting', args: ['Ada']), 'Hello Ada');
      expect(
        source.getMessage('greeting', args: ['Ada'], locale: 'ru-RU'),
        'Привет Ada',
      );
      expect(
        source.getMessage('greeting', args: ['Ada'], locale: 'ru_UA'),
        'Вітаю Ada',
      );
      expect(
        source.getMessage('greeting', args: ['Ada'], locale: 'fr'),
        'Hello Ada',
      );
    });

    test('default locale fallback', () {
      source.defaultLocale = 'de';
      expect(source.getMessage('only.de', locale: 'fr'), 'Hallo');
      source.fallbackToDefaultLocale = false;
      expect(
        () => source.getMessage('only.de', locale: 'fr'),
        throwsA(isA<NoSuchMessageException>()),
      );
      expect(source.localeChain('fr'), ['fr', '']);
    });

    test(
      'no arguments: message returned as-is unless alwaysUseMessageFormat',
      () {
        expect(source.getMessage('plain'), "It's raw");
        source.addMessage('quoted', '', "It''s formatted");
        expect(source.getMessage('quoted'), "It''s formatted");
        source.alwaysUseMessageFormat = true;
        expect(source.getMessage('quoted'), "It's formatted");
      },
    );

    test('defaults, code as default, common messages, errors', () {
      expect(
        source.getMessage('missing', defaultMessage: 'Default {0}', args: [1]),
        'Default 1',
      );
      expect(
        () => source.getMessage('missing', locale: 'ru'),
        throwsA(
          isA<NoSuchMessageException>().having(
            (e) => e.toString(),
            'text',
            allOf(contains("'missing'"), contains("'ru'")),
          ),
        ),
      );
      expect(NoSuchMessageException('x').toString(), isNot(contains('locale')));
      source.commonMessages = {'common': 'Common {0}'};
      expect(source.getMessage('common', args: ['x']), 'Common x');
      source.useCodeAsDefaultMessage = true;
      expect(source.getMessage('missing'), 'missing');
      expect(source.toString(), contains('StaticMessageSource'));
    });

    test('resolvables, nested resolvable arguments', () {
      source.addMessage('field.name', '', 'Name');
      source.addMessage('required', '', '{0} is required');
      final resolvable = DefaultMessageSourceResolvable(
        ['required.user.name', 'required'],
        arguments: [DefaultMessageSourceResolvable.code('field.name')],
      );
      expect(source.getMessageFromResolvable(resolvable), 'Name is required');
      expect(resolvable.toString(), contains('required.user.name'));
      expect(
        source.getMessageFromResolvable(
          const DefaultMessageSourceResolvable(
            ['nope'],
            defaultMessage: 'dflt {0}',
            arguments: ['x'],
          ),
        ),
        'dflt x',
      );
      expect(
        () => source.getMessageFromResolvable(
          const DefaultMessageSourceResolvable(['a', 'b']),
        ),
        throwsA(
          isA<NoSuchMessageException>().having((e) => e.code, 'code', 'b'),
        ),
      );
      expect(
        () => source.getMessageFromResolvable(
          const DefaultMessageSourceResolvable([]),
        ),
        throwsA(isA<NoSuchMessageException>()),
      );
      source.useCodeAsDefaultMessage = true;
      expect(
        source.getMessageFromResolvable(
          const DefaultMessageSourceResolvable(['a', 'b']),
        ),
        'a',
      );
    });

    test('parents: abstract and foreign', () {
      final parent = StaticMessageSource()..addMessage('p', '', 'parent {0}');
      final child = StaticMessageSource()..parentMessageSource = parent;
      expect(child.getMessage('p', args: [1]), 'parent 1');
      final foreign = StaticMessageSource()..parentMessageSource = _Foreign();
      expect(foreign.getMessage('f'), 'foreign f');
      expect(foreign.getMessage('missing', defaultMessage: 'd'), 'd');
      expect(
        DelegatingMessageSource(parent).getMessage('p', args: ['x']),
        'parent x',
      );
      expect(
        () => DelegatingMessageSource().getMessage('p'),
        throwsA(isA<NoSuchMessageException>()),
      );
    });
  });

  group('PropertiesMessageSource', () {
    late Directory temp;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('scd_messages_');
      File('${temp.path}/i18n/messages.properties')
        ..createSync(recursive: true)
        ..writeAsStringSync('hello=Hello {0}\nonly.base=base');
      File('${temp.path}/i18n/messages_ru.properties')
          .writeAsStringSync('hello=Привет {0}');
      File('${temp.path}/i18n/errors.properties')
          .writeAsStringSync('hello=from errors\nerror=Error');
    });
    tearDown(() => temp.deleteSync(recursive: true));

    test('bundles, locales, basename order, cache', () {
      final source = PropertiesMessageSource(
        basenames: ['file:${temp.path}/i18n/messages'],
      )..addBasenames(['file:${temp.path}/i18n/errors']);
      expect(source.basenames, hasLength(2));
      expect(
        source.getMessage('hello', args: ['Ada'], locale: 'ru_RU'),
        'Привет Ada',
      );
      expect(source.getMessage('hello', args: ['Ada']), 'Hello Ada');
      expect(source.getMessage('error'), 'Error');
      expect(source.getMessage('only.base', locale: 'ru'), 'base');
      File('${temp.path}/i18n/messages.properties')
          .writeAsStringSync('hello=Changed {0}');
      expect(
        source.getMessage('hello', args: ['x']),
        'Hello x',
        reason: 'cached',
      );
      source.clearCache();
      expect(source.getMessage('hello', args: ['x']), 'Changed x');
      source.cacheMessages = false;
      File('${temp.path}/i18n/messages.properties')
          .writeAsStringSync('hello=Again {0}');
      expect(source.getMessage('hello', args: ['x']), 'Again x');
      expect(source.toString(), contains('basenames'));
    });

    test('async-only resources need preload', () async {
      final loader = DefaultResourceLoader(
        protocolResolvers: [
          FunctionProtocolResolver(
            (location, _) => location.startsWith('asset:')
                ? _AsyncResource(
                    location,
                    {
                      'asset:messages.properties': 'hi=Hi',
                      'asset:messages_de.properties': 'hi=Hallo',
                    }[location],
                  )
                : null,
          ),
        ],
      );
      final source = PropertiesMessageSource(
        basenames: ['asset:messages'],
        resourceLoader: loader,
      )..defaultLocale = 'en';
      expect(() => source.getMessage('hi', locale: 'de'), throwsStateError);
      await source.preload(['de']);
      expect(source.getMessage('hi', locale: 'de'), 'Hallo');
      expect(source.getMessage('hi', locale: 'de_AT'), 'Hallo');
    });
  });
}

class _Foreign implements MessageSource {
  @override
  String getMessage(
    String code, {
    List<Object?> args = const [],
    String? defaultMessage,
    String? locale,
  }) {
    if (code == 'f') {
      return 'foreign f';
    }
    throw NoSuchMessageException(code);
  }

  @override
  String getMessageFromResolvable(
    MessageSourceResolvable resolvable, {
    String? locale,
  }) => throw UnimplementedError();
}

class _AsyncResource extends AbstractResource {
  _AsyncResource(this.description, this.content);
  @override
  final String description;
  final String? content;
  @override
  bool exists() => content != null;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(content!.codeUnits);
}
