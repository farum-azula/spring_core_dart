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

  group('the tab', () {
    final app = springBootTest(springApplication);

    testWidgets('shows every bean and member by name', (tester) async {
      final basket = app.getBean<Basket>()
        ..add(const Book('Dune', 10))
        ..coupon = 'TEN';
      expect(basket.total, 9);
      final catalog = app.getBean<Catalog>();
      await tester.runAsync(() => catalog.books);

      final section = SignalsDebugSection(app.getBean<SignalBeans>());
      expect(section.title, 'State');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(builder: section.build),
        ),
      );

      expect(find.text('Basket'), findsOneWidget);
      expect(find.text('coupon'), findsOneWidget);
      expect(find.textContaining('TEN, assigned'), findsOneWidget);
      expect(find.text('computed: 9.0'), findsOneWidget);
      expect(find.textContaining('effect, ran'), findsOneWidget);
      expect(find.text('Catalog'), findsOneWidget);
      expect(find.textContaining('loaded 1 time'), findsOneWidget);

      // The periodic refresh ends with the tab.
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('a hidden field shows no value', () {
    final member = ValueMember('Session.token', 'secret', hidden: true);
    expect(member.hidden, isTrue);
    expect(const Signal(hidden: true).hidden, isTrue);
    expect(const Signal().hidden, isFalse);
    expect(SignalsDebugSection.describe(member), isNot(contains('secret')));
  });

  test('the tab says of a late field that it is not assigned, and of a '
      'computed value that fails what it threw', () {
    expect(
      SignalsDebugSection.describe(ValueMember.unset('Late.name')),
      'late, not assigned yet',
    );
    final failing = ComputedMember(
      'Late.shown',
      () => throw StateError('no name yet'),
    );
    addTearDown(failing.dispose);
    expect(
      SignalsDebugSection.describe(failing),
      allOf(startsWith('failed: '), contains('no name yet')),
    );
    expect(failing.read, throwsStateError);
  });

  test('a bean whose proxy cannot follow its own calls (an application '
      'built by an older generator) stops the start, saying what to '
      'update', () {
    final factory = DefaultListableBeanFactory()
      ..registerBeanDefinition(
        BeanDefinition<Object>(
          name: 'pageLamps',
          create: (_) => Object(),
          // What a generator before 0.8.1 wrote for such a bean: a proxy
          // that wraps it.
          aopProxy: AopProxyFactory(
            signatures: const [
              MethodSignature.of(
                'lamps',
                AopTarget(r'PageLamps', types: [r'PageLamps']),
                kind: MemberKind.getter,
                returnType: 'Map',
                annotations: [Signal()],
                annotationTypes: ['Signal'],
              ),
            ],
            create: (target, invoker) => target,
          ),
        ),
      );
    final beans = SignalBeans();
    addTearDown(beans.dispose);
    expect(
      () => SignalBeanNames(beans).postProcessBeanFactory(factory),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains("The bean 'pageLamps'"),
            contains('spring_core_dart_generator older than 0.8.1'),
            contains('build again'),
          ),
        ),
      ),
    );
    expect(beans.names, isEmpty);
  });
}
