import 'package:dart_spring_language_server/src/did_you_mean.dart';
import 'package:dart_spring_language_server/src/schema.dart';

/// The percent, hex and name forms of a color: a message when [value] is
/// not a color, `null` when it is (or may be: a reference).
String? colorProblem(String value) {
  final text = value.trim();
  if (RegExp(r'\s(alpha|mix)\s').hasMatch(text) ||
      RegExp(r'[A-Za-z0-9\-]@\d').hasMatch(text)) {
    return 'The one-line color forms are gone: write an object, '
        '`color: …` with `alpha: 12%` and/or `mix: { with: …, amount: 14% }`';
  }
  if (text.startsWith(r'$')) {
    return null;
  }
  if (RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
          .hasMatch(text) ||
      RegExp(r'^0[xX]([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(text)) {
    return null;
  }
  if (_colorNames.contains(text) || _isShade(text)) {
    return null;
  }
  if (colorRoles.contains(text)) {
    return "'$text' is a color role, no bare role names: write \$colors.$text";
  }
  final guess = didYouMean(text, _colorNames.toList());
  return "'$text' is not a color: use '#RRGGBB', '0xAARRGGBB', a Colors name "
      "or a \$reference${guess == null ? '' : ". Did you mean '$guess'?"}";
}

bool _isShade(String text) {
  final match = RegExp(r'^([A-Za-z]+)\.shade(\d+)$').firstMatch(text);
  if (match == null) {
    return false;
  }
  final name = match[1]!;
  final shade = int.parse(match[2]!);
  if (name.endsWith('Accent')) {
    return _accents.contains(name.substring(0, name.length - 6)) &&
        const {100, 200, 400, 700}.contains(shade);
  }
  return _primaries.contains(name) &&
      const {50, 100, 200, 300, 400, 500, 600, 700, 800, 900}.contains(shade);
}

const _primaries = {
  'red', 'pink', 'purple', 'deepPurple', 'indigo', 'blue', 'lightBlue', //
  'cyan', 'teal', 'green', 'lightGreen', 'lime', 'yellow', 'amber',
  'orange', 'deepOrange', 'brown', 'grey', 'blueGrey',
};

const _accents = {
  'red', 'pink', 'purple', 'deepPurple', 'indigo', 'blue', 'lightBlue', //
  'cyan', 'teal', 'green', 'lightGreen', 'lime', 'yellow', 'amber',
  'orange', 'deepOrange',
};

final Set<String> _colorNames = {
  ..._primaries,
  for (final name in _accents) '${name}Accent',
  'transparent',
  'black',
  'white',
  'black12',
  'black26',
  'black38',
  'black45',
  'black54',
  'black87',
  'white10',
  'white12',
  'white24',
  'white30',
  'white38',
  'white54',
  'white60',
  'white70',
};

/// The parts of a color object: `color`, `alpha` and `mix`.
const colorObjectKeys = {'color', 'alpha', 'mix'};

/// Whether [value] is a percentage from 0% to 100%, a fraction from 0 to
/// 1, or a `$` reference.
bool isPercent(String value) {
  final match = RegExp(r'^(\d+(?:\.\d+)?)(%?)$').firstMatch(value.trim());
  if (match == null) {
    return value.startsWith(r'$');
  }
  final number = double.parse(match[1]!);
  return number >= 0 && number <= (match[2] == '%' ? 100 : 1);
}
