// Spring widgets subscribe to a @ChangeNotifierComponent bean only when
// they read its state: the bean below is proxied like the generator does
// it (a subclass proxy mixing ChangeNotifier in).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_dart/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

@ChangeNotifierComponent()
class Counter {
  int _value = 0;

  int get value => _value;

  void increment() => _value++;

  /// Reads its own getter (through the proxy): no widget's read.
  void incrementBelow(int max) {
    if (value < max) {
      _value++;
    }
  }
}

/// What the generator writes for [Counter].
class _$CounterProxy extends Counter with ChangeNotifier implements Advised {
  ProxyInvoker? _$invoker;

  _$CounterProxy _$advise(ProxyInvoker invoker) {
    _$invoker = invoker;
    return this;
  }

  @override
  Object get aopTarget => this;

  @override
  List<PointcutAdvisor> get aopAdvisors => _$invoker?.advisors ?? const [];

  @override
  void addAdvisor(PointcutAdvisor advisor) => _$invoker!.addAdvisor(advisor);

  @override
  bool removeAdvisor(PointcutAdvisor advisor) =>
      _$invoker!.removeAdvisor(advisor);

  @override
  void addAdvice(MethodInterceptor advice) => _$invoker!.addAdvice(advice);

  @override
  bool removeAdvice(MethodInterceptor advice) =>
      _$invoker!.removeAdvice(advice);

  @override
  void increment() {
    final i = _$invoker;
    if (i == null) {
      super.increment();
    } else {
      i.invoke(this, this, 0, const [], (_) {
        super.increment();
        return null;
      });
    }
  }

  @override
  int get value {
    final i = _$invoker;
    return i == null
        ? super.value
        : i.invoke(this, this, 1, const [], (_) => super.value) as int;
  }

  @override
  void incrementBelow(int max) {
    final i = _$invoker;
    if (i == null) {
      super.incrementBelow(max);
    } else {
      i.invoke(this, this, 2, [max], (args) {
        super.incrementBelow(args[0] as int);
        return null;
      });
    }
  }
}

MethodSignature _signature(String name, MemberKind kind, String returnType) =>
    MethodSignature(
      name: name,
      declaringType: 'Counter',
      targetType: 'Counter',
      declaringTypes: const ['Counter'],
      kind: kind,
      returnType: returnType,
      targetTypes: const ['Counter'],
      targetAnnotations: const [ChangeNotifierComponent()],
      targetAnnotationTypes: const ['ChangeNotifierComponent'],
    );

final builds = <String, int>{};

void _built(String name) => builds[name] = (builds[name] ?? 0) + 1;

/// Reads the count in build: rebuilt on every change.
class CounterValue extends SpringStatelessWidget<(Counter,)> {
  const CounterValue({super.key});

  @override
  Widget build(BuildContext context) {
    _built('value');
    return Text('${beans.$1.value}', textDirection: TextDirection.ltr);
  }
}

/// Only calls a method: never rebuilt by the counter.
class CounterButton extends SpringStatelessWidget<(Counter,)> {
  const CounterButton({this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    _built('button');
    return GestureDetector(
      onTap: beans.$1.increment,
      child: child ?? const Text('+', textDirection: TextDirection.ltr),
    );
  }
}

/// Reads the count only in a `Builder` below it.
class BuilderValue extends SpringStatelessWidget<(Counter,)> {
  const BuilderValue({super.key});

  @override
  Widget build(BuildContext context) {
    _built('builder');
    final (counter,) = beans;
    return Builder(
      builder: (_) =>
          Text('b${counter.value}', textDirection: TextDirection.ltr),
    );
  }
}

/// Reads the count while [show] is on.
class SometimesValue extends SpringStatelessWidget<(Counter,)> {
  const SometimesValue({required this.show, super.key});

  final bool show;

  @override
  Widget build(BuildContext context) => Text(
    show ? 's${beans.$1.value}' : 'hidden',
    textDirection: TextDirection.ltr,
  );
}

class CounterPage extends SpringStatefulWidget<(Counter,)> {
  const CounterPage({required this.read, super.key});

