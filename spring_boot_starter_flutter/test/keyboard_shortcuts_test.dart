// Keyboard shortcuts: keys from spring.flutter.shortcuts or @Shortcut's
// own, handlers from @Shortcut methods, ShortcutHandler beans and the
// screen's ShortcutHandlers, labels by platform, and the start stopping on
// keys that are no keys.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

final class Calls {
  final list = <String>[];
}

class SearchActions {
  SearchActions(this.calls);

  final Calls calls;

  void open(BuildContext context) =>
      calls.list.add('open ${context.widget.runtimeType}');

  bool help() {
    calls.list.add('help (passes)');
    return false;
  }

  void wrong(String text) {}
}

final class HelpHandler implements ShortcutHandler, Ordered {
  HelpHandler(this.calls);

  final Calls calls;

  @override
  String get action => 'help.show';

  @override
  int get order => 5;

  @override
  bool handle(ShortcutInvocation invocation) {
    calls.list.add('help bean');
    return true;
  }
}

final class NumpadNotation implements ShortcutNotation {
  const NumpadNotation();

  @override
  bool supports(String text) => text == 'the-f9';

  @override
  ShortcutKeys parse(String text, TargetPlatform platform) =>
      const KeyCombinationNotation().parse('f9', platform);
}

BeanDefinition<Object> _actions({
  List<String> keys = const [],
  bool wrong = false,
}) => BeanDefinition<SearchActions>(
  name: 'searchActions',
  types: const [SearchActions],
  create: (r) => SearchActions(r.dependency<Calls>()),
  annotatedMethods: [
    BeanMethod<SearchActions>(
      'open',
      invoke: (bean, arguments) => Function.apply(bean.open, arguments),
      parameterTypes: const [BuildContext],
      annotations: [Shortcut('search.open', keys: keys)],
    ),
    BeanMethod<SearchActions>(
      'help',
      invoke: (bean, arguments) => Function.apply(bean.help, arguments),
      annotations: const [Shortcut('help.show')],
    ),
    if (wrong)
      BeanMethod<SearchActions>(
        'wrong',
        invoke: (bean, arguments) => Function.apply(bean.wrong, arguments),
        parameterTypes: const [String],
        annotations: const [Shortcut('x')],
      ),
  ],
);

SpringApplication _app(
  Map<String, String> properties, {
  List<BeanDefinition<Object>> beans = const [],
}) => SpringApplication(
  [
    BeanModule(
      'test',
      [
        BeanDefinition<Calls>(
          name: 'calls',
          types: const [Calls],
          create: (_) => Calls(),
        ),
        ...beans,
      ],
      resources: {
        'application.properties': EmbeddedResource.text(
          [
            for (final MapEntry(:key, :value) in properties.entries)
              '$key=$value',
          ].join('\n'),
        ),
      },
    ),
  ],
  autoConfigurations: [springBootStarterFlutterAutoConfiguration],
  bannerMode: BannerMode.off,
);

class _Page extends StatelessWidget {
  const _Page({this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const ShortcutLabel('search.open'),
      ?child,
      const Focus(autofocus: true, child: SizedBox(width: 10, height: 10)),
    ],
  );
}

// A text field of the widgets library alone, with the focus.
class _TextField extends StatefulWidget {
  const _TextField();

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditableText(
    controller: _controller,
    focusNode: _focus,
    autofocus: true,
    style: DefaultTextStyle.of(context).style,
    cursorColor: const Color(0xFF000000),
    backgroundCursorColor: const Color(0xFF808080),
  );
}

