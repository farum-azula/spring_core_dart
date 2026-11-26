import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/debug/debug_style.dart';
import 'package:spring_boot_starter_flutter/src/debug/isolates/isolates_view.dart';

/// A number of the Isolates tab's memory and size blocks, large and bold
/// in the debug theme's number colour, its [unit] smaller after it.
class DebugBigNumber extends StatelessWidget {
  /// [number] and its [unit].
  const DebugBigNumber(this.number, [this.unit, Key? key]) : super(key: key);

  /// [bytes] as `182 MB`.
  factory DebugBigNumber.bytes(int bytes) {
    final (number, unit) = formatIsolateMemoryParts(bytes);
    return DebugBigNumber(number, unit);
  }

  /// The number.
  final String number;

  /// What it counts; `null`: nothing.
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final style = DebugStyle.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: number,
            style: style.code.copyWith(
              color: style.number,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          if (unit case final unit?)
            TextSpan(
              text: ' $unit',
              style: style.code.copyWith(color: style.number, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
