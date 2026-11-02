import 'package:flutter/foundation.dart';
import 'package:spring_boot_starter_flutter/src/sqlite_directories_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_flutter/src/sqlite_directories_io.dart'
    as native;

// The app's directories as the starter means them, one mapping for every
// user of them (the SQLite databases and FileTemplate): path_provider's
// directories, except on Windows.
//
// path_provider_windows' support directory is the roaming %APPDATA% one,
// which the OS copies between machines; its cache directory is the machine's
// own %LOCALAPPDATA%\<company>\<product>. So on Windows the starter's
// `support` is that local directory, and its `cache` a folder `cache` in it,
// so that the two never are the same folder.

/// The folder of the cache inside the local directory on Windows.
const windowsCacheFolder = 'cache';

/// The directory of `support` on [platform], from the directories
/// `path_provider` gives: [support] (the application support one) and
/// [cache] (the application cache one); null when the one needed is null.
///
/// Windows: [cache] itself (the local directory); elsewhere [support].
String? appSupportDirectory(
  TargetPlatform platform, {
  String? support,
  String? cache,
}) => platform == TargetPlatform.windows ? cache : support;

/// The directory of `cache` on [platform]: Windows: the folder `cache` in
/// [cache] (`path_provider`'s cache directory, which is the local directory
/// `support` is); elsewhere [cache]. Null when [cache] is.
String? appCacheDirectory(TargetPlatform platform, {String? cache}) =>
    platform == TargetPlatform.windows && cache != null
    ? '$cache\\$windowsCacheFolder'
    : cache;

/// The `support` directory of this platform, read from `path_provider`.
Future<String> readAppSupportDirectory() async {
  final platform = defaultTargetPlatform;
  return appSupportDirectory(
    platform,
    support: platform == TargetPlatform.windows
        ? null
        : await native.supportPath(),
    cache: platform == TargetPlatform.windows ? await native.cachePath() : null,
  )!;
}

/// The `cache` directory of this platform, read from `path_provider`.
Future<String> readAppCacheDirectory() async => appCacheDirectory(
  defaultTargetPlatform,
  cache: await native.cachePath(),
)!;

/// The `documents` directory, read from `path_provider`.
Future<String> readAppDocumentsDirectory() => native.documentsPath();
