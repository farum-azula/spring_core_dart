// The desktop window of the Flutter starter on the real window: the
// properties of spring.flutter.desktop.window.* reach the native window
// before the first frame, and the plugin reads it back. Run on a desktop:
//   flutter test integration_test/desktop_window_test.dart -d macos
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:spring_boot_starter_flutter_security/spring_boot_starter_flutter_security.dart';

SpringApplication application(String title, String size, String min) =>
    SpringApplication(
      [
        BeanModule(
          'window',
          const [],
          resources: {
            'application.properties': EmbeddedResource.text(
              'spring.flutter.desktop.window.title-bar=$title\n'
              'spring.flutter.desktop.window.initial-size=$size\n'
              'spring.flutter.desktop.window.min-size=$min\n',
            ),
          },
        ),
      ],
      bannerMode: BannerMode.off,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a transparent title bar, the initial and minimum sizes', (
    tester,
  ) async {
    DesktopWindowData? seen;
    await tester.pumpWidget(
      SpringApplicationWidget(
        application: () => application('transparent', '1000x700', '640x480'),
        child: Builder(
          builder: (context) {
            seen = DesktopWindow.of(context);
            return const Directionality(
              textDirection: TextDirection.ltr,
              child: SizedBox.expand(),
            );
          },
        ),
      ),
    );
    // The application starts on real time (files, fonts, the window).
    for (var i = 0; i < 100 && seen == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(seen, isNotNull);

    final window = await DesktopWindowChannel.describe();
    expect(window['titleBar'], 'transparent');
    expect(window['contentWidth'], 1000);
    expect(window['contentHeight'], 700);
    expect(window['minWidth'], 640);
    expect(window['minHeight'], 480);
    expect(window['titlebarAppearsTransparent'], isTrue);
    expect(window['fullSizeContentView'], isTrue);
    expect(window['buttonsHidden'], isFalse);
    expect(seen!.titleBar, TitleBarStyle.transparent);
    // The traffic lights' area.
    expect(seen!.insets.left, greaterThan(40));
    expect(seen!.insets.top, greaterThan(20));
  }, skip: !DesktopWindowChannel.isSupported);
}
