import 'dart:math' as math;

// Java's long range, computed: 2^63 - 1 is not a valid literal on the web
// (where it rounds to 2^63).
final num _two62 = math.pow(2, 62);

/// Java's `Long.MAX_VALUE` (2^63 on the web, where it cannot be exact).
final int maxJavaLong = (_two62 - 1 + _two62).toInt();

/// Java's `Long.MIN_VALUE`.
final int minJavaLong = (-_two62 - _two62).toInt();

/// [value] truncated to an integer like Java's `(long)` cast: `NaN` is 0
/// and out-of-range values saturate at [maxJavaLong] / [minJavaLong].
int toJavaLong(double value) {
  if (value.isNaN) {
    return 0;
  }
  if (value >= maxJavaLong) {
    return maxJavaLong;
  }
  if (value <= minJavaLong) {
    return minJavaLong;
  }
  return value.truncate();
}
