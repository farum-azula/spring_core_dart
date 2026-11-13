import 'dart:collection';
import 'dart:math' show Random;

import 'package:signals_core/signals_core.dart' as signals;
import 'package:spring_boot_starter_flutter_signals/src/follow_keeper.dart';

/// What the followed collections share: a counter that every read reads
/// and every change raises, so a reader is told of a change in place.
///
/// The collection itself is the one the bean's field holds: the follower
/// only stands in front of it.
base mixin FollowedCollection {
  /// The counter; made by the collection's constructor.
  signals.Signal<int> get version;

  /// Notes a read: whatever reads now is told of the next change.
  void touch() {
    FollowKeeper.note(_follow);
    version.value;
  }

  void _follow() => version.value;

  /// Tells the readers of a change.
  void changed() => version.value = version.peek() + 1;

  /// Stops following.
  void disposeFollower() => version.dispose();
}

signals.Signal<int> _version(String name) => signals.signal<int>(
  0,
  options: signals.SignalOptions<int>(name: name),
);

/// A list whose readers are told when it changes in place.
final class FollowedList<E> extends ListBase<E> with FollowedCollection {
  /// The follower of [source], called [name] in the debug tab.
  FollowedList(this.source, String name) : version = _version(name);

  /// The list followed: the one the bean's field holds.
  final List<E> source;

  @override
  final signals.Signal<int> version;

  T _change<T>(T Function() change) {
    final result = change();
    changed();
    return result;
  }

  @override
  int get length {
    touch();
    return source.length;
  }

  @override
  set length(int value) => _change(() => source.length = value);

  @override
  E operator [](int index) {
    touch();
    return source[index];
  }

  @override
  void operator []=(int index, E value) => _change(() => source[index] = value);

  // One change for each of these, however many elements they move.
  @override
  void add(E element) => _change(() => source.add(element));

  @override
  void addAll(Iterable<E> iterable) => _change(() => source.addAll(iterable));

  @override
  void insert(int index, E element) =>
      _change(() => source.insert(index, element));

  @override
  void insertAll(int index, Iterable<E> iterable) =>
      _change(() => source.insertAll(index, iterable));

  @override
  bool remove(Object? element) => _change(() => source.remove(element));

  @override
  E removeAt(int index) => _change(() => source.removeAt(index));

  @override
  E removeLast() => _change(source.removeLast);

  @override
  void removeRange(int start, int end) =>
      _change(() => source.removeRange(start, end));

  @override
  void removeWhere(bool Function(E element) test) =>
      _change(() => source.removeWhere(test));

  @override
  void retainWhere(bool Function(E element) test) =>
      _change(() => source.retainWhere(test));

  @override
  void clear() => _change(source.clear);

  @override
  void sort([int Function(E a, E b)? compare]) =>
      _change(() => source.sort(compare));

  @override
  void shuffle([Random? random]) => _change(() => source.shuffle(random));

  @override
  void setAll(int index, Iterable<E> iterable) =>
      _change(() => source.setAll(index, iterable));

  @override
  void setRange(
    int start,
    int end,
    Iterable<E> iterable, [
    int skipCount = 0,
  ]) => _change(() => source.setRange(start, end, iterable, skipCount));

  @override
  void fillRange(int start, int end, [E? fill]) =>
      _change(() => source.fillRange(start, end, fill));

  @override
  void replaceRange(int start, int end, Iterable<E> newContents) =>
      _change(() => source.replaceRange(start, end, newContents));

  // Reads of the whole list note one read, not one per element.
  @override
  Iterator<E> get iterator {
    touch();
    return source.iterator;
  }

  @override
  bool get isEmpty {
    touch();
    return source.isEmpty;
  }

  @override
  bool contains(Object? element) {
    touch();
    return source.contains(element);
  }
}

/// A set whose readers are told when it changes in place.
final class FollowedSet<E> extends SetBase<E> with FollowedCollection {
  /// The follower of [source], called [name] in the debug tab.
  FollowedSet(this.source, String name) : version = _version(name);