  final bool read;

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends SpringState<CounterPage, (Counter,)> {
  @override
  Widget build(BuildContext context) {
    _built('page');
    final (counter,) = beans;
    return Text(
      widget.read ? 'p${counter.value}' : 'page',
      textDirection: TextDirection.ltr,
    );
  }
}

Type _typeOf<T>() => T;

bool listened(Counter counter) =>
    // ignore: invalid_use_of_protected_member
    (counter as ChangeNotifier).hasListeners;

SpringApplication app() => SpringApplication([
  springBootAutoConfiguration,
  springBootStarterFlutterAutoConfiguration,
  BeanModule('test', [
    BeanDefinition<Counter>(
      name: 'counter',
      types: const [Counter],
      create: (_) => _$CounterProxy(),
      annotations: const [ChangeNotifierComponent()],
      aopProxy: AopProxyFactory.subclass(
        signatures: [
          _signature('increment', MemberKind.method, 'void'),
          _signature('value', MemberKind.getter, 'int'),
          _signature('incrementBelow', MemberKind.method, 'void'),
        ],
        advise: (bean, invoker) =>
            bean is _$CounterProxy ? bean._$advise(invoker) : null,
      ),
    ),
    BeanDefinition<SpringWidgetBindings>(
      name: 'flutterSpringWidgetBindings#test',
      types: const [SpringWidgetBindings],
      create: (_) => SpringWidgetBindings([
        SpringWidgetBinding(
          widget: 'Counter widgets',
          beans: _typeOf<(Counter,)>(),
          types: const [Counter],
          resolve: (f) => (SpringWidgetBinding.bean<Counter>(f),),
          values: (r) => [(r as (Counter,)).$1],
        ),
      ]),
    ),
  ]),
], bannerMode: BannerMode.off);

void main() {
  late ConfigurableApplicationContext context;
  late Counter counter;

  setUp(() async {
    builds.clear();
    context = await app().runAsync(const []);
    counter = context.getBean<Counter>();
  });

  tearDown(() => context.close());

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(SpringScope(applicationContext: context, child: child));

  test('the counter is advised by the reads advice', () {
    expect(counter, isA<Listenable>());
    expect(
      (counter as Advised).aopAdvisors.map((a) => a.advice),
      contains(isA<BeanReadsInterceptor>()),
    );
  });

  testWidgets('a widget that reads the state rebuilds; one that only calls '
      'a method does not', (tester) async {
    await pump(
      tester,
      const Column(children: [CounterValue(), CounterButton()]),
    );
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byType(CounterButton));
    await tester.pump();
    await tester.tap(find.byType(CounterButton));
    await tester.pump();

    expect(find.text('2'), findsOneWidget);
    expect(builds, {'value': 3, 'button': 1});
  });

  testWidgets('a read in a builder below (outside the build) keeps the '
      'widget listening', (tester) async {
    await pump(tester, const BuilderValue());
    expect(find.text('b0'), findsOneWidget);

    counter.increment();
    await tester.pump();

    expect(find.text('b1'), findsOneWidget);
    expect(builds['builder'], 2);
  });

  testWidgets("the bean's own reads in its methods are no widget's reads", (
    tester,
  ) async {
    await pump(tester, const CounterButton());
    counter.incrementBelow(5);
    counter.incrementBelow(5);
    await tester.pump();

    expect(counter.value, 2);
    expect(builds['button'], 1);
  });

  testWidgets('a widget that stops reading stops listening', (tester) async {
    await pump(tester, const SometimesValue(show: true));
    expect(listened(counter), isTrue);

    await pump(tester, const SometimesValue(show: false));
    expect(listened(counter), isFalse);

    counter.increment();
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    await pump(tester, const SometimesValue(show: true));
    expect(find.text('s1'), findsOneWidget);
    expect(listened(counter), isTrue);
  });

  testWidgets('a SpringState: rebuilt only when its build reads', (
    tester,
  ) async {
    await pump(tester, const CounterPage(read: false));
    counter.increment();
    await tester.pump();
    expect(builds['page'], 1);

    await pump(tester, const CounterPage(read: true));
    expect(find.text('p1'), findsOneWidget);
    counter.increment();
    await tester.pump();
    expect(find.text('p2'), findsOneWidget);
    expect(builds['page'], 3);
  });

  testWidgets('removed widgets stop listening', (tester) async {
    await pump(tester, const CounterValue());
    expect(listened(counter), isTrue);
    await pump(tester, const SizedBox());
    expect(listened(counter), isFalse);
  });
}
