import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_neon/spring_gen/main.spring.dart';

/// Logs the pages the user opens (Spring's logger, never print). The Logs
/// page shows these lines in a NeonLogsPanel.
@Component()
@Log(topic: 'theme_showcase_neon.pages')
class PageLog {
  void opened(String page) => log.info('page opened', fields: {'page': page});
}

/// Logs every theme the user selects.
@Component()
@Log(topic: 'theme_showcase_neon.themes')
class ThemeLog {
  ThemeLog(this._selection) {
    _selection.addListener(
      () => log.info('theme selected', fields: {'theme': _selection.active}),
    );
  }

  final ThemeSelection _selection;
}

/// The lines the Logs page writes on request, one per level.
@Component()
@Log(topic: 'theme_showcase_neon.demo')
class DemoLog {
  void info() => log.info('a line at info');

  void warn() => log.warning('a line at warning');

  void error() => log.error('a line at error', error: StateError('on request'));
}
