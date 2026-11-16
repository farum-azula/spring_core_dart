/// The file, among the generated assets, that says how precise each
/// material of the app computes: written by the build hook, read by the
/// debug tab.
const String sceneMaterialPrecisionFile = 'spring_scene_materials.json';

final RegExp _fragment = RegExp(r'(^|\n)\s*fragment\s*\{');
final RegExp _highpDefault = RegExp(r'precision\s+highp\s+float\s*;');
final RegExp _highp = RegExp(r'\bhighp\b');
final RegExp _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');

/// How precise a material's fragment code computes.
///
/// `flutter_scene` opens every material's fragment code with
/// `precision mediump float;`: a float without a qualifier is half
/// precision (a 10-bit mantissa, a range of 65504) on the GPUs that honor
/// it (phones: iOS, Mali, Adreno), and float32 on a desktop, which ignores
/// it. A material that computes in pixels, in seconds or with a hash of
/// `sin` looks right on a desktop and wrong on a phone.
final class SceneMaterialPrecision {
  /// [highp] when the fragment code opens with `precision highp float;`,
  /// else `mediump` with [declarations] places written `highp`.
  const SceneMaterialPrecision({required this.highp, this.declarations = 0});

  /// What [source] (the text of a `.fmat` file) computes in.
  factory SceneMaterialPrecision.of(String source) {
    final code = source.replaceAll(_comment, '');
    final start = _fragment.firstMatch(code);
    final fragment = start == null ? code : code.substring(start.end);
    if (_highpDefault.hasMatch(fragment)) {
      return const SceneMaterialPrecision(highp: true);
    }
    return SceneMaterialPrecision(
      highp: false,
      declarations: _highp.allMatches(fragment).length,
    );
  }

  /// What [json] (an entry of [sceneMaterialPrecisionFile]) says.
  factory SceneMaterialPrecision.fromJson(Map<String, Object?> json) =>
      SceneMaterialPrecision(
        highp: json['precision'] == 'highp',
        declarations: (json['highp'] as num?)?.toInt() ?? 0,
      );

  /// Whether all of the fragment code is float32.
  final bool highp;

  /// The places written `highp` in fragment code that defaults to
  /// `mediump`.
  final int declarations;

  /// The entry of [sceneMaterialPrecisionFile].
  Map<String, Object?> toJson() => {
    'precision': highp ? 'highp' : 'mediump',
    if (!highp) 'highp': declarations,
  };
}

/// Where the app's bundle has [sceneMaterialPrecisionFile].
const String sceneMaterialPrecisionAsset =
    'lib/spring_gen/flutter_scene_generated/$sceneMaterialPrecisionFile';
