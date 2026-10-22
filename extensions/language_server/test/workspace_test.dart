import 'dart:io';

import 'package:flutter_spring_language_server/src/dart_index.dart';
import 'package:flutter_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _shop = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

abstract interface class Payments {
  String pay(double amount);
}

@Service()
@Primary()
class CardPayments implements Payments {
  @override
  String pay(double amount) => 'card';
}

@Service('cash')
class CashPayments implements Payments {
  @override
  String pay(double amount) => 'cash';
}

class MyStereotype extends Component {
  const MyStereotype();
}

@MyStereotype()
class CryptoPayments implements Payments {
  @override
  String pay(double amount) => 'crypto';
}

class Clock {}

@Configuration()
class AppConfig {
  @Bean(aliases: ['systemClock'])
  Clock clock() => Clock();
}

@Service()
class URLService {}

@Service()
class Checkout {
  Checkout(
    this.payments,
    @Qualifier('cash') this.refunds,
    this.all, {
    @Value(r'${shop.name}') required this.name,
  });

  final Payments payments;
  final Payments refunds;
  final List<Payments> all;
  final String name;

  @Value(r'#{appConfig.toString()} and ${shop.missing} ${shop.port:80}')
  late final String banner;

  @Value('#{1 +}')
  late final String broken;

  @Value(r'${shop.motto}')
  String? motto;

  void run(ApplicationContext context) {
    context.getBean<Clock>();
    context.environment.getProperty('shop.name');
  }
}
''';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String shopPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_ws_');
    shopPath = '${root.path}/lib/src/shop.dart';
    File(shopPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(_shop);
    File('${root.path}/lib/resources/application.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('# shop\nshop.name=NEON Books\n');
    File('${root.path}/lib/resources/application-prod.properties')
        .writeAsStringSync('shop.name = NEON Online\n');
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  int at(String marker, [int skip = 0]) {
    var index = -1;
    for (var i = 0; i <= skip; i++) {
      index = _shop.indexOf(marker, index + 1);
    }
    expect(index, isNonNegative, reason: marker);
    return index;
  }

  List<String> definitions(int offset) => [
    for (final range in workspace.definition(shopPath, offset))
      '${range.path.split('/').last}:${range.startLine}',
  ];

  int line(String text, [String source = _shop]) =>
      source.substring(0, source.indexOf(text)).split('\n').length - 1;

  group('beans', () {
    test('components, @Bean methods, custom stereotypes, names', () {
      final beans = {for (final b in workspace.beans) b.name: b};
      expect(
        beans.keys,
        containsAll([
          'cardPayments',
          'cash',
          'cryptoPayments',
          'appConfig',
          'clock',
          'URLService',
          'checkout',
        ]),
      );
      expect(beans['clock']!.kind, BeanKind.beanMethod);
      expect(beans['clock']!.aliases, {'systemClock'});
      expect(
        beans['cash']!.providedTypes,
        containsAll(['CashPayments', 'Payments']),
      );
    });

    test('a constructor-injected field type goes to the candidate beans', () {
      expect(definitions(at('Payments payments') + 2), [
        'shop.dart:${line('class CardPayments')}', // @Primary first
        'shop.dart:${line('class CashPayments')}',
        'shop.dart:${line('class CryptoPayments')}',
      ]);
    });

    test('this.x with @Qualifier goes to the qualified bean', () {
      expect(definitions(at('this.refunds') + 6), [
        'shop.dart:${line('class CashPayments')}',
      ]);
      expect(definitions(at("Qualifier('cash')") + 12), [
        'shop.dart:${line('class CashPayments')}',
      ]);
    });

    test('List<T> and getBean<T>()', () {
      expect(definitions(at('List<Payments>') + 6), hasLength(3));
      expect(definitions(at('getBean<Clock>') + 9), [
        'shop.dart:${line('Clock clock()')}',
      ]);
    });

    test('a bean name inside SpEL', () {
      expect(definitions(at('appConfig.toString') + 2), [
        'shop.dart:${line('class AppConfig')}',
      ]);
    });

    test('types outside injection points are left to the Dart server', () {
      expect(definitions(at('String pay(double') + 2), isEmpty);
    });
  });

  group('properties', () {
    test('@Value placeholder goes to every file defining the key', () {
      expect(definitions(at(r'${shop.name}') + 4), [
        'application.properties:1',
        'application-prod.properties:0',
      ]);
      expect(definitions(at("getProperty('shop.name')") + 15), hasLength(2));
    });

    test('hover shows the values per file', () {
      final hover = workspace.hover(shopPath, at(r'${shop.name}') + 4)!;
      expect(hover, contains('`application`: `NEON Books`'));
      expect(hover, contains('`application-prod`: `NEON Online`'));
      expect(
        workspace.hover(shopPath, at('Payments payments') + 2),
        contains("bean 'cash': CashPayments"),
      );
    });
  });

  group('checks and highlighting', () {
    test('unknown keys without default and invalid SpEL are reported', () {
      final problems = workspace.problems(shopPath);
      expect(
        problems.map((p) => p.message),
        containsAll([
          "Cannot resolve property 'shop.missing' in any properties file",
          startsWith('SpEL:'),
        ]),
      );
      // shop.port has a default, shop.name exists, motto is nullable.
      expect(problems.where((p) => p.message.contains('shop.motto')), isEmpty);
      expect(problems.where((p) => p.message.contains('shop.port')), isEmpty);
      expect(problems.where((p) => p.message.contains("'shop.name'")), isEmpty);
      expect(
        problems.singleWhere((p) => p.error).range.startLine,
        line("#{1 +}"),
      );
    });

    test('semantic tokens for placeholders and SpEL', () {
      final tokens = workspace.semanticTokens(shopPath);
      final types = {
        for (final token in tokens)
          _shop
                  .split('\n')[token.line]
                  .substring(token.column, token.column + token.length):
              semanticTokenTypes[token.type],
      };
      expect(types['shop.name'], 'property');
      expect(types['appConfig'], 'property');
      expect(types['toString'], 'method');
      expect(types['#{'], 'keyword');
      expect(types[r'${'], 'operator');
    });
  });

  test('a placeholder in a non-raw string is reported', () {
    workspace.setOverlay(
      shopPath,
      _shop.replaceFirst(r"@Value(r'${shop.name}')", r"@Value('${shop.name}')"),
    );
    expect(
      workspace.problems(shopPath).map((p) => p.message),
      contains(contains("use a raw string, r'")),
    );
  });

  test('open documents are used instead of the disk', () {
    workspace.setOverlay(
      shopPath,
      _shop.replaceFirst("@Service('cash')", "@Service('cashier')"),
    );
    expect(workspace.beansNamed('cashier'), hasLength(1));
    expect(workspace.beansNamed('cash'), isEmpty);
    workspace.setOverlay(shopPath, null);
    workspace.refresh(force: true);
    expect(workspace.beansNamed('cash'), hasLength(1));
  });
}
