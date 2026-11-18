/// The one of [candidates] closest to [name], for a "did you mean" hint, or
/// `null` when none is close.
///
/// The comparison ignores case. A candidate is close when its edit distance
/// to [name] is at most a third of the longer of the two, rounded up, so a
/// typo (`titel` for `title`, `nme` for `name`) is found and a different
/// word is not. The first of equally close candidates wins.
///
/// A name of one or two characters has no close candidate: any other short
/// name is one change away (`b` for `a`), and an alias or a short column is
/// far more often right than mistyped.
///
/// ```dart
/// closestName('titel', ['id', 'title', 'year']); // 'title'
/// closestName('zzzzz', ['id', 'title', 'year']); // null
/// closestName('bk', ['b', 'id']); // null
/// ```
///
/// Spring (Java): none; Spring Data's `PropertyReferenceException` lists
/// the candidates and `PropertyReferenceException#getPropertyMatches` finds
/// the close ones the same way.
String? closestName(String name, Iterable<String> candidates) {
  if (name.length <= 2) {
    return null;
  }
  String? best;
  var bestDistance = 1 << 30;
  final wanted = name.toLowerCase();
  for (final candidate in candidates) {
    final distance = _distance(wanted, candidate.toLowerCase());
    final longest = wanted.length > candidate.length
        ? wanted.length
        : candidate.length;
    if (distance < bestDistance && distance <= (longest / 3).ceil()) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

// The Levenshtein distance: the fewest single-character insertions,
// deletions and replacements that turn [a] into [b].
int _distance(String a, String b) {
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final best = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      current[j] = best;
    }
    previous = current;
  }
  return previous[b.length];
}
