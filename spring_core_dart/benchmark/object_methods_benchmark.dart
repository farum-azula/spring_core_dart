// What ==, hashCode and toString() cost through IntrospectedObject beside
// hand-written ones: `==` of two equal objects, `hashCode`, a lookup in a
// set of 1,000, and `toString()`. `Book` mixes in IntrospectedObject, its
// description holds the functions as the generator writes them for
// @EqualsAndHashCode and @ToString (`deepEquals` and `deepHash` for the
// list); `HandBook` compares its fields itself. Not part of the tests; run
// with
//   dart run benchmark/object_methods_benchmark.dart
//   dart compile exe benchmark/object_methods_benchmark.dart -o /tmp/om && /tmp/om
//
// November 2026, Apple M5, nanoseconds per call, AOT / JIT (through
// IntrospectedObject; by hand): == 14 / 14 (8 / 9), hashCode 17 / 28
// (11 / 16), a set lookup 33 / 49 (19 / 25), toString() 199 / 153
// (195 / 143). The lookup of the description by runtime type is a map with
// a cache of the last type in front: 4-5 ns a call less than the map alone
// for objects of one class, under 1 ns more when classes alternate.
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';

class Book with IntrospectedObject {
  Book(this.title, this.pages, this.tags);

  final String title;
  final int pages;
  final List<String> tags;
}

bool _$equals0(Book a, Book b) =>
    a.title == b.title && a.pages == b.pages && deepEquals(a.tags, b.tags);

int _$hashCode1(Book object) =>
    Object.hash(object.title, object.pages, deepHash(object.tags));

String _$toString2(Book object) =>
    'Book(title: ${object.title}, pages: ${object.pages}, '
    'tags: ${object.tags})';

const _description = Introspection<Book>(
  className: 'Book',
  parts: {},
  objectMethods: ObjectMethods<Book>(
    equals: _$equals0,
    hashCode: _$hashCode1,
    toString: _$toString2,
  ),
);

class HandBook {
  HandBook(this.title, this.pages, this.tags);

  final String title;
  final int pages;
  final List<String> tags;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HandBook ||
        other.runtimeType != runtimeType ||
        title != other.title ||
        pages != other.pages ||
        tags.length != other.tags.length) {
      return false;
    }
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != other.tags[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(title, pages, Object.hashAll(tags));

  @override
  String toString() => 'HandBook(title: $title, pages: $pages, tags: $tags)';
}

// Nanoseconds per call of [body], over two million calls.
double _measure(void Function() body) {
  for (var i = 0; i < 200000; i++) {
    body();
  }
  const calls = 2000000;
  final watch = Stopwatch()..start();
  for (var i = 0; i < calls; i++) {
    body();
  }
  return watch.elapsedMicroseconds * 1000 / calls;
}

void main() {
  Introspector.shared.register(_description);
  const tags = ['sf', 'classic'];
  final books = [
    for (var i = 0; i < 1000; i++) Book('Dune $i', i, [...tags]),
  ];
  final hand = [
    for (var i = 0; i < 1000; i++) HandBook('Dune $i', i, [...tags]),
  ];
  final bookSet = books.toSet();
  final handSet = hand.toSet();
  final probe = Book('Dune 500', 500, [...tags]);
  final handProbe = HandBook('Dune 500', 500, [...tags]);
  var sink = 0;
  final results = {
    '== introspected': _measure(() => sink += books[500] == probe ? 1 : 0),
    '== by hand': _measure(() => sink += hand[500] == handProbe ? 1 : 0),
    'hashCode introspected': _measure(() => sink ^= probe.hashCode),
    'hashCode by hand': _measure(() => sink ^= handProbe.hashCode),
    'set lookup introspected': _measure(
      () => sink += bookSet.contains(probe) ? 1 : 0,
    ),
    'set lookup by hand': _measure(
      () => sink += handSet.contains(handProbe) ? 1 : 0,
    ),
    'toString() introspected': _measure(
      () => sink += probe.toString().length,
    ),
    'toString() by hand': _measure(() => sink += handProbe.toString().length),
  };
  for (final MapEntry(:key, :value) in results.entries) {
    stdout.writeln('$key: ${value.toStringAsFixed(1)} ns');
  }
  stdout.writeln('(sink $sink)');
}
