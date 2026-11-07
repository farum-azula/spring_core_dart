// The splash tasks: every SplashTask bean runs while the splash shows,
// before the app; their progress is the loader's last share; one that
// fails or hangs does not stop the start. The text warm-up lays out the
// characters of its sources until no font comes in any more.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class _Task extends SplashTask {
  _Task(this.work, {this.label = 'task'});

  final Future<void> Function(SplashTaskContext task) work;
  final String label;

  @override
  String get name => label;

  @override
  Future<void> run(SplashTaskContext task) => work(task);
}

final class _Texts implements TextWarmUpSource {
  const _Texts(this.values);

  final List<String> values;

  @override
  Future<Iterable<String>> texts() async => values;
}

final class _Fonts extends ChangeNotifier {
  void fontIn() => notifyListeners();
}

final class _WarmUp extends TextWarmUp {
  _WarmUp(super.sources, {super.fontsChanged, super.chunk})
    : super(
        firstFont: const Duration(milliseconds: 100),
        settle: const Duration(milliseconds: 50),
        nextFrame: () async {},
      );

  final laidOut = <String>[];

  @override
  void layOut(String text) => laidOut.add(text);
}

Future<ConfigurableApplicationContext> _context(
  List<SplashTask> tasks, {
  String properties = '',
}) => SpringApplication([
  BeanModule(
    'test',
    [
      for (final (i, task) in tasks.indexed)
        BeanDefinition<SplashTask>(
          name: 'task$i',
          types: const [SplashTask],
          create: (_) => task,
        ),
    ],
    resources: {'application.properties': EmbeddedResource.text(properties)},
  ),
], bannerMode: BannerMode.off).runAsync(const []);

void main() {
  test('every task runs; the progress is their share done', () async {
    final gate = Completer<void>();
    final context = await _context([
      _Task((task) async {
        task.progress(0.5);
        await gate.future;
      }),
      _Task((_) async {}),
    ]);
    addTearDown(context.close);
    expect(SplashTasks.any(context), isTrue);
    final seen = <double>[];
    final run = SplashTasks.of(context).run(seen.add);
    await pumpEventQueue();
    expect(seen, [0.25, 0.75]);
    gate.complete();
    await run;
    expect(seen.last, 1);
  });

  test('a task that fails or hangs does not stop the start', () async {
    final context = await _context([
      _Task((_) async => throw StateError('no'), label: 'failing'),
      _Task((_) => Completer<void>().future, label: 'hanging'),
    ], properties: 'spring.flutter.splash.tasks.timeout=50ms');
    addTearDown(context.close);
    await SplashTasks.of(context).run((_) {});
  });

  test('turned off, or none: no task, the beans take the loader', () async {
    final none = await _context(const []);
    addTearDown(none.close);
    expect(SplashTasks.any(none), isFalse);
    final off = await _context([
      _Task((_) async {}),
    ], properties: 'spring.flutter.splash.tasks.enabled=false');
    addTearDown(off.close);
    expect(SplashTasks.any(off), isFalse);
    expect(SplashTasks.shareIn(off.environment), 0);
    expect(SplashTasks.shareIn(none.environment), 0.2);
  });

  testWidgets('the stage tasks, before ready; the loader goes on', (
    tester,
  ) async {
    final gate = Completer<void>();
    final application = SpringApplication([
      BeanModule('test', [
        BeanDefinition<SplashTask>(
          name: 'task',
          types: const [SplashTask],
          create: (_) => _Task((_) => gate.future),
        ),
      ]),
    ], bannerMode: BannerMode.off);
    const child = SizedBox(key: ValueKey('child'));
    await tester.pumpWidget(
      SpringApplicationWidget(application: () => application, child: child),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byKey(const ValueKey('child')), findsNothing);
    gate.complete();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final context = SpringScope.of(
      tester.element(find.byKey(const ValueKey('child'))),
    );
    expect(
      context.getBean<SplashStages>().reached.keys,
      containsAllInOrder([
        SplashStage.starting,
        SplashStage.tasks,
        SplashStage.ready,
      ]),
    );
  });

  test('the warm-up: nothing but ASCII, nothing laid out', () async {
    final warmUp = _WarmUp(const [
      _Texts(['plain text']),
    ]);
    await warmUp.run(SplashTaskContext(_NoContext(), (_) {}));
    expect(warmUp.laidOut, isEmpty);
  });

  test('the warm-up waits until no font comes in for a while', () async {
    final fonts = _Fonts();
    final warmUp = _WarmUp(const [
      _Texts(['日本語', '本の語 and text']),
    ], fontsChanged: fonts);
    final progress = <double>[];
    var ended = false;
    final run = warmUp
        .run(SplashTaskContext(_NoContext(), progress.add))
        .then((_) => ended = true);
    await pumpEventQueue();
    expect(warmUp.laidOut.single.runes.toSet(), '日本語の'.runes.toSet());
    expect(warmUp.laidOut.single.length, 4);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    fonts.fontIn();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    fonts.fontIn();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ended, isFalse, reason: 'a font came in 30 ms ago');
    await run;
    expect(warmUp.laidOut, hasLength(1), reason: 'laid out once');
    expect(progress, [0.5, closeTo(2 / 3, 1e-9)]);
  });

  test('the warm-up lays out a chunk a frame', () async {
    final warmUp = _WarmUp(
      const [
        _Texts(['日本語の文']),
      ],
      fontsChanged: _Fonts(),
      chunk: 2,
    );
    await warmUp.run(SplashTaskContext(_NoContext(), (_) {}));
    expect([for (final text in warmUp.laidOut) text.length], [2, 2, 1]);
  });
}

final class _NoContext implements ApplicationContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
