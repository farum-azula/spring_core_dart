import 'package:flutter/widgets.dart';

/// A word to tap: the app has no design library.
class Tap extends StatelessWidget {
  /// [label] that calls [onTap].
  const Tap(this.label, {required this.onTap, super.key});

  /// The word.
  final String label;

  /// What a tap does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF22E6FF),
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}
