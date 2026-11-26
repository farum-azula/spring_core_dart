// The Signals tab: the widgets by name with their rebuilds (and nothing
// of them kept without the debug tools), the members in columns with
// short values and their colours, the times since a change and since the
// readers were told, and the highlight of a row that changed.
import 'dart:io';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart'
    show ApplicationContextRunner, doesNotHaveBean, springBootTest;

import '../example/example.dart';
import '../example/spring_gen/example.spring.dart';

/// A clock a test moves by hand.
final class _Clock {
  Duration now = Duration.zero;
  Duration call() => now;
}

enum _Tab { reviews }

Future<ApplicationContext> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => springApplication,
      home: Directionality(textDirection: TextDirection.ltr, child: home),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  return SpringScope.of(tester.element(find.byType(Directionality).first));
}

Future<void> _told(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

List<String> _widgetLabels(SignalsDebugRecorder recorder) => [
  for (final reader in recorder.readers.keys)
    if (reader is SignalTracking && !reader.disposed) reader.label,
]..sort();

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  group('widget names', () {
    testWidgets('a type alone, a number when repeated, a key that says '
        'something; a number freed is given again', (tester) async {
      final context = await _pump(
        tester,
        const Column(
          children: [
            CouponLabel(),
            CouponLabel(),
            CouponLabel(key: ValueKey(42)),
          ],
        ),
      );
      final recorder = context.getBean<SignalsDebugRecorder>();
      final release = recorder.use();
      addTearDown(release);
      // Named as they build again for the tool, in the order of the tree.
      await tester.pump();
      expect(_widgetLabels(recorder), [
        'CouponLabel #1',
        'CouponLabel #2',
        'CouponLabel [42]',
      ]);

      // The second leaves: the first keeps its number, the label of a
      // lone one has none.
      await _pump(
        tester,
        const Column(
          children: [
            CouponLabel(),
            CouponLabel(key: ValueKey(42)),
          ],
        ),
      );
      recorder.pruneEnded();
      expect(_widgetLabels(recorder), ['CouponLabel #1', 'CouponLabel [42]']);

      await _pump(
        tester,
        const Column(
          children: [
            CouponLabel(),
            CouponLabel(key: ValueKey(42)),
            CouponLabel(key: ValueKey('a b')),
          ],
        ),
      );
      expect(
        _widgetLabels(recorder),
        ['CouponLabel #1', 'CouponLabel #2', 'CouponLabel [42]'],
        reason: 'a key that could be data is a number, the freed #2',
      );

      await _pump(tester, const CouponLabel());
      recorder.pruneEnded();
      expect(_widgetLabels(recorder), ['CouponLabel']);
    });

    testWidgets('nothing is named while no tool collects; the widgets on '
        'the screen are named when one starts, and no more once the last '
        'stops', (tester) async {
      final context = await _pump(
        tester,
        const Column(children: [CouponLabel(), CouponLabel()]),
      );
      final names = context.getBean<SignalWidgetNames>();
      final recorder = context.getBean<SignalsDebugRecorder>();
      expect(names.naming, isFalse);
      expect(names.liveOf('CouponLabel'), 0, reason: 'no name worked out');

      final release = recorder.use();
      expect(names.naming, isTrue);
      await tester.pump();
      expect(names.liveOf('CouponLabel'), 2);
      expect(_widgetLabels(recorder), ['CouponLabel #1', 'CouponLabel #2']);

      release();
      expect(names.naming, isFalse);
      await _pump(
        tester,
        const Column(children: [CouponLabel(), CouponLabel(), CouponLabel()]),
      );
      expect(names.liveOf('CouponLabel'), 2, reason: 'the third is not named');
    });

    test(
      'a key is shown only when it is a number, an enum or a plain word',
      () {
        expect(SignalWidgetNames.keyLabel(const ValueKey(7)), '7');
        expect(
          SignalWidgetNames.keyLabel(const ValueKey(_Tab.reviews)),
          'reviews',
        );
        expect(SignalWidgetNames.keyLabel(const ValueKey('row-3')), 'row-3');
        expect(
          SignalWidgetNames.keyLabel(const ValueKey('ann@mail.com')),
          isNull,
        );
        expect(SignalWidgetNames.keyLabel(const ValueKey('two words')), isNull);
        expect(
          SignalWidgetNames.keyLabel(ValueKey('x' * 25)),
          isNull,
          reason: 'longer than 24',
        );
        expect(SignalWidgetNames.keyLabel(ObjectKey(Object())), isNull);
        expect(SignalWidgetNames.keyLabel(GlobalKey()), isNull);
        expect(SignalWidgetNames.keyLabel(null), isNull);
      },
    );

    testWidgets('rebuilds are counted per widget over the read window and '
        'shown in the list', (tester) async {
      final clock = _Clock();
      final context = await _pump(
        tester,
        const Column(children: [CouponLabel(), CouponLabel()]),
      );
      final recorder = SignalsDebugRecorder(
        clock: clock.call,
        names: context.getBean<SignalWidgetNames>(),
      );
      final release = recorder.use();
      addTearDown(release);
      // The first build for the tool: the widgets are named as they build.
      await tester.pump();
      final basket = context.getBean<Basket>();
      for (final coupon in ['A', 'B', 'C']) {
        basket.coupon = coupon;
        await _told(tester);
      }
      final trackings = [
        for (final reader in recorder.readers.keys)
          if (reader is NamedSignalTracking) reader,
      ];
      expect(trackings, hasLength(2));
      for (final tracking in trackings) {
        expect(recorder.rebuildsOf(tracking), 4, reason: 'first build + 3');
      }
      final first = trackings.firstWhere((t) => t.number == 1);
      expect(
        SignalsTree.label(recorder, first),
        'CouponLabel #1 · 4 rebuilds/5s',
      );
      expect(
        SignalsTree.lines(recorder, [
          (basket as SignalBeanHolder).signalBean,
        ]).map((line) => line.label),
        contains('CouponLabel #2 · 4 rebuilds/5s'),
      );

      // Out of the window.
      clock.now = const Duration(seconds: 6);
      expect(recorder.rebuildsOf(first), 0);
      basket.coupon = 'D';
      await _told(tester);
      expect(recorder.rebuildsOf(first), 1);
      basket.coupon = null;
      await _told(tester);
    });
  });

  group('nothing kept without the debug tools', () {
    final base = const ApplicationContextRunner()
        .withAutoConfiguration(springBootAutoConfiguration)
        .withAutoConfiguration(springBootStarterFlutterAutoConfiguration)
        .withAutoConfiguration(
          springBootStarterFlutterSignalsAutoConfiguration,
        );

    testWidgets('out of the build: no names bean, a plain tracking that '
        'keeps nothing of the widget', (tester) async {
      await tester.pumpWidget(_host(const SizedBox()));
      final element = tester.element(find.byType(SizedBox));
      base.run((context) {
        expect(context.startupFailure, isNull);
        expect(context, doesNotHaveBean<SignalWidgetNames>());
        final tracker = context.getBean<SignalBuildTracker>();
        expect(tracker.names, isNull);
        final tracking = tracker.attachTo(() {}, element);
        expect(tracking.runtimeType, SignalTracking);
        expect((tracking as SignalTracking).label, 'a widget');
        tracking.dispose();
      });
      base
          .withAutoConfiguration(
            springBootStarterFlutterSignalsDebugAutoConfiguration,
          )
          .run((context) {
            final tracker = context.getBean<SignalBuildTracker>();
            expect(tracker.names, isNotNull);
            final tracking = tracker.attachTo(() {}, element);
            expect(tracking, isA<NamedSignalTracking>());
            expect((tracking as SignalTracking).label, 'SizedBox');
            tracking.dispose();
          });
      // In the build, but the tab is off in the running app: no view shows
      // the widgets, so none is named.
      base
          .withAutoConfiguration(
            springBootStarterFlutterSignalsDebugAutoConfiguration,
          )
          .withPropertyValues(['spring.flutter.signals.debug.enabled=false'])
          .run((context) {
            expect(context.startupFailure, isNull);
            expect(context, doesNotHaveBean<SignalWidgetNames>());
            expect(context.getBean<SignalBuildTracker>().names, isNull);
          });
    });

    test(
      'the names bean is in the debug module only, behind its build key',
      () {
        final source = File(
          'lib/spring_auto_configuration.dart',
        ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
        final debugModule = source.substring(
          source.indexOf(
            'springBootStarterFlutterSignalsDebugAutoConfiguration=',
          ),
        );
        expect(debugModule, contains('_widgetNamesFor('));
        expect(
          source.substring(
            0,
            source.indexOf(
              'springBootStarterFlutterSignalsDebugAutoConfiguration=',
            ),
          ),
          isNot(contains('_widgetNamesFor(const')),
        );
        expect(
          source,
          contains(
            'SignalBuildTracker(r.optionalDependency<SignalWidgetNames>())',
          ),
        );
      },
    );
  });

  group('columns, values and colours', () {
    test('short values', () {
      expect(SignalsValues.short(_Plain()), '_Plain');
      expect(SignalsValues.short({'a': 1}), 'Map(1)');
      expect(SignalsValues.short([1, 2, 3]), 'List(3)');
      expect(SignalsValues.short(<int>{}), 'Set(0)');
      expect(SignalsValues.short(null), 'null');
      expect(SignalsValues.short(_Tab.reviews), '_Tab.reviews');
      final long = SignalsValues.short('x' * 100);
      expect(long, hasLength(40));
      expect(long, endsWith('…'));
      expect(SignalsValues.short('two\nlines'), "'two lines'");
      expect(SignalsValues.items([1, 2, 3]), '1, 2, 3');
      expect(SignalsValues.items({'a': 1}), "'a': 1");
      expect(
        SignalsValues.items(List.generate(25, (i) => i)),
        endsWith('19, … 5 more'),
      );
    });

    test('times: 0.4s, 12s, 3m, 2h, — for never; time taken', () {
      Duration s(num seconds) =>
          Duration(milliseconds: (seconds * 1000).round());
      expect(SignalsValues.ago(Duration.zero, s(0.4)), '0.4s');
      expect(SignalsValues.ago(Duration.zero, s(12)), '12s');
      expect(SignalsValues.ago(Duration.zero, s(180)), '3m');
      expect(SignalsValues.ago(Duration.zero, s(7200)), '2h');
      expect(SignalsValues.ago(null, s(1)), '—');
      expect(SignalsValues.ago(s(2), s(1)), '0.0s', reason: 'never negative');
      expect(SignalsValues.took(const Duration(microseconds: 12)), '12µs');
      expect(SignalsValues.took(const Duration(microseconds: 1400)), '1.4ms');
    });

    testWidgets('headers; the value in the number colour, bold; zero counts '
        'muted, others plain; failed red, loading amber; a lock for a '
        'hidden value', (tester) async {
      final recorder = SignalsDebugRecorder();
      final release = recorder.use();
      addTearDown(release);
      final coupon = ProbedValueMember('Basket.coupon', 'TEN');
      final token = ProbedValueMember('Session.token', 'eyJ.secret');
      final failing = ProbedComputedMember(
        'Basket.shown',
        () => throw StateError('no name'),
      );
      addTearDown(() {
        for (final member in [coupon, token, failing]) {
          member.dispose();
        }
      });
      coupon
        ..write('ONE')
        ..write('TWO');
      final rows = [
        SignalsRow.member(coupon, recorder),
        SignalsRow.member(token, recorder),
        SignalsRow.member(failing, recorder),
        SignalsRow(
          node: Object(),
          label: 'books',
          kind: SignalsRowKind.asynchronous,
          value: 'loading',
          tone: SignalsValueTone.loading,
          changes: 0,
        ),
      ];
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: SignalsTable(
              rows,
              recorder: recorder,
              now: recorder.now,
              timesAt: recorder.now,
            ),
          ),
        ),
      );
      final style = DebugStyle.fromApp(
        tester.element(find.byType(SignalsTable)),
      );
      for (final header in [
        'value',
        'changed',
        'told',
        'changes',
        'writes',
        'ticks',
        'reads/5s',
        'time',
      ]) {
        expect(
          tester.widget<Text>(find.text(header)).style?.color,
          style.muted,
          reason: header,
        );
      }
      final value = tester.widget<Text>(find.text("'TWO'"));
      expect(value.style?.color, style.number);
      expect(value.style?.fontWeight, FontWeight.w600);
      expect(find.textContaining('eyJ'), findsNothing);
      expect(find.byType(SignalsLock), findsOneWidget);
      await tester.tap(find.byType(SignalsLock));
      await tester.pump();
      expect(find.textContaining('looks secret'), findsOneWidget);
      expect(
        tester.widget<Text>(find.textContaining('failed: ')).style?.color,
        style.bad,
      );
      expect(
        tester.widget<Text>(find.text('loading')).style?.color,
        style.warning,
      );
      // coupon: 2 changes, 2 writes, 2 ticks.
      expect(
        tester.widgetList<Text>(find.text('2')).map((t) => t.style?.color),
        everyElement(style.foreground),
      );
      expect(
        tester.widgetList<Text>(find.text('0')).map((t) => t.style?.color),
        everyElement(style.muted),
      );
    });

    for (final width in [1400.0, 390.0]) {
      testWidgets('every header fits its column on one line at $width px', (
        tester,
      ) async {
        tester.view
          ..physicalSize = Size(width, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final coupon = ProbedValueMember('Basket.coupon', 'TEN');
        addTearDown(coupon.dispose);
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: width,
              child: SignalsTable(
                [SignalsRow.member(coupon, null)],
                now: Duration.zero,
                timesAt: Duration.zero,
              ),
            ),
          ),
        );
        for (final header in SignalsTable.headersOf(null)) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(header),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: header);
          final line = paragraph.getFullHeightForCaret(
            const TextPosition(offset: 0),
          );
          expect(
            paragraph.size.height,
            lessThanOrEqualTo(line + 1),
            reason: '$header on one line',
          );
          final cell = tester.getSize(
            find
                .ancestor(
                  of: find.text(header),
                  matching: find.byType(SizedBox),
                )
                .first,
          );
          expect(
            paragraph.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(cell.width),
            reason: '$header fits',
          );
        }
        expect(
          find.byType(SingleChildScrollView),
          width < 700 ? findsOneWidget : findsNothing,
          reason: 'a narrow screen scrolls sideways',
        );
      });
    }

    testWidgets('a collection shows its items on a tap', (tester) async {
      final tags = ProbedValueMember('Basket.tags', ['a', 'b', 'c']);
      addTearDown(tags.dispose);
      final expanded = <Object>{};
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => SignalsTable(
              [SignalsRow.member(tags, null)],
              now: Duration.zero,
              timesAt: Duration.zero,
              expanded: expanded,
              onExpand: (node) => setState(() => expanded.add(node)),
            ),
          ),
        ),
      );
      expect(find.text('List(3)'), findsOneWidget);
      expect(find.text("'a', 'b', 'c'"), findsNothing);
      await tester.tap(find.text('List(3)'));
      await tester.pump();
      expect(find.text("'a', 'b', 'c'"), findsOneWidget);
    });
  });

  group('changed and told', () {
    test('a real change, an equal value, and the readers told', () {
      final clock = _Clock();
      final recorder = SignalsDebugRecorder(clock: clock.call);
      final release = recorder.use();
      addTearDown(release);
      final coupon = ProbedValueMember('Basket.coupon', 'A');
      addTearDown(coupon.dispose);
      expect(recorder.changedAt(coupon), isNull);
      expect(recorder.toldAt(coupon), isNull);
      clock.now = const Duration(seconds: 1);
      coupon.write('B');
      expect(recorder.changedAt(coupon), const Duration(seconds: 1));
      expect(recorder.toldAt(coupon), const Duration(seconds: 1));
      // The same value: no change, nobody told.
      clock.now = const Duration(seconds: 5);
      coupon.write('B');
      expect(recorder.changedAt(coupon), const Duration(seconds: 1));
      expect(recorder.toldAt(coupon), const Duration(seconds: 1));
      final row = SignalsRow.member(coupon, recorder);
      expect(SignalsValues.ago(row.changedAt, clock.now), '4.0s');
      expect(row.writes, 2);
      expect(row.ticks, 1);
      expect(row.changes, 1);
    });

    final app = springBootTest(springApplication);

    testWidgets('a queued write changes at once and tells later; the times '
        'move at most once a second', (tester) async {
      final clock = _Clock();
      final recorder = SignalsDebugRecorder(clock: clock.call);
      final beans = app.getBean<SignalBeans>();
      final basket = app.getBean<Basket>()..coupon = 'A';
      final queue = app.getBean<SignalRuntime>().queues.primary..flush();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 900,
            height: 2000,
            child: Builder(
              builder: SignalsDebugSection(beans, recorder: recorder).build,
            ),
          ),
        ),
      );
      clock.now = const Duration(seconds: 2);
      basket.coupon = 'B';
      final member =
          (basket as SignalBeanHolder).signalBean.members['coupon']!
              as ValueMember;
      expect(recorder.changedAt(member), const Duration(seconds: 2));
      expect(recorder.toldAt(member), isNull, reason: 'waits in the queue');
      clock.now = const Duration(milliseconds: 2500);
      queue.flush();
      expect(recorder.changedAt(member), const Duration(seconds: 2));
      expect(recorder.toldAt(member), const Duration(milliseconds: 2500));

      // The tab's times were taken at 0: more than a second ago, so the
      // next refresh moves them; the ones after that only a second later.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('0.5s'), findsOneWidget, reason: 'changed');
      expect(find.text('0.0s'), findsOneWidget, reason: 'told');
      clock.now = const Duration(milliseconds: 3000);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('0.5s'), findsOneWidget, reason: 'not a second yet');
      expect(find.text('1.0s'), findsNothing);
      clock.now = const Duration(milliseconds: 3700);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('1.7s'), findsOneWidget, reason: 'changed');
      expect(find.text('1.2s'), findsOneWidget, reason: 'told');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('the highlight of a row that changed', () {
    Color? colorOf(WidgetTester tester) =>
        (tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byType(SignalsRowHighlight),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration)
            .color;

    testWidgets('lit when it changed, fading out over two seconds; lit '
        'again for a new change; none for an old one', (tester) async {
      const color = Color(0xFF4FC3F7);
      Widget at(Duration? changedAt, Duration now) => _host(
        SignalsRowHighlight(
          changedAt: changedAt,
          now: now,
          color: color,
          child: const SizedBox(width: 10, height: 10),
        ),
      );
      await tester.pumpWidget(at(Duration.zero, Duration.zero));
      expect(colorOf(tester)!.a, closeTo(0.22, 0.01));
      await tester.pump(const Duration(seconds: 1));
      expect(colorOf(tester)!.a, closeTo(0.11, 0.01));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(colorOf(tester), isNull);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: 'no frames');

      // A change half a second ago: lit from three quarters.
      await tester.pumpWidget(
        at(const Duration(seconds: 10), const Duration(milliseconds: 10500)),
      );
      expect(colorOf(tester)!.a, closeTo(0.165, 0.01));
      await tester.pumpAndSettle();
      expect(colorOf(tester), isNull);

      await tester.pumpWidget(
        at(const Duration(seconds: 20), const Duration(seconds: 23)),
      );
      expect(colorOf(tester), isNull);
      await tester.pumpWidget(at(null, const Duration(seconds: 23)));
      expect(colorOf(tester), isNull);
    });
  });
}

final class _Plain {}
