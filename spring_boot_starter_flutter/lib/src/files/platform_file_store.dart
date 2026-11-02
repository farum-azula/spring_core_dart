import 'package:spring_boot_starter_flutter/src/files/file_store.dart';
import 'package:spring_boot_starter_flutter/src/files/platform_file_store_stub.dart'
    if (dart.library.io) 'package:spring_boot_starter_flutter/src/files/platform_file_store_io.dart'
    if (dart.library.js_interop) 'package:spring_boot_starter_flutter/src/files/platform_file_store_web.dart'
    as platform;

/// The [FileStore] the starter uses when the app declares none: files on
/// the device's file system (the directories `path_provider` finds), in
/// IndexedDB in a browser.
///
/// Internal to the starter.
FileStore createPlatformFileStore() => platform.createFileStore();
