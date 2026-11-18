// The builds of lib/spring_gen/spring_metadata.json the metadata tests share
// (test/core/, test/data/, test/flutter/): the metadata builder with every
// starter's part, and the configuration properties most of them read.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/core/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/spring_metadata_builder.dart';
import 'package:spring_core_dart_generator/src/starters.dart';
import 'package:test/test.dart';

/// The imports a source of the metadata tests starts with.
const metadataHeader = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
''';

/// Runs the builder over `sources` (paths below `pkg|`); returns the JSON
/// and the log lines. `null` JSON: nothing was written.
typedef MetadataRun = ({
  Map<String, Object?>? json,
  String? text,
  List<String> logs,
});

Future<MetadataRun> runMetadataBuilder(
  Map<String, Object> sources, {
  String package = 'pkg',
}) async {
  final logs = <String>[];
  final readerWriter = TestReaderWriter(
    rootPackage: package,
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringMetadataBuilder(
      generations: starterGenerations,
      packageDirectories: PackageDirectories(),
    ),
    {for (final e in sources.entries) '$package|${e.key}': e.value},
    rootPackage: package,
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (r) => logs.add('${r.level.name}: ${r.message}'),
  );
  expect(result.errors, isEmpty);
  final id = AssetId(package, 'lib/spring_gen/spring_metadata.json');
  if (!await readerWriter.canRead(id)) {
    return (json: null, text: null, logs: logs);
  }
  final text = readerWriter.testing.readString(id);
  return (
    json: jsonDecode(text) as Map<String, Object?>,
    text: text,
    logs: logs,
  );
}

/// The entries of [json] under [key].
List<Map<String, Object?>> entriesOf(Map<String, Object?> json, String key) => [
  for (final e in json[key]! as List) e as Map<String, Object?>,
];

/// The entry of [json] under [key] named [name].
Map<String, Object?> namedEntry(
  Map<String, Object?> json,
  String key,
  String name,
) => entriesOf(json, key).firstWhere((e) => e['name'] == name);

/// `@ConfigurationProperties` classes of every kind of property.
const shopProperties =
    '''
$metadataHeader
enum Mode {
  /// Fast and loose.
  fastMode,
  slow,
}

class Pool {
  /// How many connections.
  int size = 4;
  Mode mode = Mode.slow;
}

class Route {
  String path = '/';
}

/// Settings of the shop.
@ConfigurationProperties('app.shop')
class ShopProperties {
  /// The name shown in the title bar.
  String displayName = 'Shop';

  /// Maximum of items.
  int maxItems = 10;

  double rate = 1.5;
  bool open = true;
  Duration timeout = const Duration(seconds: 3);
  Mode mode = Mode.fastMode;

  @Deprecated('Use displayName.')
  String title = '';

  List<String> tags = [];
  Map<String, String> labels = {};
  Pool pool = Pool();
  List<Route> routes = [];
  Map<String, Route> byHost = {};

  final String fixed = 'x';
}

@ConfigurationProperties('db')
class DbProperties {
  const DbProperties(this.url, {this.maxSize = 10});

  /// The URL of the database.
  final String url;
  final int maxSize;
}
''';