Future<ApplicationContext> _pump(
  WidgetTester tester,
  SpringApplication application, {
  Widget page = const _Page(),
}) async {
  await tester.pumpWidget(
    SpringApplicationWidget(
      application: () => application,
      failure: (_, error) =>
          Text('failed: $error', textDirection: TextDirection.ltr),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
  return SpringScope.of(tester.element(find.byType(_Page)), listen: false);
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  LogicalKeyboardKey? modifier,
}) async {
  if (modifier != null) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  if (modifier != null) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

void main() {
  testWidgets('configured keys run the @Shortcut method with the focus', (
    tester,
  ) async {
    final context = await _pump(
      tester,
      _app(
        {'spring.flutter.shortcuts.search.open': 'primary+k'},
        beans: [_actions()],
      ),
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyK,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(context.getBean<Calls>().list, ['open Focus']);
    expect(find.text('Ctrl+K'), findsOneWidget);
  });

  testWidgets("@Shortcut's own keys, unless the configuration names some", (
    tester,
  ) async {
    var context = await _pump(
      tester,
      _app(
        const {},
        beans: [
          _actions(keys: ['primary+j']),
        ],
      ),
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyJ,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(context.getBean<Calls>().list, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    context = await _pump(
      tester,
      _app(
        {'spring.flutter.shortcuts.search.open': 'alt+s'},
        beans: [
          _actions(keys: ['primary+j']),
        ],
      ),
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyJ,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyS,
      modifier: LogicalKeyboardKey.altLeft,
    );
    expect(context.getBean<Calls>().list, ['open Focus']);
  });

  testWidgets('handlers in order; false passes on; a list of keys', (
    tester,
  ) async {
    final context = await _pump(
      tester,
      _app(
        {
          'spring.flutter.shortcuts.help.show[0]': 'f1',
          'spring.flutter.shortcuts.help.show[1]': 'the-f9',
        },
        beans: [
          _actions(),
          BeanDefinition<HelpHandler>(
            name: 'helpHandler',
            types: const [HelpHandler, ShortcutHandler, Ordered],
            create: (r) => HelpHandler(r.dependency<Calls>()),
          ),
          BeanDefinition<NumpadNotation>(
            name: 'numpad',
            types: const [NumpadNotation, ShortcutNotation],
            create: (_) => const NumpadNotation(),
          ),
        ],
      ),
    );
    await _press(tester, LogicalKeyboardKey.f1);
    await _press(tester, LogicalKeyboardKey.f9);
    expect(context.getBean<Calls>().list, [
      'help (passes)',
      'help bean',
      'help (passes)',
      'help bean',
    ]);
  });

  testWidgets('the screen first; what it passes on goes to the app', (
    tester,
  ) async {
    final screen = <String>[];
    final context = await _pump(
      tester,
      _app(
        {
          'spring.flutter.shortcuts.search.open': 'primary+k',
          'spring.flutter.shortcuts.editor.save': 'primary+s',
        },
        beans: [_actions()],
      ),
      page: _Page(
        child: ShortcutHandlers(
          handlers: {
            'editor.save': (_) => screen.add('save'),
            'search.open': (_) => false,
          },
          child: const SizedBox(),
        ),
      ),
    );
    // The focus is not below the screen's handlers: only the app's.
    await _press(
      tester,
      LogicalKeyboardKey.keyS,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(screen, isEmpty);
    expect(context.getBean<Calls>().list, isEmpty);

    await tester.pumpWidget(const SizedBox());
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final again = await _pump(
      tester,
      _app(
        {
          'spring.flutter.shortcuts.search.open': 'primary+k',
          'spring.flutter.shortcuts.editor.save': 'primary+s',
        },
        beans: [_actions()],
      ),
      page: _Page(
        child: ShortcutHandlers(
          handlers: {
            'editor.save': (_) => screen.add('save'),
            'search.open': (_) => false,
          },
          child: Focus(
            focusNode: focus,
            autofocus: true,
            child: const SizedBox(),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await _press(
      tester,
      LogicalKeyboardKey.keyS,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyK,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(screen, ['save']);
    expect(again.getBean<Calls>().list, ['open Focus']);
  });

  testWidgets('a plain key types in a text field; Ctrl+K still works', (
    tester,
  ) async {
    final context = await _pump(
      tester,
      _app(
        {
          'spring.flutter.shortcuts.search.open[0]': 'primary+k',
          'spring.flutter.shortcuts.search.open[1]': 'slash',
        },
        beans: [_actions()],
      ),
      page: const _Page(child: _TextField()),
    );
    await tester.showKeyboard(find.byType(EditableText));
    await _press(tester, LogicalKeyboardKey.slash);
    expect(context.getBean<Calls>().list, isEmpty);
    await _press(
      tester,
      LogicalKeyboardKey.keyK,
      modifier: LogicalKeyboardKey.controlLeft,
    );
    expect(context.getBean<Calls>().list, hasLength(1));
  });

  test('labels by platform', () {
    const notations = ShortcutNotations();
    String label(String text, TargetPlatform platform) => notations
        .parse(text, property: 'p', platform: platform)
        .label(platform);
    expect(label('primary+shift+k', TargetPlatform.macOS), '⇧⌘K');
    expect(
      label('primary+shift+k', TargetPlatform.windows),
      'Ctrl+Shift+K',
    );
    expect(label('alt+left', TargetPlatform.linux), 'Alt+←');
    expect(label('char:?', TargetPlatform.iOS), '?');
    expect(
      notations
          .parse('primary+k', property: 'p', platform: TargetPlatform.macOS)
          .activator,
      isA<SingleActivator>().having((a) => a.meta, 'meta', isTrue),
    );
  });

  testWidgets('keys that are no keys stop the start, naming the property', (
    tester,
  ) async {
    for (final (value, problem) in [
      ('primary+moon', "'moon' is no key"),
      ('hyper+k', "'hyper' is no modifier"),
      ('char:ab', 'char: takes one character'),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        SpringApplicationWidget(
          application: () => _app(
            {'spring.flutter.shortcuts.search.open': value},
            beans: [_actions()],
          ),
          failure: (_, error) =>
              Text('failed: $error', textDirection: TextDirection.ltr),
          home: const _Page(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('spring.flutter.shortcuts.search.open'),
        findsOneWidget,
        reason: value,
      );
      expect(find.textContaining(problem), findsOneWidget, reason: value);
    }
  });

  testWidgets('a @Shortcut method of another signature stops the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => _app(const {}, beans: [_actions(wrong: true)]),
        failure: (_, error) =>
            Text('failed: $error', textDirection: TextDirection.ltr),
        home: const _Page(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid @Shortcut method'), findsOneWidget);
  });

  testWidgets('on macOS primary is ⌘', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final context = await _pump(
      tester,
      _app(
        {'spring.flutter.shortcuts.search.open': 'primary+k'},
        beans: [_actions()],
      ),
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyK,
      modifier: LogicalKeyboardKey.metaLeft,
    );
    expect(context.getBean<Calls>().list, hasLength(1));
    expect(find.text('⌘K'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
