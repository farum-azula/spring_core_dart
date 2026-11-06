import 'package:flutter/widgets.dart';

/// What a shell's widget gets: the screens of its current branch and the
/// way to switch branches.
///
/// ```dart
/// Scaffold(
///   body: shell.child,
///   bottomNavigationBar: NavigationBar(
///     selectedIndex: shell.index,
///     onDestinationSelected: shell.select,
///     destinations: const [...],
///   ),
/// )
/// ```
abstract interface class ShellState {
  /// The screens of the current branch; the other branches stay built
  /// (offstage) once visited, so each keeps its stack and state.
  Widget get child;

  /// The index of the current branch in [branches].
  int get index;

  /// The paths that start the branches.
  List<String> get branches;

  /// The path of the current branch.
  String get branch;

  /// Switches to branch [index] as it was left, or to its first screen
  /// when it was never visited; selecting the current branch again goes
  /// back to its first screen.
  void select(int index);
}
