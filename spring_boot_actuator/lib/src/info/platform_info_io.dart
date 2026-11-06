import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

/// The operating system: `Platform.operatingSystem`, its version and the
/// architecture of the running code (`x64`, `arm64`).
Map<String, Object?> osInfo() => {
  'name': Platform.operatingSystem,
  'version': Platform.operatingSystemVersion,
  'arch': '${Abi.current()}'.split('_').last,
};

/// The Dart version: `3.13.7`, the channel and the full version text.
Map<String, Object?> dartInfo() {
  final full = Platform.version;
  final version = full.split(' ').first;
  final channel = RegExp(r'\((\w+)\)').firstMatch(full)?.group(1);
  return {
    'version': version,
    'channel': ?channel,
    'runtime': {
      'name': const bool.fromEnvironment('dart.vm.product')
          ? 'Dart AOT runtime'
          : 'Dart VM',
      'version': full,
    },
  };
}
