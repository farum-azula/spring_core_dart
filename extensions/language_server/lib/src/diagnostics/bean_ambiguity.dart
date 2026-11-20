import 'package:dart_spring_language_server/src/dart_index.dart';

final _profileName = RegExp(r'[A-Za-z0-9_][\w\-.]*');

/// The candidates of an injection point that compete: those that back off
/// when another bean of the type exists do not (unless all of them do),
/// nor do beans of one name (the later one replaces the earlier), nor
/// beans whose profiles can never be active together. Empty when the
/// injection point is not ambiguous.
List<BeanInfo> competingBeans(List<BeanInfo> candidates) {
  final firm = [
    for (final bean in candidates)
      if (!bean.backsOff) bean,
  ];
  final pool = firm.isEmpty ? candidates : firm;
  if ({for (final bean in pool) bean.name}.length < 2) {
    return const [];
  }
  // Each limited to its own profile (`dev`, `prod`): alternatives, as
  // profiles are used in practice.
  final plain = RegExp(r'^[A-Za-z0-9_][\w\-.]*$');
  final alternatives = [
    for (final bean in pool)
      if (bean.profiles.length == 1 && plain.hasMatch(bean.profiles.single))
        bean.profiles.single,
  ];
  if (alternatives.length == pool.length &&
      alternatives.toSet().length == pool.length) {
    return const [];
  }
  final names = <String>{
    for (final bean in pool)
      for (final expression in bean.profiles)
        ..._profileName.allMatches(expression).map((m) => m.group(0)!),
  }.toList();
  if (names.length > 12) {
    return pool;
  }
  for (var mask = 0; mask < 1 << names.length; mask++) {
    final active = {
      for (var i = 0; i < names.length; i++)
        if (mask & (1 << i) != 0) names[i],
    };
    final together = [
      for (final bean in pool)
        if (profilesActive(bean.profiles, active)) bean,
    ];
    if ({for (final bean in together) bean.name}.length > 1) {
      return together;
    }
  }
  return const [];
}

/// Whether a bean limited by the profile expressions [expressions] (any one
/// of them) is active when exactly the profiles [active] are: `dev`,
/// `!web`, `a & b`, `a | (b & !c)`. No expressions: always.
bool profilesActive(List<String> expressions, Set<String> active) {
  if (expressions.isEmpty) {
    return true;
  }
  return expressions.any((expression) => _evaluateProfile(expression, active));
}

bool _evaluateProfile(String expression, Set<String> active) {
  final tokens = RegExp(
    r'[A-Za-z0-9_][\w\-.]*|[!&|()]',
  ).allMatches(expression).map((m) => m.group(0)!).toList();
  var position = 0;
  late bool Function() or;

  bool atom() {
    if (position >= tokens.length) {
      return false;
    }
    final token = tokens[position++];
    if (token == '!') {
      return !atom();
    }
    if (token == '(') {
      final value = or();
      if (position < tokens.length && tokens[position] == ')') {
        position++;
      }
      return value;
    }
    return active.contains(token);
  }

  bool and() {
    var value = atom();
    while (position < tokens.length && tokens[position] == '&') {
      position++;
      final right = atom();
      value = value && right;
    }
    return value;
  }

  or = () {
    var value = and();
    while (position < tokens.length && tokens[position] == '|') {
      position++;
      final right = and();
      value = value || right;
    }
    return value;
  };
  return or();
}
