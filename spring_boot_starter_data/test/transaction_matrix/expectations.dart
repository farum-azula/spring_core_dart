// The propagation matrix as a model: what each of the 224 combinations of an
// outer method (none, or one of the seven propagations), an inner method
// (the seven) and a variant must give, written from Spring's rules and not
// from the starter's code. The Spring reference gives the same outcomes
// (the differential test); this keeps the PostgreSQL suite self-contained.
//
// An outer method without a transaction (none, supports, notSupported,
// never) writes its rows in autocommit; with one (required, requiresNew,
// nested) its rows follow the transaction. The inner method then runs:
//
// - joined: the outer's transaction (a failure only marks it rollback-only),
// - savepoint: a nested one (a failure rolls back to it),
// - new: in a transaction of its own (committed or rolled back alone),
// - none: in autocommit,
// - refused: an `IllegalTransactionStateException` before it runs.
import 'comparison.dart';
import 'env.dart';
import 'expected_outcomes.dart';

const _illegal = 'IllegalTransactionStateException';

/// What the scenario [id] must give.
Outcome expectedOutcome(String id) {
  if (id.startsWith('propagation/')) {
    final [_, outer, inner, variant] = id.split('/');
    return _propagation(outer, inner, variant);
  }
  final known = knownDifferences[id];
  if (known != null) {
    return known.starter;
  }
  return expectedOutcomes[id] ??
      (throw StateError('No expected outcome for $id'));
}

Outcome _propagation(String outer, String inner, String variant) {
  if (outer == 'mandatory') {
    // Called with no transaction: refused before its body.
    return {'outer': _illegal, 'rows': <String>[]};
  }
  final inTx = const {'required', 'requiresNew', 'nested'}.contains(outer);
  final how = inTx
      ? switch (inner) {
          'required' || 'supports' || 'mandatory' => 'joined',
          'nested' => 'savepoint',
          'requiresNew' => 'new',
          'notSupported' => 'none',
          _ => null, // never
        }
      : switch (inner) {
          'required' || 'requiresNew' || 'nested' => 'new',
          'supports' || 'notSupported' || 'never' => 'none',
          _ => null, // mandatory
        };
  final innerFails =
      variant == 'innerThrowsCaught' || variant == 'innerThrowsPropagates';
  final propagates = variant == 'innerThrowsPropagates';
  final innerThrown = how == null ? _illegal : (innerFails ? 'Boom' : null);

  // How the transaction of the outer method ends.
  final outerError = switch (variant) {
    'innerThrowsPropagates' => innerThrown,
    'outerThrowsAfter' => 'Boom',
    _ => null,
  };
  final markedRollbackOnly = how == 'joined' && innerFails && !propagates;
  final committed = inTx && outerError == null && !markedRollbackOnly;

  final out = <String, Object?>{'outerTx': inTx ? 'tx' : 'none'};
  if (how != null) {
    out['innerSeesO1'] = !inTx || how == 'joined' || how == 'savepoint' ? 1 : 0;
    out['innerTx'] = how == 'savepoint' || how == 'joined' ? 'same' : how;
  }
  if (!propagates) {
    out['inner'] = innerThrown ?? 'ok';
    // What the outer method sees of the inner one's row.
    out['outerSeesI'] = switch (how) {
      null => 0,
      'none' || 'joined' => 1,
      _ => innerFails ? 0 : 1,
    };
  }
  out['outer'] =
      outerError ??
      (inTx && markedRollbackOnly ? 'UnexpectedRollbackException' : 'ok');

  // The rows that stay.
  final reachedO2 = !propagates;
  final rows = <String>[
    if (!inTx || committed) 'o1',
    if (reachedO2 && (!inTx || committed)) 'o2',
    if (switch (how) {
      null => false,
      'none' => true,
      'new' => !innerFails,
      'joined' => committed,
      _ => committed && !innerFails, // savepoint
    })
      'i',
  ]..sort();
  out['rows'] = rows;
  return out;
}
