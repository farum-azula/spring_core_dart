// The login screens: LoginForm on the AuthenticationManager (checks,
// progress, errors that never say which part was wrong, the context set,
// the event), OAuth2LoginButton on the login service (labels, progress,
// cancel, errors), the brand buttons (their rules: sizes, colours, texts,
// logos), in the three designs, with semantics, RTL and large text.
//
// The widgets know no design library. In an app of type `material` or
// `cupertino` the controls of its design starter draw them (the
// `DesignScope` of the starter's app widget); in an app without a design
// library they are the plain widgets. So the Material and Cupertino apps
// here are the ones the starters build.
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:spring_boot_starter_flutter_cupertino/spring_boot_starter_flutter_cupertino.dart'
    show CupertinoDesignControls;
import 'package:spring_boot_starter_flutter_material/spring_boot_starter_flutter_material.dart'
    show MaterialDesignControls;
import 'package:spring_boot_starter_flutter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/brand_buttons.dart'
    show BrandButton;
import 'package:spring_boot_starter_flutter_security/src/screens/brand_logos.dart';
import 'package:spring_boot_starter_flutter_security/src/screens/login_design.dart'
    show LoginSpinner, loginColorScheme;
import 'package:spring_boot_starter_flutter_security/src/screens/login_form.dart'
    show PlainLoginButton;

import 'support/design_starters.dart';

/// Checks `ada` / `secret`; a gate holds the answer back when set.
class _Manager implements AuthenticationManager {
  final requests = <Authentication>[];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<Authentication> authenticate(Authentication authentication) async {
    requests.add(authentication);
    await gate?.future;
    if (failure case final failure?) {
      throw failure;
    }
    if (authentication.name != 'ada' ||
        authentication.credentials != 'secret') {
      throw BadCredentialsException();
    }
    return UsernamePasswordAuthenticationToken.authenticated('ada', null, [
      SimpleGrantedAuthority('ROLE_USER'),
    ]);
  }
}

/// Logs in as the registration's id; a gate holds the answer back.
class _LoginService implements OAuth2LoginService {
  final logins = <(String, Map<String, String>)>[];
  Completer<void>? gate;
  Object? failure;

  @override
  Future<Authentication?> login(
    String registrationId, {
    Map<String, String> additionalParameters = const {},
  }) async {
    logins.add((registrationId, additionalParameters));
    await gate?.future;
    if (failure case final failure?) {
      throw failure;
    }
    return TestingAuthenticationToken(registrationId, null);
  }

  @override
  Authentication? get authentication => null;

  @override
  Stream<Authentication?> get authenticationChanges => const Stream.empty();

  @override
  bool get isLoggedIn => false;

  @override
  Future<void> logout({
    bool endSession = false,
    Uri? postLogoutRedirectUri,
  }) async {}

  @override
  Future<Authentication?> restore() async => null;
}

class _Events implements GenericApplicationListener {
  final received = <Object>[];

  @override
  bool supportsEvent(Object event) =>
      event is InteractiveAuthenticationSuccessEvent;

  @override
  void onApplicationEvent(Object event) => received.add(event);
}

/// [child] on a page of the app widget that the application above builds
/// (`spring.flutter.app.type`): the Material starter's `MaterialApp` under
/// the application the tests start by default.
Widget _material(Widget child, {TextDirection? direction}) => SpringApp(
  home: Scaffold(
    body: Directionality(
      textDirection: direction ?? TextDirection.ltr,
      child: ListView(padding: const EdgeInsets.all(16), children: [child]),
    ),
  ),
);

/// A `MaterialApp` of the test's own, with Material's controls given the
/// way the Material starter's app gives them.
Widget _ownMaterial({
  required Widget home,
  Locale? locale,
  Iterable<Locale> supportedLocales = const [Locale('en')],
  Iterable<LocalizationsDelegate<Object?>>? localizationsDelegates,
}) => MaterialApp(
  locale: locale,
  supportedLocales: supportedLocales,
  localizationsDelegates: localizationsDelegates,
  builder: (context, child) => DesignScope(
    controls: const MaterialDesignControls(),
    textStyle: (context, style) => null,
    selectable: (context, child) => SelectionArea(child: child),
    child: child!,
  ),
  home: home,
);

