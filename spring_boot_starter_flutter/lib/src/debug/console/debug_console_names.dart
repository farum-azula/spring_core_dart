/// The items of [all] (by name) that [names] names, in its order; `*`
/// stands for every item it does not name, in their order. A name no item
/// has is left out.
Map<String, T> pickDebugConsoleNamed<T>(
  Map<String, T> all,
  List<String> names,
) {
  final named = names.toSet();
  final picked = <String, T>{};
  for (final name in names) {
    if (name == '*') {
      for (final MapEntry(key: other, value: item) in all.entries) {
        if (!named.contains(other)) {
          picked.putIfAbsent(other, () => item);
        }
      }
      continue;
    }
    if (all[name] case final item?) {
      picked.putIfAbsent(name, () => item);
    }
  }
  return picked;
}

/// The items of [all] (by name) that the build list [names] lets in (it
/// names them or holds `*`), in [all]'s order.
Map<String, T> keepDebugConsoleNamed<T>(
  Map<String, T> all,
  List<String> names,
) {
  final every = names.contains('*');
  return {
    for (final MapEntry(key: name, value: item) in all.entries)
      if (every || names.contains(name)) name: item,
  };
}

/// Fails the start when [shown], the list [shownKey] (what shows at the
/// start), names what the build list [built] ([builtKey]) does not let
/// in: a name [built] does not hold, or, when it holds `*`, one no item of
/// [available] has. `*` in [shown] stands for all of [built].
void checkDebugConsoleNames({
  required String shownKey,
  required List<String> shown,
  required String builtKey,
  required List<String> built,
  required Iterable<String> available,
}) {
  final every = built.contains('*');
  final known = available.toSet();
  final unknown = [
    for (final name in shown)
      if (name != '*' &&
          !built.contains(name) &&
          !(every && known.contains(name)))
        name,
  ];
  if (unknown.isEmpty) {
    return;
  }
  final names = unknown.map((name) => "'$name'").join(', ');
  throw StateError(
    '$shownKey names $names, which $builtKey does not have '
    '(${built.isEmpty ? 'empty' : '[${built.join(', ')}]'}): only what the '
    'build has can show. Add ${unknown.length == 1 ? 'it' : 'them'} to '
    '$builtKey (the build reads it, without a profile), or drop '
    '${unknown.length == 1 ? 'it' : 'them'} from $shownKey.',
  );
}
