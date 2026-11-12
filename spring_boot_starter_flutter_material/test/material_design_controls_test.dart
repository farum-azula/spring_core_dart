// Material's form controls for the widgets that draw a form without
// knowing the design: the text field, the filled button, the color of an
// error and the Material they need above them.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart';

const controls = MaterialDesignControls();

Future<void> pump(
  WidgetTester tester,
  Widget Function(BuildContext context) build, {
  bool scaffold = true,
  ThemeData? theme,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: scaffold
        ? Scaffold(body: Builder(builder: build))
        : Builder(builder: build),
  ),
);

void main() {
  group('textField', () {
    testWidgets('a TextField with the label, the error and the form\'s '
        'settings', (tester) async {
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
            errorText: 'Required',
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: submitted.add,
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller, same(controller));
      expect(field.focusNode, same(focus));
      expect(field.enabled, isTrue);
      expect(field.autofocus, isTrue);
      expect(field.obscureText, isFalse);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autofillHints, [AutofillHints.username]);
      expect(field.keyboardType, TextInputType.emailAddress);
      expect(field.textInputAction, TextInputAction.next);
      expect(field.decoration!.labelText, 'User name');
      expect(field.decoration!.errorText, 'Required');
      expect(field.decoration!.suffixIcon, isNull);
      expect(find.text('User name'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      expect(submitted, ['ada']);
    });

    testWidgets('a hidden text has a button to show it', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var obscured = true;
      var enabled = true;
      late StateSetter rebuild;
      await pump(
        tester,
        (context) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return controls.textField(
              context,
              DesignTextField(
                controller: controller,
                label: 'Password',
                enabled: enabled,
                obscureText: obscured,
                toggleObscured: () => setState(() => obscured = !obscured),
                toggleLabel: 'Show the password',
              ),
            );
          },
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byTooltip('Show the password'), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isFalse,
      );
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // A disabled field's button does nothing.
      rebuild(() => enabled = false);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).enabled,
        isFalse,
      );
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
    });
  });

  group('filledButton', () {
    testWidgets('a FilledButton with the label', (tester) async {
      var pressed = 0;
      await pump(
        tester,
        (context) => controls.filledButton(
          context,
          DesignButton(label: 'Sign in', onPressed: () => pressed++),
        ),
      );
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(FilledButton));
      expect(pressed, 1);
    });

    testWidgets('busy: a progress indicator named by the label, whatever '
        'keepsLabel says', (tester) async {
      for (final keepsLabel in [false, true]) {
        await pump(
          tester,
          (context) => controls.filledButton(
            context,
            DesignButton(
              label: 'Sign in',
              onPressed: null,
              busy: true,
              keepsLabel: keepsLabel,
            ),
          ),
        );
        expect(find.text('Sign in'), findsNothing);
        final indicator = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(indicator.strokeWidth, 2);
        expect(
          tester.getSize(find.byType(CircularProgressIndicator)),
          const Size.square(18),
        );
        expect(find.bySemanticsLabel('Sign in'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
      }
    });

    testWidgets('with an icon: before the label, the progress indicator in '
        'its place while busy', (tester) async {
      const icon = Icon(Icons.login);
      var busy = false;
      late StateSetter rebuild;
      await pump(
        tester,
        (context) => StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return controls.filledButton(
              context,
              DesignButton(
                label: 'Sign in with GitHub',
                onPressed: busy ? null : () {},
                busy: busy,
                icon: icon,
              ),
            );
          },
        ),
      );
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.login)).dx,
        lessThan(tester.getCenter(find.text('Sign in with GitHub')).dx),
      );

      rebuild(() => busy = true);
      await tester.pump();
      expect(find.byIcon(Icons.login), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });
  });

  testWidgets('errorColor: the error role of Material\'s theme', (
    tester,
  ) async {
    late Color color;
    await pump(
      tester,
      (context) {
        color = controls.errorColor(context);
        return const SizedBox();
      },
      theme: ThemeData(
        colorScheme: const ColorScheme.light(error: Color(0xFF123456)),
      ),
    );
    expect(color, const Color(0xFF123456));
  });

  group('surface', () {
    const child = Text('form');

    testWidgets('a transparent Material where there is none above', (
      tester,
    ) async {
      late Widget surface;
      await pump(tester, scaffold: false, (context) {
        surface = controls.surface(context, child);
        return surface;
      });
      expect(
        surface,
        isA<Material>()
            .having((m) => m.type, 'type', MaterialType.transparency)
            .having((m) => m.child, 'child', same(child)),
      );
      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('the child as it is under a Material', (tester) async {
      late Widget surface;
      await pump(tester, (context) {
        surface = controls.surface(context, child);
        return surface;
      });
      expect(surface, same(child));
    });
  });
}
