// The privacy manifest of the iOS and macOS plugin against its Swift code:
// every "required reason" API the code calls (Apple's list: UserDefaults,
// file timestamps, boot time, disk space, active keyboards) must be
// declared with a reason, or the App Store refuses the app. The install
// marker kept its id in UserDefaults once, undeclared; it is a file now.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _sources =
    'darwin/spring_boot_starter_flutter_security/Sources/'
    'spring_boot_starter_flutter_security';

// The categories and the symbols that call them (Swift and C names).
const _categories = {
  'NSPrivacyAccessedAPICategoryUserDefaults': [
    'UserDefaults',
    'NSUserDefaults',
  ],
  'NSPrivacyAccessedAPICategoryFileTimestamp': [
    'creationDate',
    'modificationDate',
    'fileModificationDate',
    'contentModificationDateKey',
    'creationDateKey',
    'attributesOfItem',
    'getattrlist',
    'fgetattrlist',
    'getattrlistbulk',
    'getattrlistat',
    'stat(',
    'fstat(',
    'fstatat(',
    'lstat(',
  ],
  'NSPrivacyAccessedAPICategorySystemBootTime': [
    'systemUptime',
    'mach_absolute_time',
  ],
  'NSPrivacyAccessedAPICategoryDiskSpace': [
    'volumeAvailableCapacity',
    'volumeTotalCapacity',
    'systemFreeSize',
    'systemSize',
    'attributesOfFileSystem',
    'statfs(',
    'statvfs(',
    'fstatfs(',
    'fstatvfs(',
  ],
  'NSPrivacyAccessedAPICategoryActiveKeyboards': ['activeInputModes'],
};

// [source] without its comments (`//`, `///`, `/* */`) and string
// literals, so a doc comment naming UserDefaults is no call.
String _code(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '')
    .replaceAll(RegExp(r'"(?:[^"\\\n]|\\.)*"'), '""');

void main() {
  final manifest = File('$_sources/PrivacyInfo.xcprivacy').readAsStringSync();
  final code = {
    for (final file in Directory(_sources).listSync().whereType<File>())
      if (file.path.endsWith('.swift'))
        file.uri.pathSegments.last: _code(file.readAsStringSync()),
  };

  test('the Swift sources are found', () {
    expect(
      code.keys,
      containsAll(['InstallMarker.swift', 'KeychainSecretStore.swift']),
    );
  });

  for (final MapEntry(key: category, value: symbols) in _categories.entries) {
    test('$category: declared exactly when called', () {
      final callers = [
        for (final MapEntry(key: file, value: source) in code.entries)
          for (final symbol in symbols)
            if (RegExp('(?<![A-Za-z0-9_])${RegExp.escape(symbol)}')
                .hasMatch(source))
              '$file: $symbol',
      ];
      final declared = manifest.contains(
        '<string>$category</string>',
      );
      if (callers.isEmpty) {
        expect(declared, isFalse, reason: 'declared but never called');
      } else {
        expect(declared, isTrue, reason: 'called, undeclared: $callers');
        // A declaration needs its reasons.
        final entry = RegExp(
          '<string>$category</string>\\s*<key>NSPrivacyAccessedAPITypeReasons</key>'
          '\\s*<array>\\s*<string>[0-9A-F]{4}\\.[0-9]</string>',
        );
        expect(manifest, matches(entry));
      }
    });
  }

  test('the install marker is a file, not UserDefaults', () {
    final marker = code['InstallMarker.swift']!;
    expect(marker, isNot(contains('UserDefaults')));
    expect(marker, contains('applicationSupportDirectory'));
  });

  test('both package managers ship the manifest', () {
    expect(
      File('darwin/spring_boot_starter_flutter_security.podspec')
          .readAsStringSync(),
      contains('PrivacyInfo.xcprivacy'),
    );
    expect(
      File('darwin/spring_boot_starter_flutter_security/Package.swift')
          .readAsStringSync(),
      contains('.process("PrivacyInfo.xcprivacy")'),
    );
  });
}
