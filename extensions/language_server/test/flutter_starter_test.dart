// spring_boot_starter_flutter in the editor: `context.basket` getters and
// `context.bean<T>()` go to the beans, so do the types of a Spring widget's
// bean record; `asset:` locations go to the file and are checked against
// `flutter: assets:` of pubspec.yaml.
import 'dart:io';

import 'package:dart_spring_language_server/src/flutter_assets.dart';
import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _app = r'''
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@ChangeNotifierComponent()
@BuildContextAccess()
class Basket {
  int count = 0;
}

class Clock {}

@Configuration()
class Clocks {
  @Bean()
  @BuildContextAccess(name: 'clock')
  Clock localClock() => Clock();

  @Bean()
  Clock utc() => Clock();
}

@Component()
class AppAssets {
  AppAssets(
    @Value('asset:assets/images/logo.png') this.logo,
    @Value('asset:/assets/sounds/tap.mp3') this.tap,
    @Value('asset:assets/texts/missing.txt') this.missing,
    @Value(r'asset:${sound.file:assets/x.mp3}') this.dynamic,
    @Value('asset:packages/icons/star.png') this.star,
  );
  final Resource logo;
  final Resource tap;
  final Resource missing;
  final Resource dynamic;
  final Resource star;
}

class BasketBadge extends SpringStatelessWidget<(Basket, {Clock utc})> {
  const BasketBadge({super.key});

  @override
  Widget build(BuildContext context) {
    context.basket.count;
    context.clock;
    context.bean<Basket>();
    return const SizedBox();
  }
}

class BasketPage extends SpringStatefulWidget<(Basket,)> {
  const BasketPage({super.key});
}

class _BasketPageState extends SpringState<BasketPage, (Basket,)> {}

/// The beans of [OrdersPage].
typedef OrdersPageBeans = (Basket, Clock);

class OrdersPage extends SpringStatefulWidget<OrdersPageBeans> {
  const OrdersPage({super.key});
}

class _OrdersPageState extends SpringState<OrdersPage, OrdersPageBeans> {}

/// A record no Spring widget uses.
typedef Pair = (Basket, Clock);
''';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String path;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lsp_flutter_');
    path = '${root.path}/lib/app.dart';
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(_app);
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: app
flutter:
  assets:
    - assets/images/
''');
    for (final asset in ['assets/images/logo.png', 'assets/sounds/tap.mp3']) {
      File('${root.path}/$asset')
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  int at(String marker, [int skip = 0]) {
    var index = -1;
    for (var i = 0; i <= skip; i++) {
      index = _app.indexOf(marker, index + 1);
    }
    expect(index, isNonNegative, reason: marker);
    return index;
  }

  int line(String text) =>
      _app.substring(0, _app.indexOf(text)).split('\n').length - 1;

  List<int> lines(int offset) => [
    for (final range in workspace.definition(path, offset)) range.startLine,
  ];

  test('@ChangeNotifierComponent is a bean stereotype', () {
    expect(workspace.beansNamed('basket'), hasLength(1));
  });

  test('context.<getter> goes to the @BuildContextAccess bean', () {
    expect(lines(at('context.basket') + 'context.'.length + 1), [
      line('class Basket'),
    ]);
    // `name:` on a @Bean method.
    expect(lines(at('context.clock;') + 'context.'.length + 1), [
      line('Clock localClock()'),
    ]);
    expect(
      workspace.hover(path, at('context.basket') + 'context.'.length + 1),
      contains('@BuildContextAccess'),
    );
    // The receiver itself is no bean.
    expect(lines(at('context.basket') + 1), isEmpty);
  });

  test('context.bean<T>() goes to the beans of T', () {
    expect(lines(at('bean<Basket>') + 'bean<'.length + 1), [
      line('class Basket'),
    ]);
  });

  test('the bean record of a Spring widget goes to the beans', () {
    expect(lines(at('(Basket, {Clock') + 2), [line('class Basket')]);
    // A named field picks among several beans by its name.
    expect(lines(at('Clock utc})') + 1), [line('Clock utc()')]);
    expect(lines(at('SpringStatefulWidget<(Basket') + 23), [
      line('class Basket'),
    ]);
    expect(lines(at('BasketPage, (Basket') + 'BasketPage, ('.length + 1), [
      line('class Basket'),
    ]);
  });

  test("a typedef of a Spring widget's bean record goes to the beans", () {
    expect(
      lines(at('OrdersPageBeans = (Basket') + 'OrdersPageBeans = ('.length + 1),
      [line('class Basket')],
    );
    // A record no Spring widget takes: not beans.
    expect(lines(at('Pair = (Basket') + 'Pair = ('.length + 1), isEmpty);
  });

  test('asset: goes to the file of the package', () {
    final targets = workspace.definition(path, at('asset:assets/images') + 8);
    expect(
      [for (final range in targets) range.path.substring(root.path.length)],
      ['/assets/images/logo.png'],
    );
    expect(
      workspace.hover(path, at('asset:/assets/sounds') + 8),
      contains('assets/sounds/tap.mp3'),
    );
  });

  test('asset: problems: missing files, not declared in pubspec.yaml', () {
    final problems = {
      for (final problem in workspace.problems(path))
        if (problem.range.startLine >= line('AppAssets(') &&
            problem.range.startLine <= line('final Resource logo'))
          problem.range.startLine: problem.message,
    };
    expect(problems, {
      line('asset:/assets/sounds'):
          'assets/sounds/tap.mp3 is not declared in pubspec.yaml, so the app '
          'would not contain it: add `- assets/sounds/` under '
          '`flutter: assets:`',
      line('asset:assets/texts'):
          'No file assets/texts/missing.txt in this '
          'package',
    });
  });

  test('a changed pubspec.yaml is read again', () {
    File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: app
flutter:
  assets:
    - assets/images/
    - path: assets/sounds/
      flavors: [prod]
''');
    // Make sure the modification time differs.
    File('${root.path}/pubspec.yaml')
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
    expect(
      workspace.problems(path).map((p) => p.message),
      isNot(contains(contains('assets/sounds/tap.mp3'))),
    );
  });

  group('flutterAssets / declaredAsset', () {
    test('entries: strings and path: maps', () {
      expect(
        flutterAssets(
          'flutter:\n  assets:\n    - a/\n    - path: b/c.png\n      flavors: [x]\n',
        ),
        ['a/', 'b/c.png'],
      );
      expect(flutterAssets('name: x\n'), isEmpty);
      expect(flutterAssets(': : :'), isEmpty);
    });

    test('a directory declares its own files, not its subdirectories', () {
      expect(declaredAsset(['assets/'], 'assets/a.png'), isTrue);
      expect(declaredAsset(['assets/'], 'assets/x/a.png'), isFalse);
      expect(declaredAsset(['./assets/x/'], 'assets/x/a.png'), isTrue);
      expect(declaredAsset(['assets/x/a.png'], 'assets/x/a.png'), isTrue);
      expect(declaredAsset(['a.png'], 'a.png'), isTrue);
    });
  });
}