/// A `WidgetsApp` of the test's own: no design library.
Widget _ownWidgets(Widget home) => WidgetsApp(
  color: const Color(0xFF6750A4),
  textStyle: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, _, _) => builder(context),
  ),
  home: home,
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  // An application of type `material` with both design starters, one of
  // type `cupertino` with Cupertino's, and one without a design library.
  late ConfigurableApplicationContext context;
  late ConfigurableApplicationContext cupertinoContext;
  late ConfigurableApplicationContext plainContext;
  // Starts another application of [type] with [starters], as those above.
  late Future<ConfigurableApplicationContext> Function(
    String type,
    DesignStarters starters,
  )
  startApplication;
  late _Manager manager;
  late _Events events;

  setUp(() async {
    SecurityContextHolder.clearContext();
    manager = _Manager();
    events = _Events();
    final messages = StaticMessageSource()
      ..addMessages({
        'login-form.username': 'Nom',
        'login-button.google.continue': 'Continuer avec Google',
      }, 'fr');
    Future<ConfigurableApplicationContext> start(
      String type,
      DesignStarters starters,
    ) => SpringApplication(
      [
        BeanModule('loginScreensTest', [
          BeanDefinition<AuthenticationManager>(
            name: 'authenticationManager',
            types: const [AuthenticationManager],
            create: (_) => manager,
          ),
          BeanDefinition<MessageSource>(
            name: 'messageSource',
            types: const [MessageSource],
            create: (_) => messages,
          ),
        ]),
      ],
      // The security core's beans only: a registration property would
      // make this package's login beans want a provider. The Flutter
      // starter and the design starters build the app widget.
      autoConfigurations: [
        springSecurityCoreAutoConfiguration,
        springBootStarterFlutterAutoConfiguration,
        ...starters.autoConfigurations,
      ],
      autoConfigurationMetadata: starters.metadata,
      listeners: [events],
      defaultProperties: {
        'spring.flutter.app.type': type,
        // A widget test has no directories to keep the chosen theme in.
        'spring.flutter.theme.remember': 'false',
        'spring.security.oauth2.client.registration.keycloak.client-name':
            'Neon SSO',
      },
      bannerMode: BannerMode.off,
    ).runAsync(const []);
    startApplication = start;
    context = await start('material', DesignStarters.both);
    cupertinoContext = await start('cupertino', DesignStarters.onlyCupertino);
    plainContext = await start('widgets', DesignStarters.none);
  });

  tearDown(() async {
    await context.closeAsync();
    await cupertinoContext.closeAsync();
    await plainContext.closeAsync();
    SecurityContextHolder.clearContext();
    debugDefaultTargetPlatformOverride = null;
  });

  Widget spring(Widget app) =>
      SpringScope(applicationContext: context, child: app);

  // [home] in the Cupertino starter's `CupertinoApp`.
  Widget cupertino(Widget home) => SpringScope(
    applicationContext: cupertinoContext,
    child: SpringApp(home: home),
  );

  // [home] in the Flutter starter's `WidgetsApp`, in an application
  // without a design starter.
  Widget plain(Widget home) => SpringScope(
    applicationContext: plainContext,
    child: SpringApp(home: home),
  );

  group('LoginDesign', () {
    // The design the login widgets find below [app], and its controls.
    Future<(LoginDesign, DesignControls?)> designIn(
      WidgetTester tester,
      Widget Function(Widget home) app,
    ) async {
      late LoginDesign design;
      DesignControls? controls;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) {
              design = LoginDesign.of(context);
              controls = design.controlsOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return (design, controls);
    }

    testWidgets("app below a design starter's app, with its controls", (
      tester,
    ) async {
      var (design, controls) = await designIn(
        tester,
        (home) => spring(SpringApp(home: home)),
      );
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(design, LoginDesign.app);
      expect(controls, isA<MaterialDesignControls>());

      (design, controls) = await designIn(tester, cupertino);
      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(design, LoginDesign.app);
      expect(controls, isA<CupertinoDesignControls>());
    });

    testWidgets('widgets in an app without a design library', (tester) async {
      final (design, controls) = await designIn(tester, plain);
      expect(find.byType(WidgetsApp), findsOneWidget);
      expect(find.byType(MaterialApp), findsNothing);
      expect(find.byType(CupertinoApp), findsNothing);
      expect(design, LoginDesign.widgets);
      expect(controls, isNull);
    });

    testWidgets("an app widget of the app's own: the controls of its "
        "DesignScope, else those of the design starter whose app it is, "
        'else widgets', (tester) async {
      // Its own DesignScope with controls: those.
      var (design, controls) = await designIn(
        tester,
        (home) => spring(_ownMaterial(home: home)),
      );
      expect(design, LoginDesign.app);
      expect(controls, isA<MaterialDesignControls>());

      // No DesignScope, or one for the text styles only: the controls of
      // the starter whose app it is. With both starters a MaterialApp gets
      // Material's, though it has Cupertino's localizations too.
      Widget textStylesOnly(Widget home) => MaterialApp(
        builder: (context, child) => DesignScope(
          textStyle: (context, style) => null,
          selectable: (context, child) => child,
          child: child!,
        ),
        home: home,
      );
      for (final (label, app, expected) in [
        (
          'MaterialApp',
          (Widget home) => MaterialApp(home: home),
          isA<MaterialDesignControls>(),
        ),
        (
          'CupertinoApp',
          (Widget home) => CupertinoApp(home: home),
          isA<CupertinoDesignControls>(),
        ),
        ('text styles only', textStylesOnly, isA<MaterialDesignControls>()),
      ]) {
        (design, controls) = await designIn(
          tester,
          (home) => spring(app(home)),
        );
        expect(design, LoginDesign.app, reason: label);
        expect(controls, expected, reason: label);
      }

      // The Cupertino starter alone: a CupertinoApp gets Cupertino's.
      (design, controls) = await designIn(
        tester,
        (home) => SpringScope(
          applicationContext: cupertinoContext,
          child: CupertinoApp(home: home),
        ),
      );
      expect(design, LoginDesign.app);
      expect(controls, isA<CupertinoDesignControls>());

      // The Cupertino starter alone: a MaterialApp, which has Cupertino's
      // localizations too, is not Cupertino's app: plain widgets.
      (design, controls) = await designIn(
        tester,
        (home) => SpringScope(
          applicationContext: cupertinoContext,
          child: MaterialApp(home: home),
        ),
      );
      expect(design, LoginDesign.widgets);
      expect(controls, isNull);

      // The Material starter alone: a MaterialApp gets Material's, a
      // CupertinoApp, whose starter is not there, plain widgets.
      final materialContext = await startApplication(
        'material',
        DesignStarters.onlyMaterial,
      );
      addTearDown(materialContext.closeAsync);
      (design, controls) = await designIn(
        tester,
        (home) => SpringScope(
          applicationContext: materialContext,
          child: MaterialApp(home: home),
        ),
      );
      expect(design, LoginDesign.app);
      expect(controls, isA<MaterialDesignControls>());
      (design, controls) = await designIn(
        tester,
        (home) => SpringScope(
          applicationContext: materialContext,
          child: CupertinoApp(home: home),
        ),
      );
      expect(design, LoginDesign.widgets);
      expect(controls, isNull);

      // No design starter: plain widgets in any of them; a WidgetsApp has
      // no design whatever the starters.
      for (final (label, application, app) in [
        (
          'MaterialApp',
          plainContext,
          (Widget home) => MaterialApp(home: home),
        ),
        (
          'CupertinoApp',
          plainContext,
          (Widget home) => CupertinoApp(home: home),
        ),
        ('WidgetsApp', plainContext, _ownWidgets),
        ('WidgetsApp, both starters', context, _ownWidgets),
      ]) {
        (design, controls) = await designIn(
          tester,
          (home) =>
              SpringScope(applicationContext: application, child: app(home)),
        );
        expect(design, LoginDesign.widgets, reason: label);
        expect(controls, isNull, reason: label);
      }
    });

    testWidgets("a LoginForm in an app widget of the app's own draws the "
        "controls of its design's starter", (tester) async {
      await tester.pumpWidget(
        spring(MaterialApp(home: const Scaffold(body: LoginForm()))),
      );
      expect(_field('User name'), findsOneWidget);
      expect(_field('Password'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);

      await tester.pumpWidget(
        SpringScope(
          applicationContext: cupertinoContext,
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: Center(child: LoginForm())),
          ),
        ),
      );
      expect(find.byType(CupertinoTextField), findsNWidgets(2));
      expect(find.byType(TextField), findsNothing);

      await tester.pumpWidget(
        SpringScope(
          applicationContext: plainContext,
          child: MaterialApp(home: const Scaffold(body: LoginForm())),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CupertinoTextField), findsNothing);
      expect(find.byType(EditableText), findsNWidgets(2));
    });

    testWidgets('no app at all: widgets', (tester) async {
      final (design, controls) = await designIn(
        tester,
        (home) => Directionality(textDirection: TextDirection.ltr, child: home),
      );
      expect(design, LoginDesign.widgets);
      expect(controls, isNull);
    });

    testWidgets('widgets has no controls, in a Material app too', (
      tester,
    ) async {
      late DesignControls? ofWidgets;
      late DesignControls? ofApp;
      await tester.pumpWidget(
        spring(
          SpringApp(
            home: Builder(
              builder: (context) {
                ofWidgets = LoginDesign.widgets.controlsOf(context);
                ofApp = LoginDesign.app.controlsOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(ofWidgets, isNull);
      expect(ofApp, isA<MaterialDesignControls>());
    });
  });

  group('LoginForm', () {
    testWidgets('empty fields are checked before anything is asked', (
      tester,
    ) async {
      await tester.pumpWidget(spring(_material(const LoginForm())));
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();

      expect(find.text('Enter your user name'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(manager.requests, isEmpty);
    });

    testWidgets(
      'logs in: the trimmed name, the context set, the event, onSuccess',
      (tester) async {
        Authentication? succeeded;
        await tester.pumpWidget(
          spring(_material(LoginForm(onSuccess: (user) => succeeded = user))),
        );
        await tester.enterText(_field('User name'), '  ada ');
        await tester.enterText(_field('Password'), 'secret');
        await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
        await tester.pumpAndSettle();

        final request = manager.requests.single;
        expect(request, isA<UsernamePasswordAuthenticationToken>());
        expect(request.name, 'ada'); // trimmed, as Spring's form login
        expect(succeeded?.name, 'ada');
        expect(SecurityContextHolder.getContext().authentication?.name, 'ada');
        expect(
          events.received.single,
          isA<InteractiveAuthenticationSuccessEvent>(),
        );
      },
    );

    testWidgets('a wrong password, an unknown user, a locked account: '
        'the same text, the password cleared', (tester) async {
      final errors = <Object>[];
      await tester.pumpWidget(
        spring(_material(LoginForm(onError: errors.add))),
      );
      for (final failure in <Object?>[
        null, // the manager's BadCredentialsException
        UsernameNotFoundException('bob'),
        LockedException('locked'),
      ]) {
        manager.failure = failure;
        await tester.enterText(_field('User name'), 'bob');
        await tester.enterText(_field('Password'), 'guess');
        await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
        await tester.pumpAndSettle();

        expect(find.text('Wrong user name or password'), findsOneWidget);
        expect(
          tester.widget<TextField>(_field('Password')).controller!.text,
          isEmpty,
        );
        expect(find.text('guess'), findsNothing);
      }
      expect(errors, hasLength(3));
      expect(SecurityContextHolder.getContext().authentication, isNull);
    });

    testWidgets('a service failure says the login could not be checked', (
      tester,
    ) async {
      manager.failure = AuthenticationServiceException('down');
      await tester.pumpWidget(spring(_material(const LoginForm())));
      await tester.enterText(_field('User name'), 'ada');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(
        find.text('The login could not be checked. Try again later.'),
        findsOneWidget,
      );
      expect(find.text('Wrong user name or password'), findsNothing);
    });

    testWidgets('shows progress and locks the form while the login runs', (
      tester,
    ) async {
      manager.gate = Completer();
      await tester.pumpWidget(spring(_material(const LoginForm())));
      await tester.enterText(_field('User name'), 'ada');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(_field('Password')).enabled, isFalse);
      // A second press does not log in twice.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(manager.requests, hasLength(1));

      manager.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Enter moves to the password, Enter there submits', (
      tester,
    ) async {
      await tester.pumpWidget(spring(_material(const LoginForm())));
      await tester.enterText(_field('User name'), 'ada');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      final password = tester.widget<TextField>(_field('Password'));
      expect(password.focusNode!.hasFocus, isTrue);

      await tester.enterText(_field('Password'), 'secret');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(manager.requests.single.name, 'ada');
    });

    testWidgets('autofill hints, an obscured password with a toggle', (
      tester,
    ) async {
      await tester.pumpWidget(spring(_material(const LoginForm())));
      final username = tester.widget<TextField>(_field('User name'));
      var password = tester.widget<TextField>(_field('Password'));
      expect(username.autofillHints, [AutofillHints.username]);
      expect(password.autofillHints, [AutofillHints.password]);
      expect(password.obscureText, isTrue);
      expect(find.byType(AutofillGroup), findsOneWidget);

      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      password = tester.widget<TextField>(_field('Password'));
      expect(password.obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('labels from the app messages, or given', (tester) async {
      // MaterialApp sets its own locale (en); the messages are read in
      // it, so the French text needs a French app.
      await tester.pumpWidget(
        spring(
          _ownMaterial(
            locale: const Locale('fr'),
            supportedLocales: const [Locale('fr')],
            localizationsDelegates: const [
              _FrenchMaterial.delegate,
              _FrenchCupertino.delegate,
            ],
            home: const Scaffold(body: LoginForm(submitLabel: 'Entrer')),
          ),
        ),
      );
      expect(_field('Nom'), findsOneWidget);
      expect(_field('Password'), findsOneWidget); // English default
      expect(find.widgetWithText(FilledButton, 'Entrer'), findsOneWidget);
    });

    testWidgets('authenticate replaces the manager; no context set by it', (
      tester,
    ) async {
      final calls = <(String, String)>[];
      Authentication? succeeded = TestingAuthenticationToken('x', null);
      await tester.pumpWidget(
        spring(
          _material(
            LoginForm(
              authenticate: (username, password) async {
                calls.add((username, password));
                return null;
              },
              onSuccess: (user) => succeeded = user,
            ),
          ),
        ),
      );
      await tester.enterText(_field('User name'), 'ada');
      await tester.enterText(_field('Password'), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();

      expect(calls, [('ada', 'secret')]);
      expect(manager.requests, isEmpty);
      expect(succeeded, isNull);
      expect(SecurityContextHolder.getContext().authentication, isNull);
      expect(events.received, isEmpty);
    });

    testWidgets('in a CupertinoApp: Cupertino fields and button', (
      tester,
    ) async {
      await tester.pumpWidget(
        cupertino(
          const CupertinoPageScaffold(child: SafeArea(child: LoginForm())),
        ),
      );
      expect(find.byType(CupertinoApp), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNWidgets(2));
      expect(find.byType(TextField), findsNothing);

      final fields = find.byType(CupertinoTextField);
      await tester.enterText(fields.first, 'ada');
      await tester.enterText(fields.last, 'secret');
      expect(
        tester.widget<CupertinoTextField>(fields.last).obscureText,
        isTrue,
      );
      await tester.tap(find.widgetWithText(CupertinoButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(SecurityContextHolder.getContext().authentication?.name, 'ada');
    });

    testWidgets('in a WidgetsApp: plain fields, no Material needed', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(
          _ownWidgets(
            const Padding(padding: EdgeInsets.all(16), child: LoginForm()),
          ),
        ),
      );
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.byType(Material), findsNothing);

      await tester.tap(find.text('Log in'));
      await tester.pump();
      expect(find.text('Enter your user name'), findsOneWidget);

      final fields = find.byType(EditableText);
      await tester.enterText(fields.first, 'ada');
      await tester.enterText(fields.last, 'secret');
      await tester.tap(find.text('Show password'));
      await tester.pump();
      expect(tester.widget<EditableText>(fields.last).obscureText, isFalse);
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(SecurityContextHolder.getContext().authentication?.name, 'ada');
    });

    testWidgets('in a Material app: the look of the old Material design', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      manager.gate = Completer();
      // A page without a Scaffold: the form brings the Material its
      // fields need.
      await tester.pumpWidget(
        spring(
          SpringApp(
            home: Builder(
              builder: (context) => ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: const LoginForm(),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(LoginForm),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .type,
        MaterialType.transparency,
      );
      expect(
        find.ancestor(
          of: find.byType(LoginForm),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(CupertinoTextField), findsNothing);
      final username = tester.widget<TextField>(_field('User name'));
      expect(username.autocorrect, isFalse);
      expect(username.enableSuggestions, isFalse);
      expect(username.decoration!.suffixIcon, isNull);
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);

      // The checks: each error in its field's decoration.
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();
      expect(
        tester.widget<TextField>(_field('User name')).decoration!.errorText,
        'Enter your user name',
      );
      expect(
        tester.widget<TextField>(_field('Password')).decoration!.errorText,
        'Enter your password',
      );

      // While the login runs: a small spinner in the button, which still
      // says what it is.
      await tester.enterText(_field('User name'), 'bob');
      await tester.enterText(_field('Password'), 'guess');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();
      final spinner = find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      );
      expect(tester.getSize(spinner), const Size.square(18));
      expect(
        tester.widget<CircularProgressIndicator>(spinner).strokeWidth,
        2,
      );
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.text('Log in'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.bySemanticsLabel('Log in'),
        ),
        findsOneWidget,
      );

      // The refusal in the theme's error color.
      manager.gate!.complete();
      await tester.pumpAndSettle();
      final error = find.text('Wrong user name or password');
      expect(
        tester.widget<Text>(error).style!.color,
        Theme.of(tester.element(error)).colorScheme.error,
      );
      semantics.dispose();
    });

    testWidgets('in a Cupertino app: the look of the old Cupertino design', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      manager.gate = Completer();
      await tester.pumpWidget(
        cupertino(
          const CupertinoPageScaffold(child: SafeArea(child: LoginForm())),
        ),
      );
      expect(find.byType(Material), findsNothing);
      final fields = find.byType(CupertinoTextField);
      // The labels are the fields' placeholders.
      expect(
        tester.widget<CupertinoTextField>(fields.first).placeholder,
        ('User name'),
      );
      expect(
        tester.widget<CupertinoTextField>(fields.last).placeholder,
        'Password',
      );
      expect(tester.widget<CupertinoTextField>(fields.first).suffix, isNull);
      expect(tester.widget<CupertinoTextField>(fields.first).autofillHints, [
        AutofillHints.username,
      ]);
      expect(tester.widget<CupertinoTextField>(fields.last).autofillHints, [
        AutofillHints.password,
      ]);

      // The eye shows and hides the password, and says so to a screen
      // reader.
      Finder toggle(String label) => find.ancestor(
        of: find.bySubtype<Icon>(),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == label &&
              (widget.properties.button ?? false),
        ),
      );
      expect(find.byIcon(CupertinoIcons.eye), findsOneWidget);
      expect(toggle('Show password'), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.eye));
      await tester.pump();
      expect(
        tester.widget<CupertinoTextField>(fields.last).obscureText,
        (isFalse),
      );
      expect(find.byIcon(CupertinoIcons.eye_slash), findsOneWidget);
      expect(toggle('Hide password'), findsOneWidget);

      // The checks: each error below its field, in iOS's red.
      await tester.tap(find.widgetWithText(CupertinoButton, 'Log in'));
      await tester.pump();
      final required = find.text('Enter your user name');
      final red = CupertinoColors.destructiveRed.resolveFrom(
        tester.element(required),
      );
      expect(tester.widget<Text>(required).style!.color, red);
      expect(tester.widget<Text>(required).style!.fontSize, 13);
      expect(
        tester.getTopLeft(required).dy,
        greaterThan(tester.getBottomLeft(fields.first).dy),
      );
      expect(
        tester.getTopLeft(required).dy,
        lessThan(tester.getTopLeft(fields.last).dy),
      );
      expect(find.text('Enter your password'), findsOneWidget);

      // While the login runs: the activity indicator in place of the
      // button's text, the button still saying what it is.
      await tester.enterText(fields.first, 'bob');
      await tester.enterText(fields.last, 'guess');
      await tester.tap(find.widgetWithText(CupertinoButton, 'Log in'));
      await tester.pump();
      final button = find.ancestor(
        of: find.byType(CupertinoActivityIndicator),
        matching: find.byType(CupertinoButton),
      );
      expect(button, findsOneWidget);
      expect(tester.widget<CupertinoButton>(button).onPressed, isNull);
      expect(
        find.descendant(of: button, matching: find.text('Log in')),
        findsNothing,
      );
      expect(
        find.descendant(of: button, matching: find.bySemanticsLabel('Log in')),
        findsOneWidget,
      );
      expect(tester.widget<CupertinoTextField>(fields.last).enabled, isFalse);

      manager.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
      final refused = find.text('Wrong user name or password');
      expect(tester.widget<Text>(refused).style!.color, red);
      expect(
        tester.widget<CupertinoTextField>(fields.last).controller!.text,
        (isEmpty),
      );
      semantics.dispose();
    });

    testWidgets('without a design starter: the plain design', (tester) async {
      manager.gate = Completer();
      await tester.pumpWidget(
        plain(const Padding(padding: EdgeInsets.all(16), child: LoginForm())),
      );
      expect(find.byType(WidgetsApp), findsOneWidget);
      expect(find.byType(Material), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(CupertinoTextField), findsNothing);
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.byType(PlainLoginButton), findsOneWidget);
      // The labels above the fields, the toggle as a text.
      expect(find.text('User name'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Show password'), findsOneWidget);

      await tester.tap(find.text('Log in'));
      await tester.pump();
      final colors = loginColorScheme(tester.element(find.byType(LoginForm)));
      expect(
        colors,
        SpringTheme.of(tester.element(find.byType(LoginForm))).colorScheme,
      );
      expect(
        tester.widget<Text>(find.text('Enter your user name')).style!.color,
        colors.error,
      );

      final fields = find.byType(EditableText);
      await tester.enterText(fields.first, 'bob');
      await tester.enterText(fields.last, 'guess');
      await tester.tap(find.text('Log in'));
      await tester.pump();
      // The spinner drawn by the starter, in place of the text.
      expect(
        find.descendant(
          of: find.byType(PlainLoginButton),
          matching: find.byType(LoginSpinner),
        ),
        findsOneWidget,
      );
      expect(find.text('Log in'), findsNothing);
      expect(tester.widget<EditableText>(fields.last).readOnly, isTrue);

      manager.gate!.complete();
      // The spinner turns for ever: no settling while it shows.
      await tester.pump();
      await tester.pump();
      expect(find.byType(LoginSpinner), findsNothing);
      expect(
        tester
            .widget<Text>(find.text('Wrong user name or password'))
            .style!
            .color,
        colors.error,
      );
      expect(tester.widget<EditableText>(fields.last).controller.text, isEmpty);
    });

    testWidgets('design: the plain widgets in a Material app; app without '
        'a design library is the plain design', (tester) async {
      await tester.pumpWidget(
        spring(_material(const LoginForm(design: LoginDesign.widgets))),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.byType(PlainLoginButton), findsOneWidget);

      await tester.pumpWidget(
        plain(
          const Padding(
            padding: EdgeInsets.all(16),
            child: LoginForm(design: LoginDesign.app),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(EditableText), findsNWidgets(2));
      expect(find.byType(PlainLoginButton), findsOneWidget);
    });

    testWidgets('semantics: labelled fields, the toggle, the button', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(spring(_material(const LoginForm())));
      expect(
        tester.getSemantics(find.byType(FilledButton)),
        matchesSemantics(
          label: 'Log in',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byType(IconButton)).tooltip,
        'Show password',
      );
      expect(find.bySemanticsLabel('User name'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('right to left: the toggle on the left of the field', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(_material(const LoginForm(), direction: TextDirection.rtl)),
      );
      final field = tester.getRect(_field('Password'));
      final toggle = tester.getCenter(find.byTooltip('Show password'));
      expect(toggle.dx, lessThan(field.center.dx));
    });

    testWidgets('twice the text size: no overflow', (tester) async {
      await tester.pumpWidget(
        spring(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: _material(const LoginForm()),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('OAuth2LoginButton', () {
    testWidgets('label: client-name, a common provider, else the id', (
      tester,
    ) async {
      final service = _LoginService();
      await tester.pumpWidget(
        spring(
          _material(
            Column(
              children: [
                OAuth2LoginButton('keycloak', loginService: service),
                OAuth2LoginButton('github', loginService: service),
                OAuth2LoginButton('corp', loginService: service),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Sign in with Neon SSO'), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(find.text('Sign in with corp'), findsOneWidget);
    });

    testWidgets('logs in with the registration, shows progress meanwhile', (
      tester,
    ) async {
      final service = _LoginService()..gate = Completer();
      Authentication? succeeded;
      await tester.pumpWidget(
        spring(
          _material(
            OAuth2LoginButton(
              'keycloak',
              loginService: service,
              additionalParameters: const {'prompt': 'login'},
              icon: const Icon(Icons.key),
              onSuccess: (user) => succeeded = user,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(OAuth2LoginButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.key), findsNothing);
      await tester.tap(find.byType(OAuth2LoginButton), warnIfMissed: false);

      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(service.logins.single.$1, 'keycloak');
      expect(service.logins.single.$2, {'prompt': 'login'});
      expect(succeeded?.name, 'keycloak');
      expect(find.byIcon(Icons.key), findsOneWidget);
    });

    testWidgets('the user closing the window is no error', (tester) async {
      final service = _LoginService()
        ..failure = AuthorizationCancelledException();
      final errors = <Object>[];
      await tester.pumpWidget(
        spring(
          _material(
            OAuth2LoginButton(
              'keycloak',
              loginService: service,
              onError: errors.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(OAuth2LoginButton));
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('other failures go to onError, else to FlutterError', (
      tester,
    ) async {
      final service = _LoginService()
        ..failure = OAuth2AuthenticationException(
          OAuth2Error('access_denied'),
        );
      final errors = <Object>[];
      await tester.pumpWidget(
        spring(
          _material(
            OAuth2LoginButton(
              'keycloak',
              loginService: service,
              onError: errors.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(OAuth2LoginButton));
      await tester.pumpAndSettle();
      expect(errors.single, isA<OAuth2AuthenticationException>());

      await tester.pumpWidget(
        spring(_material(OAuth2LoginButton('github', loginService: service))),
      );
      await tester.tap(find.byType(OAuth2LoginButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<OAuth2AuthenticationException>());
    });

    testWidgets('the login function replaces the service', (tester) async {
      final ids = <String>[];
      await tester.pumpWidget(
        spring(
          _material(
            OAuth2LoginButton(
              'keycloak',
              label: 'SSO',
              login: (id) async {
                ids.add(id);
                return null;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('SSO'));
      await tester.pumpAndSettle();
      expect(ids, ['keycloak']);
    });

    testWidgets('in a Material app: a filled button; the spinner takes the '
        "text's place, or the icon's", (tester) async {
      final semantics = tester.ensureSemantics();
      final service = _LoginService()..gate = Completer();
      await tester.pumpWidget(
        spring(
          _material(
            Column(
              children: [
                OAuth2LoginButton('keycloak', loginService: service),
                OAuth2LoginButton(
                  'github',
                  loginService: service,
                  icon: const Icon(Icons.key),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNWidgets(2));
      expect(find.byType(PlainLoginButton), findsNothing);
      final plain = find.widgetWithText(FilledButton, 'Sign in with Neon SSO');
      final withIcon = find.ancestor(
        of: find.byIcon(Icons.key),
        matching: find.bySubtype<FilledButton>(),
      );
      expect(plain, findsOneWidget);
      expect(withIcon, findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.key)).dx,
        lessThan(tester.getCenter(find.text('Sign in with GitHub')).dx),
      );

      // Without an icon the spinner replaces the text.
      await tester.tap(plain);
      await tester.pump();
      final busy = find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.bySubtype<FilledButton>(),
      );
      expect(busy, findsOneWidget);
      expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      expect(find.text('Sign in with Neon SSO'), findsNothing);
      expect(find.bySemanticsLabel('Sign in with Neon SSO'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size.square(18),
      );
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sign in with Neon SSO'), findsOneWidget);

      // With an icon the spinner replaces the icon, the text stays.
      service.gate = Completer();
      await tester.tap(find.text('Sign in with GitHub'));
      await tester.pump();
      expect(find.byIcon(Icons.key), findsNothing);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      expect(
        tester.getCenter(find.byType(CircularProgressIndicator)).dx,
        lessThan(tester.getCenter(find.text('Sign in with GitHub')).dx),
      );
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.key), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('in a Cupertino app: a filled button; the activity '
        'indicator before the text, which stays', (tester) async {
      final service = _LoginService()..gate = Completer();
      await tester.pumpWidget(
        cupertino(
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OAuth2LoginButton('keycloak', loginService: service),
                OAuth2LoginButton(
                  'github',
                  loginService: service,
                  icon: const Icon(CupertinoIcons.lock),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Material), findsNothing);
      expect(find.byType(CupertinoButton), findsNWidgets(2));
      expect(find.byType(PlainLoginButton), findsNothing);
      // A filled button: the primary color behind the text.
      final button = tester.widget<CupertinoButton>(
        find.widgetWithText(CupertinoButton, 'Sign in with Neon SSO'),
      );
      expect(button.onPressed, isNotNull);
      expect(
        tester.getCenter(find.byIcon(CupertinoIcons.lock)).dx,
        lessThan(tester.getCenter(find.text('Sign in with GitHub')).dx),
      );

      await tester.tap(find.text('Sign in with Neon SSO'));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Sign in with Neon SSO'), findsOneWidget);
      expect(
        tester.getCenter(find.byType(CupertinoActivityIndicator)).dx,
        lessThan(tester.getCenter(find.text('Sign in with Neon SSO')).dx),
      );
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, 'Sign in with Neon SSO'),
            )
            .onPressed,
        isNull,
      );
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActivityIndicator), findsNothing);

      // With an icon the indicator takes its place.
      service.gate = Completer();
      await tester.tap(find.text('Sign in with GitHub'));
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.lock), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.lock), findsOneWidget);
      expect(service.logins.map((login) => login.$1), ['keycloak', 'github']);
    });

    testWidgets('without a design starter: the plain button, and the plain '
        'one by design in a Material app', (tester) async {
      final service = _LoginService()..gate = Completer();
      await tester.pumpWidget(
        plain(
          Center(child: OAuth2LoginButton('keycloak', loginService: service)),
        ),
      );
      expect(find.byType(Material), findsNothing);
      expect(find.byType(PlainLoginButton), findsOneWidget);
      await tester.tap(find.text('Sign in with Neon SSO'));
      await tester.pump();
      // The spinner before the text, which stays.
      expect(find.byType(LoginSpinner), findsOneWidget);
      expect(find.text('Sign in with Neon SSO'), findsOneWidget);
      service.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byType(LoginSpinner), findsNothing);
      expect(service.logins.single.$1, 'keycloak');

      await tester.pumpWidget(
        spring(
          _material(
            OAuth2LoginButton(
              'keycloak',
              loginService: service,
              design: LoginDesign.widgets,
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(PlainLoginButton), findsOneWidget);
    });

    testWidgets('in a CupertinoApp and a WidgetsApp', (tester) async {
      final service = _LoginService();
      await tester.pumpWidget(
        cupertino(
          Center(child: OAuth2LoginButton('keycloak', loginService: service)),
        ),
      );
      expect(find.byType(CupertinoButton), findsOneWidget);
      await tester.tap(find.text('Sign in with Neon SSO'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        spring(
          _ownWidgets(
            Center(child: OAuth2LoginButton('keycloak', loginService: service)),
          ),
        ),
      );
      expect(find.byType(CupertinoButton), findsNothing);
      expect(find.byType(PlainLoginButton), findsOneWidget);
      await tester.tap(find.text('Sign in with Neon SSO'));
      await tester.pumpAndSettle();
      expect(service.logins.map((login) => login.$1), [
        'keycloak',
        'keycloak',
      ]);
    });
  });

  group('brand buttons', () {
    Widget apple({
      AppleButtonStyle style = AppleButtonStyle.black,
      bool iconOnly = false,
      List<AppleLogoArtwork>? asked,
      _LoginService? service,
    }) => AppleLoginButton(
      style: style,
      iconOnly: iconOnly,
      loginService: service,
      logo: (context, artwork) {
        asked?.add(artwork);
        return SizedBox(
          key: const Key('apple-logo'),
          width: artwork.logoOnly ? artwork.height : artwork.height * 0.7,
          height: artwork.height,
        );
      },
    );

    BoxDecoration decorationOf(WidgetTester tester, Finder button) =>
        tester
                .widget<Container>(
                  find
                      .descendant(of: button, matching: find.byType(Container))
                      .first,
                )
                .decoration!
            as BoxDecoration;

    testWidgets('Google: 40 high on Android, 44 on iOS, the "G" at 20', (
      tester,
    ) async {
      final service = _LoginService();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        spring(
          _material(Center(child: GoogleLoginButton(loginService: service))),
        ),
      );
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(tester.getSize(find.byType(BrandButton)).height, 40);
      expect(tester.getSize(find.byType(GoogleLogo)), const Size(20, 20));
      final logo = tester.getRect(find.byType(GoogleLogo));
      final button = tester.getRect(find.byType(BrandButton));
      expect(logo.left - button.left, 12);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        spring(
          _material(
            Center(
              child: GoogleLoginButton(
                loginService: service,
                key: const Key('ios'),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(BrandButton)).height, 44);
      expect(
        tester.getRect(find.byType(GoogleLogo)).left -
            tester.getRect(find.byType(BrandButton)).left,
        16,
      );
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets("Google's themes, texts and shapes", (tester) async {
      await tester.pumpWidget(
        spring(
          _material(
            const Column(
              children: [
                GoogleLoginButton(key: Key('light')),
                GoogleLoginButton(
                  key: Key('dark'),
                  theme: GoogleButtonTheme.dark,
                  text: LoginButtonText.signUp,
                  shape: LoginButtonShape.pill,
                ),
                GoogleLoginButton(
                  key: Key('neutral'),
                  theme: GoogleButtonTheme.neutral,
                  text: LoginButtonText.continueWith,
                ),
                GoogleLoginButton(key: Key('icon'), iconOnly: true),
              ],
            ),
          ),
        ),
      );
      final light = decorationOf(tester, find.byKey(const Key('light')));
      expect(light.color, const Color(0xFFFFFFFF));
      expect(light.border, Border.all(color: const Color(0xFF747775)));
      expect(light.borderRadius, BorderRadius.circular(4));
      final dark = decorationOf(tester, find.byKey(const Key('dark')));
      expect(dark.color, const Color(0xFF131314));
      expect(dark.border, Border.all(color: const Color(0xFF8E918F)));
      expect(dark.borderRadius, BorderRadius.circular(20));
      final neutral = decorationOf(tester, find.byKey(const Key('neutral')));
      expect(neutral.color, const Color(0xFFF2F2F2));
      expect(neutral.border, isNull);
      expect(find.text('Sign up with Google'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      final icon = find.byKey(const Key('icon'));
      expect(tester.getSize(icon), const Size(40, 40));
      expect(
        find.descendant(of: icon, matching: find.byType(Text)),
        findsNothing,
      );
    });

    testWidgets('icon-only buttons still say what they do', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        spring(
          _material(
            const Row(
              children: [
                GoogleLoginButton(iconOnly: true),
                GitHubLoginButton(iconOnly: true),
              ],
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Sign in with Google'), findsOneWidget);
      expect(find.bySemanticsLabel('Sign in with GitHub'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(GoogleLoginButton)),
        matchesSemantics(
          label: 'Sign in with Google',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('Google text from the app messages (translated)', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(
          MaterialApp(
            locale: const Locale('fr'),
            supportedLocales: const [Locale('fr')],
            localizationsDelegates: const [
              _FrenchMaterial.delegate,
              _FrenchCupertino.delegate,
            ],
            home: const Scaffold(
              body: GoogleLoginButton(text: LoginButtonText.continueWith),
            ),
          ),
        ),
      );
      expect(find.text('Continuer avec Google'), findsOneWidget);
    });

    testWidgets('Apple: the app logo, 44 high, at least 140 wide, '
        'the title at 43 % of the height', (tester) async {
      final asked = <AppleLogoArtwork>[];
      await tester.pumpWidget(
        spring(
          _material(
            Center(
              child: Column(
                children: [
                  apple(asked: asked),
                  apple(style: AppleButtonStyle.whiteOutline, asked: asked),
                  apple(iconOnly: true, asked: asked),
                ],
              ),
            ),
          ),
        ),
      );
      expect(asked.map((a) => (a.color, a.logoOnly, a.height)), [
        (AppleLogoColor.white, false, 44.0),
        (AppleLogoColor.black, false, 44.0),
        (AppleLogoColor.white, true, 44.0),
      ]);
      final buttons = find.byType(BrandButton);
      expect(tester.getSize(buttons.at(0)).height, 44);
      expect(tester.getSize(buttons.at(0)).width, greaterThanOrEqualTo(140));
      expect(tester.getSize(buttons.at(2)), const Size(44, 44));
      final title = tester.widget<Text>(find.text('Sign in with Apple').first);
      expect(title.style!.fontSize, closeTo(44 * 0.43, 0.01));
      expect(title.style!.color, const Color(0xFFFFFFFF));
      final black = decorationOf(tester, buttons.at(0));
      expect(black.color, const Color(0xFF000000));
      expect(black.border, isNull);
      final outlined = decorationOf(tester, buttons.at(1));
      expect(outlined.color, const Color(0xFFFFFFFF));
      expect(outlined.border, Border.all(color: const Color(0xFF000000)));
    });

    testWidgets('Microsoft: 41 high, square, its colours, the short text', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(
          _material(
            const Center(
              child: Column(
                children: [
                  MicrosoftLoginButton(),
                  MicrosoftLoginButton(
                    theme: MicrosoftButtonTheme.dark,
                    text: MicrosoftButtonText.signIn,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final buttons = find.byType(BrandButton);
      expect(tester.getSize(buttons.at(0)).height, 41);
      final light = decorationOf(tester, buttons.at(0));
      expect(light.color, const Color(0xFFFFFFFF));
      expect(light.border, Border.all(color: const Color(0xFF8C8C8C)));
      expect(light.borderRadius, BorderRadius.zero);
      expect(
        decorationOf(tester, buttons.at(1)).color,
        const Color(0xFF2F2F2F),
      );
      expect(find.text('Sign in with Microsoft'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(tester.getSize(find.byType(MicrosoftLogo).first).width, 21);
      final text = tester.widget<Text>(find.text('Sign in with Microsoft'));
      expect(text.style!.fontSize, 15);
      expect(text.style!.fontWeight, FontWeight.w600);
      expect(text.style!.color, const Color(0xFF5E5E5E));
    });

    testWidgets('GitHub: the mark white on dark, black on light', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(
          _material(
            const Column(
              children: [
                GitHubLoginButton(),
                GitHubLoginButton(theme: GitHubButtonTheme.light),
              ],
            ),
          ),
        ),
      );
      final marks = tester.widgetList<GitHubLogo>(find.byType(GitHubLogo));
      expect(marks.map((mark) => mark.color), [
        GitHubMarkColor.white,
        GitHubMarkColor.black,
      ]);
    });

    testWidgets('each logs in with its registration id, overridable', (
      tester,
    ) async {
      final service = _LoginService();
      await tester.pumpWidget(
        spring(
          _material(
            Column(
              children: [
                GoogleLoginButton(loginService: service),
                apple(service: service),
                MicrosoftLoginButton(
                  registrationId: 'entra',
                  loginService: service,
                ),
                GitHubLoginButton(loginService: service),
              ],
            ),
          ),
        ),
      );
      for (final type in [
        GoogleLoginButton,
        AppleLoginButton,
        MicrosoftLoginButton,
        GitHubLoginButton,
      ]) {
        await tester.tap(find.byType(type));
        await tester.pumpAndSettle();
      }
      expect(service.logins.map((login) => login.$1), [
        'google',
        'apple',
        'entra',
        'github',
      ]);
    });

    testWidgets('a spinner in place of the text while the login runs', (
      tester,
    ) async {
      final service = _LoginService()..gate = Completer();
      await tester.pumpWidget(
        spring(
          _material(Center(child: GoogleLoginButton(loginService: service))),
        ),
      );
      final before = tester.getSize(find.byType(BrandButton));
      await tester.tap(find.byType(GoogleLoginButton));
      await tester.pump();
      expect(find.byType(LoginSpinner), findsOneWidget);
      expect(find.byType(GoogleLogo), findsOneWidget);
      expect(tester.getSize(find.byType(BrandButton)), before);
      service.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoginSpinner), findsNothing);
    });

    testWidgets('the keyboard: focus and Enter log in', (tester) async {
      final service = _LoginService();
      await tester.pumpWidget(
        spring(_material(GitHubLoginButton(loginService: service))),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(service.logins.single.$1, 'github');
    });

    testWidgets('right to left: the logo on the right', (tester) async {
      await tester.pumpWidget(
        spring(
          _material(
            const Center(child: GoogleLoginButton()),
            direction: TextDirection.rtl,
          ),
        ),
      );
      final logo = tester.getRect(find.byType(GoogleLogo));
      final button = tester.getRect(find.byType(BrandButton));
      expect(button.right - logo.right, 12);
    });

    testWidgets('large text: taller, no overflow, the logo unchanged', (
      tester,
    ) async {
      await tester.pumpWidget(
        spring(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
            child: _material(
              const Column(
                children: [
                  GoogleLoginButton(),
                  MicrosoftLoginButton(),
                  GitHubLoginButton(text: LoginButtonText.continueWith),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(BrandButton).first).height,
        greaterThan(40),
      );
      expect(tester.getSize(find.byType(GoogleLogo)), const Size(20, 20));
    });

    testWidgets('they work in a WidgetsApp too', (tester) async {
      final service = _LoginService();
      await tester.pumpWidget(
        spring(
          WidgetsApp(
            color: const Color(0xFF000000),
            pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
              settings: settings,
              pageBuilder: (context, _, _) => builder(context),
            ),
            home: Center(child: GoogleLoginButton(loginService: service)),
          ),
        ),
      );
      await tester.tap(find.byType(GoogleLoginButton));
      await tester.pumpAndSettle();
      expect(service.logins.single.$1, 'google');
    });
  });
}

/// French Material texts are not needed: the English ones under `fr`.
class _FrenchMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const _FrenchMaterial();

  static const delegate = _FrenchMaterial();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(_FrenchMaterial old) => false;
}

class _FrenchCupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const _FrenchCupertino();

  static const delegate = _FrenchCupertino();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_FrenchCupertino old) => false;
}
