// What the debug tab may show of a member whose name looks secret, or of
// a value kept for its caller.
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter_signals/spring_boot_starter_flutter_signals.dart';

void main() {
  test('a field or computed value whose name looks secret shows no value '
      '(S-04)', () {
    final token = ValueMember('Session.accessToken', 'eyJ.secret');
    expect(token.hidden, isTrue);
    final tokenRow = SignalsRow.member(token, null);
    expect(tokenRow.tone, SignalsValueTone.locked);
    expect(tokenRow.value, isNot(contains('eyJ')));
    final plain = ValueMember('TokenStore.count', 3);
    expect(plain.hidden, isFalse);
    expect(SignalsRow.member(plain, null).value, '3');
    final computed = ComputedMember('Session.bearer', () => 'eyJ.secret');
    addTearDown(computed.dispose);
    final computedRow = SignalsRow.member(computed, null);
    expect(computedRow.tone, SignalsValueTone.locked);
    expect(computedRow.value, isNot(contains('eyJ')));
  });

  test("a computed value that becomes the caller's as the tab first reads "
      'it shows a lock, never the value', () {
    final balance = ComputedMember('Account.balance', () {
      // Read what depends on the caller, as method security does.
      CallerBoundReads.noteRead();
      return 4200;
    });
    addTearDown(balance.dispose);
    expect(balance.callerBound, isFalse, reason: 'never computed yet');

    final row = SignalsRow.member(balance, null);

    expect(balance.callerBound, isTrue);
    expect(row.tone, SignalsValueTone.locked);
    expect(row.value, isNot(contains('4200')));
  });
}
