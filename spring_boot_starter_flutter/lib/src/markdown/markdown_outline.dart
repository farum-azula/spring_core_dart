import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A heading of a Markdown page: its [level] (1 for `#`), its [text]
/// without the Markdown, and its [id], the anchor GitHub gives it (`#why`,
/// `#bean-methods`).
final class MarkdownHeading {
  /// A heading of [level], [text] and [id].
  const MarkdownHeading({
    required this.level,
    required this.text,
    required this.id,
  });

  /// 1 to 6.
  final int level;

  /// The text, without the Markdown's marks.
  final String text;

  /// The anchor: lower case, spaces as `-`, other marks left out; a second
  /// heading of the same text gets `-1`, the next `-2`.
  final String id;

  /// The anchor GitHub gives a heading of [text], made unique in [taken].
  static String idOf(String text, [Set<String>? taken]) {
    final base = text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true), '')
        .replaceAll(RegExp(r'\s'), '-');
    var id = base;
    for (var n = 1; taken != null && taken.contains(id); n++) {
      id = '$base-$n';
    }
    taken?.add(id);
    return id;
  }

  @override
  bool operator ==(Object other) =>
      other is MarkdownHeading &&
      other.level == level &&
      other.text == text &&
      other.id == id;

  @override
  int get hashCode => Object.hash(level, text, id);

  @override
  String toString() => '${'#' * level} $text (#$id)';
}

/// The headings of the page a `MarkdownView` shows, and the way to scroll
/// to one: give one to `MarkdownView(outline:)` and build an "On this page"
/// list from [headings]; it notifies when they change (a page loaded,
/// another language).
///
/// ```dart
/// final outline = MarkdownOutline();
/// MarkdownView.resource('resources:content/beans.md', outline: outline);
/// ListenableBuilder(
///   listenable: outline,
///   builder: (context, _) => Column(children: [
///     for (final h in outline.headings.where((h) => h.level == 2))
///       TextButton(onPressed: () => outline.show(h.id), child: Text(h.text)),
///   ]),
/// );
/// ```
///
/// [current] is the heading being read as the page scrolls, for a list
/// that marks where the reader is:
///
/// ```dart
/// ValueListenableBuilder(
///   valueListenable: outline.current,
///   builder: (context, _, _) {
///     final shown = outline.headings.where((h) => h.level == 2).toList();
///     final reading = outline.currentAmong(shown);
///     return Column(children: [
///       for (final h in shown) Entry(h, selected: h == reading),
///     ]);
///   },
/// );
/// ```
class MarkdownOutline extends ChangeNotifier {
  List<MarkdownHeading> _headings = const [];
  final Map<(Object?, String), GlobalKey> _keys = {};
  Object? _page;
  final ValueNotifier<MarkdownHeading?> _current = ValueNotifier(null);

  // The heading [show] went to: it stays the current one while the page
  // scrolls there, and after it until the reader scrolls again (a heading
  // near the end of a page cannot come to the top of the screen).
  MarkdownHeading? _shown;
  Timer? _arriving;
  double? _arrivedAt;

  /// The heading being read: the last one whose line has reached the top
  /// part of the screen as the page scrolls, `null` above the first. It
  /// notifies when the reader comes to another heading, and only then, so
  /// a list that marks the current entry is built again once a section.
  ///
  /// The `MarkdownView` keeps it up to date from the scrollable it is in.
  ValueListenable<MarkdownHeading?> get current => _current;

  /// The entry of [shown] to mark for [current]: the last of [shown] at or
  /// before it. A list of the second-level headings marks `## Setup` while
  /// the reader is in a `###` of it.
  MarkdownHeading? currentAmong(Iterable<MarkdownHeading> shown) {
    final current = _current.value;
    if (current == null) {
      return null;
    }
    final at = _headings.indexOf(current);
    MarkdownHeading? found;
    for (final heading in shown) {
      final index = _headings.indexOf(heading);
      if (index >= 0 && index <= at) {
        found = heading;
      }
    }
    return found;
  }

