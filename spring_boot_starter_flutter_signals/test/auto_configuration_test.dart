// The starter's beans, the tab of the debug panel by its property, and
// what the tab shows of the example's beans.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show
        ApplicationContextRunner,
        doesNotHaveBean,
        hasSingleBean,
        springBootTest;

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

void main() {
  final runner = const ApplicationContextRunner()
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
      .withAutoConfiguration(springBootStarterFlutterSignalsAutoConfiguration)
      .withAutoConfiguration(
        springBootStarterFlutterSignalsDebugAutoConfiguration,
      );

  test('the beans', () {
    runner.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SignalBeans>());
      expect(context, hasSingleBean<SignalEffects>());
      expect(context, hasSingleBean<SignalBuildTracker>());
      expect(context.getBean<WidgetBuildTracker>(), isA<SignalBuildTracker>());
      expect(
        context.getBean<DebugPanelSection>(qualifier: 'signalsDebugSection'),
        isA<SignalsDebugSection>(),
      );
    });
  });

  test('the tab, off by its property', () {
    runner
        .withPropertyValues(['spring.flutter.signals.debug.enabled=false'])
        .run((context) {
          expect(context, doesNotHaveBean<SignalsDebugSection>());
          expect(context, hasSingleBean<SignalBeans>());
        });
  });

  test("the console's segment and the activity log: each on its own "
      'switch', () {
    final withConsole = runner.withAutoConfiguration(
      springBootStarterFlutterSignalsDebugConsoleAutoConfiguration,
    );
    withConsole.run((context) {
      expect(context.startupFailure, isNull);
      expect(context, hasSingleBean<SignalsSegment>());
      expect(context, hasSingleBean<SignalsDebugRecorder>());
      expect(context, doesNotHaveBean<SignalsDebugLog>());
      expect(
        context.context
            .findAnnotationOnBean<ConsoleSegment>('signalsSegment')
            ?.segment,
        'signals',
      );
      expect(SignalProbes.current, isNull, reason: 'nothing shows yet');
    });
    withConsole
        .withPropertyValues([
          'spring.flutter.debug.console.enabled=false',
          'spring.flutter.signals.debug.log.enabled=true',
        ])
        .run((context) {
          expect(context, doesNotHaveBean<SignalsSegment>());
          expect(context, hasSingleBean<SignalsDebugLog>());
          expect(SignalProbes.current, isA<SignalsDebugLog>());
        });
    expect(SignalProbes.current, isNull);
  });

  group('the tab', () {
    final app = springBootTest(springApplication);

    testWidgets('shows every bean and member by name', (tester) async {
      final basket = app.getBean<Basket>()
        ..add(const Book('Dune', 10))
        ..coupon = 'TEN';
      expect(basket.total, 9);
      final catalog = app.getBean<Catalog>();
      await tester.runAsync(() => catalog.books);

      final recorder = SignalsDebugRecorder();
      final section = SignalsDebugSection(
        app.getBean<SignalBeans>(),
        recorder: recorder,
        queues: app.getBean<SignalRuntime>().queues,
      );
      expect(section.title, 'Signals');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: section.build),
        ),
      );

      expect(find.text('Basket  ·  singleton'), findsOneWidget);
      expect(find.text('coupon'), findsOneWidget);
      expect(find.text("'TEN'"), findsOneWidget);
      expect(find.text('9.0'), findsOneWidget);
      expect(find.text('save()'), findsOneWidget);
      expect(find.text('effect'), findsOneWidget);
      expect(find.text('Catalog  ·  singleton'), findsOneWidget);
      expect(find.text('List(1)'), findsOneWidget, reason: 'the items');
      expect(
        find.byType(SignalsLock),
        findsOneWidget,
        reason: "the books, kept for their caller",
      );
      expect(find.text('reads/5s'), findsNWidgets(2));
      expect(find.text('Queues'), findsOneWidget);
      expect(find.textContaining('microtask, 0 waiting'), findsOneWidget);
      expect(find.text('Buffers'), findsOneWidget);
      expect(SignalProbes.current, same(recorder), reason: 'while it shows');

      // Read through the tab while it shows: the tree and the timings.
      basket.coupon = null;
      await tester.pump(const Duration(milliseconds: 300));
      expect(basket.total, 10);
      expect(recorder.readers.keys, isNotEmpty);

      // The periodic refresh and the collection end with the tab.
      await tester.pumpWidget(const SizedBox());
      expect(SignalProbes.current, isNull);
    });
  });

  test('a hidden field shows no value', () {
    final member = ValueMember('Session.token', 'secret', hidden: true);
    expect(member.hidden, isTrue);
    expect(const Signal(hidden: true).hidden, isTrue);
    expect(const Signal().hidden, isFalse);
    final row = SignalsRow.member(member, null);
    expect(row.tone, SignalsValueTone.locked);
    expect(row.value, isNot(contains('secret')));
  });

  test('the tab says of a late field that it is not assigned, and of a '
      'computed value that fails what it threw', () {
    final unset = SignalsRow.member(ValueMember.unset('Late.name'), null);
    expect(unset.value, 'late, unset');
    expect(unset.tone, SignalsValueTone.none);
    final failing = ComputedMember(
      'Late.shown',
      () => throw StateError('no name yet'),
    );
    addTearDown(failing.dispose);
    final row = SignalsRow.member(failing, null);
    expect(row.value, allOf(startsWith('failed: '), contains('no name yet')));
    expect(row.tone, SignalsValueTone.failed);
    expect(failing.read, throwsStateError);
  });

  test('an @Effect on a bean the generator made no subclass for stops the '
      'start, saying what to update', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Object>(
          name: 'pageLamps',
          annotatedMethods: [
            IntrospectedMethod<Object>(
              'watch',
              invoke: (_, _) => null,
              isVoid: true,
              annotations: const [Effect()],
            ),
          ],
          create: (_) => Object(),
        ),
      );
    final beans = SignalBeans();
    addTearDown(beans.dispose);
    final effects = SignalEffects.of(
      beans,
      SignalRuntime(queues: SignalQueues(const SignalQueueSettings())),
    )..setBeanFactory(factory);
    expect(
      () => effects.postProcessAfterInitialization(Object(), 'pageLamps'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains("The bean 'pageLamps'"), contains('generator')),
        ),
      ),
    );
  });

  test('an @Effect whose first run throws stops the bean and ends its '
      'state: the effect does not run again on the half-made bean', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Object>(
          name: 'gauge',
          annotatedMethods: [
            IntrospectedMethod<Object>(
              'check',
              invoke: (bean, _) {
                (bean as _Gauge).check();
                return null;
              },
              isVoid: true,
              annotations: const [Effect()],
            ),
          ],
          create: (_) => _Gauge(),
        ),
      );
    final beans = SignalBeans();
    addTearDown(beans.dispose);
    final effects = SignalEffects.of(
      beans,
      SignalRuntime(
        queues: SignalQueues(
          SignalQueueSettings(schedule: SignalFlushSchedules.immediate()),
        ),
      ),
    )..setBeanFactory(factory);
    final gauge = _Gauge();

    expect(
      () => effects.postProcessAfterInitialization(gauge, 'gauge'),
      throwsStateError,
    );
    expect(gauge.runs, 1);
    expect(gauge.signalBean.closed, isTrue);
    expect(beans.live, isNot(contains(gauge.signalBean)));

    gauge.level = 1;
    expect(gauge.runs, 1, reason: 'the effect was stopped with the bean');
  });
}

// A bean on signals as the generator writes it, whose effect fails on its
// first run.
final class _Gauge implements SignalBeanHolder {
  @override
  final SignalBean signalBean = SignalBean('Gauge');

  late final ValueMember _level = signalBean.field('level', () => 0);

  int runs = 0;

  int get level => _level.read()! as int;

  set level(int value) => _level.write(value);

  void check() => signalBean.effectBody('check', () {
    runs++;
    if (level == 0) {
      throw StateError('no level yet');
    }
  });

  @override
  Map<String, SignalMember Function()> get signalMembers => {
    'level': () => _level,
  };

  @override
  List<String> get eagerSignals => const [];

  @override
  List<String> get signalQueues => const [];
}
