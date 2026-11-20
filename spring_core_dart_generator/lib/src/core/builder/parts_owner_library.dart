import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:spring_core_dart_generator/src/core/builder/generated_path.dart';

/// A `.dart` file with a `@ComponentScan` or `@SpringBootApplication`, and
/// whether it has the second.
typedef ScanLibrary = ({AssetId id, bool boot});

/// The library of a package whose generated `.spring.dart` holds the `part`
/// directives of the files other builders write into `lib/spring_gen/`
/// (the Flutter starter's typed key files, the classes of
/// `spring.json.schemas`), and the paths of the `part` and `part of`
/// directives between them. The main builder and those builders find it
/// the same way, so the main builder writes the `part` directives of
/// exactly the files the others write.
///
/// ```dart
/// final scanLibraries = await PartsOwnerLibrary.scanLibrariesOf(buildStep);
/// final owner = PartsOwnerLibrary.find(scanLibraries); // lib/main.dart
/// owner.generatedLibrary;   // lib/spring_gen/main.spring.dart
/// owner.partDirectivePath('lib/spring_gen/theme.spring.keys.dart');
/// // 'theme.spring.keys.dart'
/// owner.partOfDirectivePath; // 'main.spring.dart'
/// ```
final class PartsOwnerLibrary {
  PartsOwnerLibrary._(this.source);

  /// The library's source (`lib/main.dart`).
  final AssetId source;

  /// The generated library the parts belong to:
  /// `lib/spring_gen/main.spring.dart` for `lib/main.dart`.
  String get generatedLibrary => generatedPath(source.path);

  /// The path of [part] (below the package) as the `part` directive of
  /// [generatedLibrary] names it.
  String partDirectivePath(String part) =>
      p.url.relative(part, from: p.url.dirname(generatedLibrary));

  /// The path of [generatedLibrary] as the `part of` directive of a part in
  /// `lib/spring_gen/` names it.
  String get partOfDirectivePath =>
      p.url.relative(generatedLibrary, from: 'lib/$generatedFolder');

  /// The `.dart` files of `lib/` of [buildStep]'s package with a
  /// `@ComponentScan` or a `@SpringBootApplication` (the two annotations
  /// that make the main builder write a `.spring.dart`), sorted by path;
  /// `boot` tells the second.
  static Future<List<ScanLibrary>> scanLibrariesOf(BuildStep buildStep) async {
    final package = buildStep.inputId.package;
    final scan = RegExp(
      r'^\s*@(ComponentScan|SpringBootApplication)\b',
      multiLine: true,
    );
    final boot = RegExp(r'^\s*@SpringBootApplication\b', multiLine: true);
    final result = <ScanLibrary>[];
    final assets = await buildStep
        .findAssets(Glob('lib/**.dart'))
        .where((asset) => asset.package == package)
        .where((asset) => !isGeneratedSource(asset.path))
        .toList();
    assets.sort((a, b) => a.path.compareTo(b.path));
    for (final asset in assets) {
      final text = await buildStep.readAsString(asset);
      if (scan.hasMatch(text)) {
        result.add((id: asset, boot: boot.hasMatch(text)));
      }
    }
    return result;
  }

  /// The owner of the parts among [scanLibraries]: the
  /// `@SpringBootApplication` library if there is one, else the outermost
  /// `@ComponentScan` (the one whose directory holds the others, as nested
  /// scans are supported). `null` when there is no library, or no single
  /// one ([whyNotFound] says why).
  static PartsOwnerLibrary? find(List<ScanLibrary> scanLibraries) =>
      switch (_choose(scanLibraries).owner) {
        final owner? => PartsOwnerLibrary._(owner.id),
        null => null,
      };

  /// Why [find] finds no owner among [scanLibraries] although there are
  /// some (two applications, or scans in sibling directories); `null` when
  /// it finds one, or when [scanLibraries] is empty.
  static String? whyNotFound(List<ScanLibrary> scanLibraries) =>
      _choose(scanLibraries).reason;

  // The owner, or the reason there is none; neither without any scan
  // library.
  static ({ScanLibrary? owner, String? reason}) _choose(
    List<ScanLibrary> scanLibraries,
  ) {
    if (scanLibraries.isEmpty) {
      return (owner: null, reason: null);
    }
    String names(Iterable<ScanLibrary> list) =>
        list.map((library) => library.id.path).join(' and ');
    final boots = scanLibraries.where((library) => library.boot).toList();
    if (boots.length > 1) {
      return (
        owner: null,
        reason:
            'A package has one @SpringBootApplication library for the typed '
            'keys, found ${names(boots)}: remove one, or move it into its '
            'own package.',
      );
    }
    if (boots.length == 1) {
      return (owner: boots.single, reason: null);
    }
    String directoryOf(ScanLibrary library) => p.url.dirname(library.id.path);
    for (final candidate in scanLibraries) {
      final directory = directoryOf(candidate);
      if (scanLibraries.every(
        (other) =>
            other == candidate || p.url.isWithin(directory, other.id.path),
      )) {
        // Same directory is not "within": two scans there are unrelated.
        if (scanLibraries
                .where((library) => directoryOf(library) == directory)
                .length ==
            1) {
          return (owner: candidate, reason: null);
        }
      }
    }
    return (
      owner: null,
      reason:
          'A package has one outermost @ComponentScan library for the typed '
          'keys, found unrelated ${names(scanLibraries)}: nest one scan '
          "inside the other's directory, or move one into its own package.",
    );
  }
}
