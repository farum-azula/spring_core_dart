import 'dart:io';

import 'package:dart_spring_language_server/src/dart_index.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
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

  group('resources', () {
    test('classpath: and file: locations go to the file', () {
      const config = r'''
@Configuration()
@PropertySource(['classpath:legacy.properties', 'optional:classpath:none.properties'])
class LegacyConfig {
  @Value('file:config/extra.properties')
  late final Resource extra;
}
''';
      final path = '${root.path}/lib/external/legacy_config.dart';
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(config);
      File('${root.path}/lib/resources/legacy.properties')
          .writeAsStringSync('legacy.greeting=Hello\n');
      File('${root.path}/config/extra.properties')
        ..createSync(recursive: true)
        ..writeAsStringSync('');
      workspace.refresh(force: true);

      List<String> targets(String marker) => [
        for (final range in workspace.definition(
          path,
          config.indexOf(marker) + 3,
        ))
          '${range.path.substring(root.path.length)}:${range.startLine}',
      ];
      expect(targets('classpath:legacy'), [
        '/lib/resources/legacy.properties:0',
      ]);
      expect(targets('file:config'), ['/config/extra.properties:0']);
      expect(targets('optional:classpath:none'), isEmpty);
      expect(
        workspace.hover(path, config.indexOf('classpath:legacy') + 3),
        contains('lib/resources/legacy.properties'),
      );
      expect(
        workspace.hover(path, config.indexOf('optional:classpath:none') + 3),
        contains('not found'),
      );
    });

    test('test files see test/resources first', () {
      final path = '${root.path}/test/app_test.dart';
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          "final r = loader.getResource('classpath:data.txt');\n",
        );
      File('${root.path}/test/resources/data.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('test');
      File('${root.path}/lib/resources/data.txt').writeAsStringSync('main');
      workspace.refresh(force: true);
      final targets = workspace.definition(path, 35);
      expect(
        [for (final range in targets) range.path.substring(root.path.length)],
        ['/test/resources/data.txt', '/lib/resources/data.txt'],
      );
    });
  });

  group('pointcuts', () {
    const aspects = r'''
class Timed {
  const Timed();
}

@Service()
class OrderService {
  @Timed()
  void place() {}
  void cancel() {}
}

@Aspect()
@Component()
class AuditAspect {
  @Pointcut('within(OrderService)')
  void orders() {}

  @Before('orders() && !bean(cash*)')
  void before(JoinPoint joinPoint) {}

  @Around('@annotation(Timed) || execution(* OrderService.can*(..))')
  Object? time(ProceedingJoinPoint joinPoint) => joinPoint.proceed();

  @After('AuditAspect.orders() and ordrs()')
  void after(JoinPoint joinPoint) {}
}
''';
    late String path;

    setUp(() {
      path = '${root.path}/lib/src/aspects.dart';
      File(path).writeAsStringSync(aspects);
      workspace.refresh(force: true);
    });

    List<String> targets(String marker, [int shift = 1]) => [
      for (final range in workspace.definition(
        path,
        aspects.indexOf(marker) + shift,
      ))
        '${range.path.split('/').last}:${range.startLine}',
    ];

    test('types, annotations, beans and named pointcuts navigate', () {
      final aspectsFile = 'aspects.dart';
      expect(targets('OrderService)'), [
        '$aspectsFile:${line('class OrderService', aspects)}',
      ]);
      expect(targets('Timed)'), ['$aspectsFile:0']);
      expect(targets("orders() &&"), [
        '$aspectsFile:${line('void orders()', aspects)}',
      ]);
      expect(targets('AuditAspect.orders()', 13), [
        '$aspectsFile:${line('void orders()', aspects)}',
      ]);
      expect(targets('cash*'), ['shop.dart:${line('class CashPayments')}']);
      expect(targets('can*('), [
        '$aspectsFile:${line('void cancel()', aspects)}',
      ]);
      expect(
        workspace.hover(path, aspects.indexOf('orders() &&') + 1),
        contains('`AuditAspect.orders()`: `within(OrderService)`'),
      );
    });

    test('highlighting and the runtime check', () {
      final tokens = workspace.semanticTokens(path);
      String typeAt(String marker) {
        final at = aspects.indexOf(marker);
        final row = line(marker, aspects);
        final column = at - aspects.lastIndexOf('\n', at) - 1;
        final token = tokens.firstWhere(
          (t) => t.line == row && t.column == column,
        );
        return semanticTokenTypes[token.type];
      }

      expect(typeAt("within(OrderService)"), 'keyword');
      expect(typeAt('OrderService)'), 'type');
      expect(typeAt('&& !bean'), 'operator');
      expect(typeAt('cash*'), 'variable');
      expect(typeAt('Timed) ||'), 'class');
      expect(typeAt('can*('), 'method');
      expect(typeAt('ordrs()'), 'method');

      final problems = workspace.problems(path);
      expect(problems, hasLength(1));
      expect(problems.single.message, contains("unknown pointcut 'ordrs'"));
      expect(problems.single.range.startLine, line('ordrs()', aspects));
    });
  });

  group('cache expressions and @Scheduled', () {
    const books = r'''
@Service()
class Books {
  @Cacheable('books', key: '#isbn', condition: '#isbn.length > 3', unless: '#result == null')
  String? find(String isbn, {int page = 0}) => isbn;

  @Caching(evict: [CacheEvict('books', key: '#isbm')])
  void remove(String isbn) {}

  @CachePut('books', key: '#p0 + ')
  String save(String isbn) => isbn;

  @Cacheable.of(cacheNames: ['books'], key: '#code')
  @Caching(put: [CachePut.of(key: '#cod')])
  String byCode(String code) => code;

  @Scheduled(cron: r'${jobs.cron:0 0 * * * *}', fixedDelayString: r'${jobs.delay}')
  void refresh() {}
}
''';
    late String path;

    setUp(() {
      path = '${root.path}/lib/src/books.dart';
      File(path).writeAsStringSync(books);
      workspace.refresh(force: true);
    });

    test('#parameter goes to the parameter', () {
      final at = books.indexOf("'#isbn'") + 3;
      final targets = workspace.definition(path, at);
      expect(targets, hasLength(1));
      expect(targets.single.startLine, line('String? find', books));
      expect(
        targets.single.startColumn,
        books.split('\n')[line('String? find', books)].indexOf('isbn,'),
      );
      expect(workspace.hover(path, at), contains('`String isbn`'));
    });

    test('highlighting, syntax errors and unknown variables', () {
      final tokens = workspace.semanticTokens(path);
      final keyLine = line("@Cacheable('books'", books);
      final keyColumn = books.split('\n')[keyLine].indexOf('#isbn');
      final variable = tokens.firstWhere(
        (t) => t.line == keyLine && t.column == keyColumn,
      );
      expect(semanticTokenTypes[variable.type], 'variable');
      expect(variable.length, '#isbn'.length);

      final problems = workspace.problems(path);
      final messages = [for (final problem in problems) problem.message];
      expect(messages, contains("Unknown variable '#isbm'; parameters: #isbn"));
      expect(messages.where((m) => m.startsWith('SpEL:')), hasLength(1));
      // #result, #p0 and real parameters are fine; ${jobs.delay} has no
      // default and no properties file defines it.
      // `.of(...)` constructors are recognised too: only `#cod` is wrong.
      expect(messages, contains("Unknown variable '#cod'; parameters: #code"));
      expect(
        messages.where((m) => m.contains('Unknown variable')),
        hasLength(2),
      );
      expect(
        messages,
        contains("Cannot resolve property 'jobs.delay' in any properties file"),
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
