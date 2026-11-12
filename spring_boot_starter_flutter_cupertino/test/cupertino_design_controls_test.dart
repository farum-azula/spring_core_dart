// Cupertino's form controls for the widgets that draw a form without
// knowing the design: the text field, the filled button, the error color.
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart';

void main() {
  const controls = CupertinoDesignControls();

  Future<void> pump(
    WidgetTester tester,
    Widget Function(BuildContext context) build, {
    Brightness brightness = Brightness.light,
  }) => tester.pumpWidget(
    CupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      home: CupertinoPageScaffold(
        child: Center(child: Builder(builder: build)),
      ),
    ),
  );

  group('textField', () {
    testWidgets('a CupertinoTextField with what the form knows of it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ada');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      final submitted = <String>[];
      await pump(
        tester,
        (context) => controls.textField(
          context,
          DesignTextField(
            controller: controller,
            label: 'User name',
            focusNode: focus,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: submitted.add,
          ),
        ),
      );
      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.controller, same(controller));
      expect(field.focusNode, same(focus));
      expect(field.placeholder, 'User name');
      expect(field.enabled, isTrue);
      expect(field.autofocus, isTrue);
      expect(field.obscureText, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autofillHints, [AutofillHints.username]);
      expect(field.keyboardType, TextInputType.emailAddress);
      expect(field.textInputAction, TextInputAction.next);
      expect(field.suffix, isNull);
      expect(focus.hasFocus, isTrue);
      await tester.enterText(find.byType(CupertinoTextField), 'grace');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      expect(controller.text, 'grace');
      expect(submitted, ['grace']);
    });

    testWidgets('the error below it, in iOS\'s red at size 13', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        (context) => controls.textField(
          context,
          DesignTextField(
            controller: controller,
            label: 'Password',
            errorText: 'Wrong password',
          ),
        ),
      );
      final error = tester.widget<Text>(find.text('Wrong password'));
      final context = tester.element(find.text('Wrong password'));
      expect(error.style!.fontSize, 13);
      expect(
        error.style!.color,
        CupertinoColors.destructiveRed.resolveFrom(context),
      );
      expect(
        error.style!.fontFamily,
        CupertinoTheme.of(context).textTheme.textStyle.fontFamily,
      );
      expect(
        tester
            .widget<Padding>(
              find
                  .ancestor(
                    of: find.text('Wrong password'),
                    matching: find.byType(Padding),
                  )
                  .first,
            )
            .padding,
        const EdgeInsetsDirectional.only(start: 6, top: 4),
      );
      expect(
        tester.getTopLeft(find.text('Wrong password')).dy,
        greaterThan(tester.getBottomLeft(find.byType(CupertinoTextField)).dy),
      );
    });

    testWidgets('no error text without an error', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        (context) => controls.textField(
          context,
          DesignTextField(controller: controller, label: 'Password'),
        ),
      );
      expect(
        tester.widget<Column>(find.byType(Column).first).children,
        hasLength(1),
      );
    });

    testWidgets('a hidden text has an eye button that shows it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'secret');
      addTearDown(controller.dispose);
      var obscured = true;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: StatefulBuilder(
                builder: (context, setState) => controls.textField(
                  context,
                  DesignTextField(
                    controller: controller,
                    label: 'Password',
                    obscureText: obscured,
                    toggleObscured: () => setState(() => obscured = !obscured),
                    toggleLabel: obscured ? 'Show password' : 'Hide password',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      CupertinoTextField field() =>
          tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
      expect(field().obscureText, isTrue);
      expect(find.byIcon(CupertinoIcons.eye), findsOneWidget);
      expect(find.bySemanticsLabel('Show password'), findsOneWidget);
      final button = tester.widget<CupertinoButton>(
        find.byType(CupertinoButton),
      );
      expect(button.minimumSize, const Size(44, 44));
      expect(button.padding, const EdgeInsets.symmetric(horizontal: 8));
      expect(tester.widget<Icon>(find.byType(Icon)).size, 20);

      await tester.tap(find.byType(CupertinoButton));
      await tester.pump();
      expect(field().obscureText, isFalse);
      expect(find.byIcon(CupertinoIcons.eye_slash), findsOneWidget);
      expect(find.bySemanticsLabel('Hide password'), findsOneWidget);
    });

    testWidgets('a disabled field: no editing, no eye button to press', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        (context) => controls.textField(
          context,
          DesignTextField(
            controller: controller,
            label: 'Password',
            enabled: false,
            obscureText: true,
            toggleObscured: () => fail('pressed'),
          ),
        ),
      );
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField))
            .enabled,
        isFalse,
      );
      expect(
        tester.widget<CupertinoButton>(find.byType(CupertinoButton)).onPressed,
        isNull,
      );
    });
  });

  group('filledButton', () {
    CupertinoButton button(WidgetTester tester) =>
        tester.widget<CupertinoButton>(find.byType(CupertinoButton));

    testWidgets('its label, pressed', (tester) async {
      var pressed = 0;
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          DesignButton(label: 'Sign in', onPressed: () => pressed++),
        ),
      );
      expect(button(tester).child, isA<Text>());
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      // Filled: the theme's primary color behind the label.
      final context = tester.element(find.byType(CupertinoButton));
      expect(
        tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(CupertinoButton),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => box.decoration)
            .whereType<ShapeDecoration>()
            .map((decoration) => decoration.color?.toARGB32()),
        contains(CupertinoTheme.of(context).primaryColor.toARGB32()),
      );
      await tester.tap(find.text('Sign in'));
      expect(pressed, 1);
    });

    testWidgets('busy: an activity indicator in the label\'s place', (
      tester,
    ) async {
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          const DesignButton(label: 'Sign in', onPressed: null, busy: true),
        ),
      );
      expect(button(tester).onPressed, isNull);
      expect(button(tester).child, isA<Semantics>());
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      expect(find.bySemanticsLabel('Sign in'), findsOneWidget);
    });

    testWidgets('with an icon: the icon, a gap, the label', (tester) async {
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          DesignButton(
            label: 'Sign in with GitHub',
            onPressed: () {},
            icon: const Icon(CupertinoIcons.person),
          ),
        ),
      );
      final row = button(tester).child as Row;
      expect(row.mainAxisSize, MainAxisSize.min);
      expect(row.children, hasLength(3));
      expect(row.children[0], isA<Icon>());
      expect(
        row.children[1],
        isA<SizedBox>().having((box) => box.width, 'width', 8),
      );
      expect(row.children[2], isA<Flexible>());
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });

    testWidgets('with an icon, busy: the indicator in the icon\'s place', (
      tester,
    ) async {
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          const DesignButton(
            label: 'Sign in with GitHub',
            onPressed: null,
            busy: true,
            icon: Icon(CupertinoIcons.person),
          ),
        ),
      );
      final row = button(tester).child as Row;
      expect(row.children, hasLength(3));
      expect(row.children[0], isA<CupertinoActivityIndicator>());
      expect(find.byIcon(CupertinoIcons.person), findsNothing);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });

    testWidgets('a label that stays: alone, then after the indicator', (
      tester,
    ) async {
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          DesignButton(
            label: 'Sign in with GitHub',
            onPressed: () {},
            keepsLabel: true,
          ),
        ),
      );
      var row = button(tester).child as Row;
      expect(row.children, hasLength(1));
      expect(row.children.single, isA<Flexible>());

      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          const DesignButton(
            label: 'Sign in with GitHub',
            onPressed: null,
            busy: true,
            keepsLabel: true,
          ),
        ),
      );
      row = button(tester).child as Row;
      expect(row.children, hasLength(3));
      expect(row.children[0], isA<CupertinoActivityIndicator>());
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });
  });

  group('errorColor', () {
    for (final brightness in Brightness.values) {
      testWidgets('iOS\'s destructive red, ${brightness.name}', (tester) async {
        late Color color;
        await pump(tester, (context) {
          color = controls.errorColor(context);
          return const SizedBox();
        }, brightness: brightness);
        expect(
          color.toARGB32(),
          (brightness == Brightness.dark
                  ? CupertinoColors.destructiveRed.darkColor
                  : CupertinoColors.destructiveRed.color)
              .toARGB32(),
        );
      });
    }
  });

  testWidgets('surface: the child as it is', (tester) async {
    const child = Text('form');
    late Widget surface;
    await pump(tester, (context) {
      surface = controls.surface(context, child);
      return surface;
    });
    expect(surface, same(child));
  });
}