  /// Works out [current] from where the headings are in the scrollable of
  /// [position]. Called by the `MarkdownView` when the page scrolls and
  /// when it is laid out.
  void track(ScrollPosition position) {
    if (!position.hasPixels || !position.hasViewportDimension) {
      return;
    }
    final shown = _shown;
    if (shown != null) {
      if (_arriving != null) {
        return;
      }
      final arrived = _arrivedAt ??= position.pixels;
      if ((position.pixels - arrived).abs() < 4) {
        return;
      }
      _shown = null;
      _arrivedAt = null;
    }
    // A heading is being read once it is in the top fifth of the screen.
    final line =
        position.pixels + (position.viewportDimension * 0.2).clamp(48.0, 160.0);
    final end =
        position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 1;
    final bottom = position.pixels + position.viewportDimension;
    MarkdownHeading? found;
    for (final heading in _headings) {
      final box = _keys[(_page, heading.id)]?.currentContext
          ?.findRenderObject();
      if (box == null || !box.attached) {
        continue;
      }
      final at = RenderAbstractViewport.maybeOf(
        box,
      )?.getOffsetToReveal(box, 0).offset;
      if (at == null) {
        continue;
      }
      // At the end of the page the last heading on the screen is read:
      // it may never reach the top.
      if (at <= line || (end && at < bottom)) {
        found = heading;
      }
    }
    _current.value = found;
  }

  /// The headings, in order.
  List<MarkdownHeading> get headings => _headings;

  /// Scrolls the heading [id] into view; `false` when the page has none.
  bool show(
    String id, {
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.easeOut,
  }) {
    final key = _keys[(_page, id)];
    final target = key?.currentContext;
    for (final heading in _headings) {
      if (heading.id == id) {
        _shown = heading;
        _arrivedAt = null;
        _arriving?.cancel();
        _arriving = Timer(duration + const Duration(milliseconds: 100), () {
          _arriving = null;
        });
        _current.value = heading;
        break;
      }
    }
    if (target != null) {
      Scrollable.ensureVisible(target, duration: duration, curve: curve);
      return true;
    }
    // A heading of a long page not built yet: the page is built, then
    // shown there.
    final build = buildAll;
    if (key == null || build == null) {
      return false;
    }
    build();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final built = key.currentContext;
      if (built != null) {
        Scrollable.ensureVisible(built, duration: duration, curve: curve);
      }
    });
    return true;
  }

  /// Set by the [MarkdownView] that shows the page: builds the rest of a
  /// long page, which comes in over a few frames, so [show] reaches a
  /// heading further down at once.
  VoidCallback? buildAll;

  /// The key of the heading [id] of [page]; the view gives it to the
  /// heading's widget. Each page has its own keys: while one page goes and
  /// the next comes (`motion.content-change`) both are on screen, often
  /// with headings of the same text.
  GlobalKey keyOf(String id, {Object? page}) =>
      _keys.putIfAbsent((page, id), GlobalKey.new);

  /// Sets the [headings] of [page], the page shown; the view calls it.
  void update(List<MarkdownHeading> headings, {Object? page}) {
    final samePage = page == _page;
    _page = page;
    _keys.removeWhere(
      (key, _) => key.$1 != page || !headings.any((h) => h.id == key.$2),
    );
    if (samePage && _listEquals(headings, _headings)) {
      return;
    }
    _headings = List.unmodifiable(headings);
    if (!samePage || !_headings.contains(_current.value)) {
      _shown = null;
      _arrivedAt = null;
      _arriving?.cancel();
      _arriving = null;
      _current.value = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _arriving?.cancel();
    _current.dispose();
    super.dispose();
  }

  static bool _listEquals(List<MarkdownHeading> a, List<MarkdownHeading> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
