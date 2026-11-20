import 'dart:io';

import 'package:dart_spring_language_server/src/flutter_assets.dart';

/// The `flutter: assets:` entries of the packages' `pubspec.yaml`, read
/// again when a pubspec changes.
final class PubspecAssets {
  final _pubspecs = <String, (DateTime, List<String>)>{};

  /// The `flutter: assets:` entries of the package at [package].
  List<String> of(String package) {
    final file = File('$package/pubspec.yaml');
    if (!file.existsSync()) {
      return const [];
    }
    final modified = file.lastModifiedSync();
    final cached = _pubspecs[package];
    if (cached != null && cached.$1 == modified) {
      return cached.$2;
    }
    final assets = flutterAssets(file.readAsStringSync());
    _pubspecs[package] = (modified, assets);
    return assets;
  }
}
