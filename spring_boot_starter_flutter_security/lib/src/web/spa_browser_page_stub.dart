import 'package:spring_boot_starter_flutter_security/src/web/spa_browser_page.dart';

/// Outside a browser there is no page: throws an [UnsupportedError].
SpaBrowserPage createSpaBrowserPage() => throw UnsupportedError(
  'No browser page outside the web: declare a SpaBrowserPage bean (a fake '
  'in tests)',
);
