import 'package:spring_boot_starter_flutter/src/files/file_template.dart';
import 'package:spring_boot_starter_flutter/src/splash/splash_task.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';

/// Where the theme the user chose is kept between runs
/// (`spring.flutter.theme.remember`): `ThemeSelection` writes it at each
/// choice, [ThemeChoiceRestore] reads it back while the splash shows. The
/// starter keeps it in the app's files ([FileThemeChoiceStore]); a bean of
/// this type keeps it elsewhere (an account's settings on a server).
abstract interface class ThemeChoiceStore {
  /// The choice kept: `system` or a theme's name; `null` when none is.
  Future<String?> read();

  /// Keeps [choice].
  Future<void> write(String choice);
}

/// The choice in the app's files (`fileTemplate`): `spring/theme-choice`,
/// IndexedDB in a browser.
final class FileThemeChoiceStore implements ThemeChoiceStore {
  /// The choice in [files].
  const FileThemeChoiceStore(this.files);

  /// The app's files.
  final FileTemplate files;

  static const _path = 'spring/theme-choice';

  @override
  Future<String?> read() => files.support.readString(_path);

  @override
  Future<void> write(String choice) => files.write(_path, choice);
}

/// Shows the theme kept by [store] before the app shows, while the splash
/// does, so a reload does not flash the default theme first.
final class ThemeChoiceRestore extends SplashTask {
  /// Restores [selection]'s choice from [store].
  ThemeChoiceRestore(this.selection, this.store);

  /// The choice shown.
  final ThemeSelection selection;

  /// Where it is kept.
  final ThemeChoiceStore store;

  @override
  String get name => 'theme choice';

  @override
  Future<void> run(SplashTaskContext task) async {
    final kept = await store.read();
    if (kept != null) {
      selection.restore(kept);
    }
  }
}
