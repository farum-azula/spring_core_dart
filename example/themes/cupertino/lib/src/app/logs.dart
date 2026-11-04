import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

/// Logs the pages the user opens (Spring's logger, never print).
@Component()
@Log(topic: 'theme_showcase_cupertino.pages')
class PageLog {
  void opened(String page) => log.info('page opened', fields: {'page': page});
}

/// Logs every theme the user selects.
@Component()
@Log(topic: 'theme_showcase_cupertino.themes')
class ThemeLog {
  ThemeLog(this._selection) {
    _selection.addListener(
      () => log.info('theme selected', fields: {'theme': _selection.active}),
    );
  }

  final ThemeSelection _selection;
}
