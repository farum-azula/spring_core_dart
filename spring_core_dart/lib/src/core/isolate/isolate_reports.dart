/// A part of what each isolate of a pool tells the primary every few
/// seconds: a bean that implements it is asked in its own isolate, and
/// what it answers is kept in the primary's [IsolateReports] under [id].
///
/// For numbers kept per isolate that are wanted for the whole
/// application: the web starter's request rate is one.
///
/// ```dart
/// @Component()
/// class BasketCount implements IsolateReporter {
///   BasketCount(this.baskets);
///   final Baskets baskets;
///
///   @override
///   String get id => 'baskets';
///   @override
///   Object? report() => baskets.open; // of this isolate
/// }
/// ```
abstract interface class IsolateReporter {
  /// The report's name, one per kind of report.
  String get id;

  /// What this isolate has to tell now: JSON values only (numbers, text,
  /// lists and maps of them), which cross isolates.
  Object? report();
}

/// The last report of every isolate of the pool, by isolate and by
/// [IsolateReporter.id]: the bean `isolateReports`. Without a pool it has
/// the reports of the one isolate, asked when read.
final class IsolateReports {
  /// The reports of this isolate's [reporters], and of the others once
  /// they [put] theirs.
  IsolateReports(this.reporters);

  /// The reporters of this isolate.
  final List<IsolateReporter> reporters;

  final _remote = <String, Map<String, Object?>>{};

  /// Asks the other isolates for their reports now; set by the pool that
  /// has them. `null` without a pool.
  Future<void> Function()? onRefresh;

  /// Brings the other isolates' reports up to date: completes once they
  /// have answered (or shortly after, without those that did not). At
  /// once without a pool. Reports are otherwise as old as the last
  /// refresh.
  Future<void> refresh() async => await onRefresh?.call();

  /// What this isolate's reporters tell now, by id.
  Map<String, Object?> own() => {
    for (final reporter in reporters) reporter.id: reporter.report(),
  };

  /// Keeps the [reports] of the isolate named [isolate]; the pool calls
  /// it in the primary.
  void put(String isolate, Map<String, Object?> reports) =>
      _remote[isolate] = reports;

  /// Forgets the isolate named [isolate], which left the pool.
  void remove(String isolate) => _remote.remove(isolate);

  /// The reports named [id] by isolate: this isolate's (under [own]'s
  /// name) first, then the others in the order of their numbers
  /// (`isolate-2` before `isolate-10`).
  Map<String, Object?> of(String id, {required String own}) {
    final others = _remote.keys.toList()
      ..sort(
        (a, b) => a.length != b.length
            ? a.length.compareTo(b.length)
            : a.compareTo(b),
      );
    return {
      for (final reporter in reporters)
        if (reporter.id == id) own: reporter.report(),
      for (final isolate in others)
        if (_remote[isolate]!.containsKey(id)) isolate: _remote[isolate]![id],
    };
  }
}
