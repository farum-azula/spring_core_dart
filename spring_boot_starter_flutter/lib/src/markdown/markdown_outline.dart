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
class MarkdownOutline extends ChangeNotifier {
  List<MarkdownHeading> _headings = const [];
  final Map<(Object?, String), GlobalKey> _keys = {};
  Object? _page;

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
    notifyListeners();
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
