import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_boot_starter_flutter/src/debug/logs/debug_file_platform.dart'
    as platform;

const _log = SpringLog('spring_boot_starter_flutter.DebugFileExports');

/// Where the debug tools put a file they export (the log export): a
/// download in a browser, the Downloads folder on a desktop. Every
/// `DebugFileExport` bean is one; the first by `@Order` that is
/// [available] takes the file ([DebugFileExports]). The built-in ones come
/// last: [BrowserDebugFileExport], [DownloadsDebugFileExport]. On a phone
/// none is available, and the export says so: the records never go
/// anywhere the user did not choose. [ClipboardDebugFileExport] puts the
/// text on the clipboard, which other apps can read, only when the
/// application registers it as a bean.
///
/// An application adds its own, a share sheet on a phone, as a bean of an
/// order before them (`@Order(0)`); its package goes into the
/// application's pubspec, not the starter's:
///
/// ```dart
/// @Component()
/// @Order(0)
/// class ShareDebugFileExport implements DebugFileExport {
///   @override
///   bool get available => !kIsWeb && (Platform.isIOS || Platform.isAndroid);
///
///   @override
///   Future<String> export(String fileName, Uint8List bytes, String mimeType) async {
///     final file = XFile.fromData(bytes, name: fileName, mimeType: mimeType);
///     await SharePlus.instance.share(ShareParams(files: [file], fileNameOverrides: [fileName]));
///     return 'Shared $fileName';
///   }
/// }
/// ```
///
/// In the build only with the log export
/// (`spring.flutter.debug.logs.export.enabled`).
abstract interface class DebugFileExport {
  /// Whether it can take a file on this platform, now.
  bool get available;

  /// Puts [bytes] somewhere as [fileName] of [mimeType]; what to tell the
  /// user (where the file went). Throws when it cannot: the next one
  /// available takes the file.
  Future<String> export(String fileName, Uint8List bytes, String mimeType);
}

/// The chain of the [DebugFileExport] beans (`debugFileExports`): a file
/// goes to the first, by `@Order`, that is available; when it throws, to
/// the next one available.
final class DebugFileExports {
  /// The chain of [exports], in their order.
  const DebugFileExports(this.exports);

  /// Every one, in order.
  final List<DebugFileExport> exports;

  /// What [export] tells when no exporter is available here (a phone
  /// without one of the application's).
  static const noneAvailable =
      'No file export here: add a DebugFileExport bean (a share sheet), or '
      'ClipboardDebugFileExport to copy the text to the clipboard';

  /// The one a file goes to now; `null`: none is available.
  DebugFileExport? get current {
    for (final export in exports) {
      if (export.available) {
        return export;
      }
    }
    return null;
  }

  /// Puts [bytes] somewhere as [fileName] of [mimeType]; what to tell the
  /// user.
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async {
    Object? failure;
    for (final export in exports) {
      if (!export.available) {
        continue;
      }
      try {
        return await export.export(fileName, bytes, mimeType);
      } on Object catch (error, stackTrace) {
        failure = error;
        _log.warning(
          () => '${export.runtimeType} could not export $fileName',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return failure == null ? noneAvailable : 'The export failed: $failure';
  }
}

/// A file as a browser download (a `Blob` behind an `<a download>`), in a
/// browser only.
final class BrowserDebugFileExport implements DebugFileExport, Ordered {
  /// The export; [web] and [download] are for tests.
  const BrowserDebugFileExport({
    this.web = kIsWeb,
    this.download = platform.browserDownload,
  });

  /// Whether the app runs in a browser.
  final bool web;

  /// Hands a file to the browser.
  final void Function(String fileName, Uint8List bytes, String mimeType)
  download;

  @override
  int get order => Ordered.lowestPrecedence - 2;

  @override
  bool get available => web;

  @override
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async {
    download(fileName, bytes, mimeType);
    return 'Downloaded $fileName';
  }
}

/// A file in the user's Downloads folder (`path_provider`'s
/// `getDownloadsDirectory`), on macOS, Windows and Linux. A sandboxed
/// macOS app writes into its container's Downloads folder unless it has
/// the `com.apple.security.files.downloads.read-write` entitlement.
final class DownloadsDebugFileExport implements DebugFileExport, Ordered {
  /// The export; [web] and [write] are for tests.
  const DownloadsDebugFileExport({
    this.web = kIsWeb,
    this.write = platform.writeToDownloads,
  });

  /// Whether the app runs in a browser.
  final bool web;

  /// Writes a file into the Downloads folder; its path.
  final Future<String> Function(String fileName, Uint8List bytes) write;

  static const _desktops = {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  };

  @override
  int get order => Ordered.lowestPrecedence - 1;

  @override
  bool get available => !web && _desktops.contains(defaultTargetPlatform);

  @override
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async => 'Saved ${await write(fileName, bytes)}';
}

/// The file's text on the clipboard, which other apps can read: not a
/// built-in exporter, only when the application registers it, after its
/// own (`@Order` lowest).
///
/// ```dart
/// @Bean()
/// DebugFileExport clipboardExport() => const ClipboardDebugFileExport();
/// ```
final class ClipboardDebugFileExport implements DebugFileExport, Ordered {
  /// The export.
  const ClipboardDebugFileExport();

  @override
  int get order => Ordered.lowestPrecedence;

  @override
  bool get available => true;

  @override
  Future<String> export(
    String fileName,
    Uint8List bytes,
    String mimeType,
  ) async {
    await Clipboard.setData(
      ClipboardData(text: utf8.decode(bytes, allowMalformed: true)),
    );
    return '$fileName copied to the clipboard';
  }
}
