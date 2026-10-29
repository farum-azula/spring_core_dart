import 'package:spring_boot_starter_flutter_security/src/web/browser_page.dart';

/// Outside a browser there is no page: throws an [UnsupportedError].
BrowserPage createBrowserPage() => throw UnsupportedError(
  'No browser page outside the web: declare a BrowserPage bean (a fake in '
  'tests)',
);
