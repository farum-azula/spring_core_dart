import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;

// The directories where dart:io exists (every platform but the web): what
// path_provider reads, and the creation of the one chosen.

/// Whether the plugin has a platform implementation registered.
///
/// Without one, path_provider falls back to a method channel that no host
/// answers: in a widget test the call would wait for ever, and on a device
/// without the plugin it would fail. A test that wants the directories
/// installs a `PathProviderPlatform` of its own.
bool get hasPlatform =>
    // The default implementation's name; its file is not exported.
    PathProviderPlatform.instance.runtimeType.toString() !=
    'MethodChannelPathProvider';

/// The application support directory.
Future<String> supportPath() async =>
    (await path_provider.getApplicationSupportDirectory()).path;

/// The application cache directory.
Future<String> cachePath() async =>
    (await path_provider.getApplicationCacheDirectory()).path;

/// The application documents directory.
Future<String> documentsPath() async =>
    (await path_provider.getApplicationDocumentsDirectory()).path;

/// Creates [path] and what is missing above it.
void createDirectory(String path) =>
    Directory(path).createSync(recursive: true);
