import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

/// Which files are the application's, for the widgets layer: a widget is
/// the application's when what its `build` makes is created in them
/// (Flutter's creation locations, in debug and profile builds run with
/// `--track-widget-creation`, the default of a debug run): a `ReviewTile`
/// builds in the app's files, a `Padding` or a `Container` in Flutter's.
///
/// The application's files are those of the package of the widget given
/// to `runApp` (the first widget created outside Flutter's own), outside
/// its dependencies (`/packages/`, the pub cache). Without creation
/// locations (a build without the tracking) no file is known, and only
/// the Spring widgets count as the application's.
final class AppWidgetFiles {
  /// The files under [root] (a directory, or a URI's scheme and path).
  const AppWidgetFiles(this.root);

  /// No file known.
  static const none = AppWidgetFiles(null);

  /// The directory of the application's files; `null`: none known.
  final String? root;

  /// Whether creation locations are known.
  bool get known => root != null;

  /// The files of the application under [rootElement]: of the first widget
  /// down from it created outside Flutter's own package.
  static AppWidgetFiles of(Element? rootElement) {
    String? found;
    var element = rootElement;
    for (var depth = 0; element != null && depth < 40; depth++) {
      final file = developer.CreationLocation.of(element.widget)?.file;
      if (file != null && !_flutters(file)) {
        found = file;
        break;
      }
      Element? next;
      element.visitChildren((child) => next ??= child);
      element = next;
    }
    return found == null ? none : AppWidgetFiles(rootOf(found));
  }

  /// The package directory of [file]: what comes before its `/lib/`,
  /// `/test/`, `/example/`, `/bin/` or `/web/`, else its directory.
  static String rootOf(String file) {
    for (final folder in const [
      '/lib/',
      '/test/',
      '/example/',
      '/bin/',
      '/web/',
    ]) {
      final at = file.lastIndexOf(folder);
      if (at >= 0) {
        return file.substring(0, at + 1);
      }
    }
    final slash = file.lastIndexOf('/');
    return slash < 0 ? file : file.substring(0, slash + 1);
  }

  static bool _flutters(String file) =>
      file.contains('/packages/flutter/') || file.contains('package:flutter/');

  /// Whether [file] is one of the application's.
  bool contains(String file) {
    final root = this.root;
    return root != null &&
        file.startsWith(root) &&
        !file.contains('/packages/') &&
        !file.contains('/.pub-cache/') &&
        !file.contains('/.dart_tool/');
  }

  /// Whether [widget] was created in the application's files.
  bool created(Widget widget) {
    final file = developer.CreationLocation.of(widget)?.file;
    return file != null && contains(file);
  }

  /// Where [widget] was created, `file:line`, when known.
  static String? locationOf(Widget widget) {
    final location = developer.CreationLocation.of(widget);
    return location == null ? null : '${location.file}:${location.line}';
  }
}
