import 'package:dart_spring_language_server/src/schema.dart';

/// The closest of [choices] to [name] when it is near enough to be a typo.
String? didYouMean(String name, List<String> choices) {
  String? best;
  var bestDistance = 1 << 30;
  final target = canonicalName(name);
  for (final choice in choices) {
    final candidate = canonicalName(choice);
    var distance = _distance(target, candidate);
    if (candidate.startsWith(target) || target.startsWith(candidate)) {
      distance = distance.clamp(0, 1);
    }
    if (distance < bestDistance) {
      bestDistance = distance;
      best = choice;
    }
  }
  final limit = target.length <= 4 ? 1 : (target.length <= 8 ? 2 : 3);
  return best != null && bestDistance <= limit ? best : null;
}

int _distance(String a, String b) {
  if (a == b) {
    return 0;
  }
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var twoBack = previous;
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      // Two letters swapped (hots for host) is one slip.
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        current[j] = current[j] < twoBack[j - 2] + 1
            ? current[j]
            : twoBack[j - 2] + 1;
      }
    }
    twoBack = previous;
    previous = current;
  }
  return previous[b.length];
}
