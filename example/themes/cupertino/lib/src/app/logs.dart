import 'package:spring_boot_starter_flutter_navigation/spring_boot_starter_flutter_navigation.dart';
import 'package:theme_showcase_cupertino/spring_gen/main.spring.dart';

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