  /// The set followed.
  final Set<E> source;

  @override
  final signals.Signal<int> version;

  @override
  bool add(E value) {
    final added = source.add(value);
    if (added) {
      changed();
    }
    return added;
  }

  @override
  bool remove(Object? value) {
    final removed = source.remove(value);
    if (removed) {
      changed();
    }
    return removed;
  }

  @override
  void clear() {
    source.clear();
    changed();
  }

  @override
  void addAll(Iterable<E> elements) {
    source.addAll(elements);
    changed();
  }

  @override
  void removeAll(Iterable<Object?> elements) {
    source.removeAll(elements);
    changed();
  }

  @override
  void retainWhere(bool Function(E element) test) {
    source.retainWhere(test);
    changed();
  }

  @override
  void removeWhere(bool Function(E element) test) {
    source.removeWhere(test);
    changed();
  }

  @override
  bool contains(Object? element) {
    touch();
    return source.contains(element);
  }

  @override
  E? lookup(Object? element) {
    touch();
    return source.lookup(element);
  }

  @override
  Iterator<E> get iterator {
    touch();
    return source.iterator;
  }

  @override
  int get length {
    touch();
    return source.length;
  }

  @override
  Set<E> toSet() {
    touch();
    return source.toSet();
  }
}

/// A map whose readers are told when it changes in place.
final class FollowedMap<K, V> extends MapBase<K, V> with FollowedCollection {
  /// The follower of [source], called [name] in the debug tab.
  FollowedMap(this.source, String name) : version = _version(name);

  /// The map followed.
  final Map<K, V> source;

  @override
  final signals.Signal<int> version;

  @override
  V? operator [](Object? key) {
    touch();
    return source[key];
  }

  @override
  void operator []=(K key, V value) {
    source[key] = value;
    changed();
  }

  @override
  void clear() {
    source.clear();
    changed();
  }

  @override
  Iterable<K> get keys {
    touch();
    return source.keys;
  }

  @override
  V? remove(Object? key) {
    final had = source.containsKey(key);
    final value = source.remove(key);
    if (had) {
      changed();
    }
    return value;
  }

  @override
  void addAll(Map<K, V> other) {
    source.addAll(other);
    changed();
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    source.removeWhere(test);
    changed();
  }

  @override
  int get length {
    touch();
    return source.length;
  }

  @override
  bool containsKey(Object? key) {
    touch();
    return source.containsKey(key);
  }
}

/// A queue whose readers are told when it changes in place.
final class FollowedQueue<E>
    with IterableMixin<E>, FollowedCollection
    implements Queue<E> {
  /// The follower of [source], called [name] in the debug tab.
  FollowedQueue(this.source, String name) : version = _version(name);

  /// The queue followed.
  final Queue<E> source;

  @override
  final signals.Signal<int> version;

  T _change<T>(T Function() change) {
    final result = change();
    changed();
    return result;
  }

  @override
  Iterator<E> get iterator {
    touch();
    return source.iterator;
  }

  @override
  int get length {
    touch();
    return source.length;
  }

  @override
  void add(E value) => _change(() => source.add(value));

  @override
  void addAll(Iterable<E> iterable) => _change(() => source.addAll(iterable));

  @override
  void addFirst(E value) => _change(() => source.addFirst(value));

  @override
  void addLast(E value) => _change(() => source.addLast(value));

  @override
  void clear() => _change(source.clear);

  @override
  bool remove(Object? value) => _change(() => source.remove(value));

  @override
  E removeFirst() => _change(source.removeFirst);

  @override
  E removeLast() => _change(source.removeLast);

  @override
  void removeWhere(bool Function(E element) test) =>
      _change(() => source.removeWhere(test));

  @override
  void retainWhere(bool Function(E element) test) =>
      _change(() => source.retainWhere(test));

  @override
  Queue<R> cast<R>() {
    touch();
    return source.cast<R>();
  }
}
