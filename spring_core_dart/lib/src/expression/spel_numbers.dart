import 'dart:math' as math;

// Java's long range, computed: 2^63 - 1 is not a valid literal on the web
// (where it rounds to 2^63).
final num _two62 = math.pow(2, 62);

/// Java's `Long.MAX_VALUE`, the largest SpEL integer (2^63 on the web,
/// where it cannot be exact).
final int maxJavaLong = (_two62 - 1 + _two62).toInt();

/// Java's `Long.MIN_VALUE`, the smallest SpEL integer.
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

/// Java's `Double.toString` of a real number that is an `int` at run time
/// (an integral double on the web): `2.0`, `-3.0`, `1.0E7`, `1.5E10`.
String javaRealString(int value) {
  if (value.abs() < 10000000) {
    return '$value.0';
  }
  final digits = BigInt.from(value).abs().toString();
  final significant = digits.replaceFirst(RegExp(r'0+$'), '');
  final fraction = significant.length > 1 ? significant.substring(1) : '0';
  return '${value < 0 ? '-' : ''}${significant[0]}.${fraction}E'
      '${digits.length - 1}';
}

/// Whether [digits] in [radix] fit Java's `long` (64-bit two's complement
/// range), checked exactly also on the web.
bool fitsJavaLong(String digits, int radix) {
  final value = BigInt.tryParse(digits, radix: radix);
  return value != null &&
      value >= -(BigInt.one << 63) &&
      value < (BigInt.one << 63);
}
