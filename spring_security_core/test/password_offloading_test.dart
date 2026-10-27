// Password checks run on another isolate so a login does not stop the
// server's event loop, and still work when the encoder holds something an
// isolate cannot receive (they then run on the caller's isolate).
import 'dart:isolate';

import 'package:spring_security_core/spring_security_core.dart';
import 'package:spring_security_core/src/authentication/offload_io.dart';
import 'package:test/test.dart';

/// An encoder that cannot be sent to another isolate: it holds a port.
final class PortHoldingEncoder implements PasswordEncoder {
  final ReceivePort port = ReceivePort();
  final isolates = <String>[];

  @override
  String encode(String rawPassword) => 'enc:$rawPassword';

  @override
  bool matches(String rawPassword, String? encodedPassword) {
    isolates.add(Isolate.current.debugName ?? 'unnamed');
    return encodedPassword == 'enc:$rawPassword';
  }

  @override
  bool upgradeEncoding(String? encodedPassword) => false;
}

void main() {
  test('work that can be sent runs on another isolate', () async {
    final name = Isolate.current.debugName;
    final ranOn = await offload(() => Isolate.current.debugName);
    expect(ranOn, isNot(name));
  });

  test('its result and its errors come back', () async {
    expect(await offload(() => 6 * 7), 42);
    await expectLater(
      offload<int>(() => throw StateError('failed there')),
      throwsA(isA<StateError>()),
    );
  });

  test("work that captures something unsendable runs on the caller's "
      'isolate instead', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    final name = Isolate.current.debugName;

    final ranOn = await offload(() {
      port.sendPort; // captured: a ReceivePort cannot be sent
      return Isolate.current.debugName;
    });

    expect(ranOn, name);
  });

  test('a login with an encoder that cannot be sent still checks the '
      'password', () async {
    final encoder = PortHoldingEncoder();
    addTearDown(encoder.port.close);
    final provider = DaoAuthenticationProvider(
      InMemoryUserDetailsManager([
        User.withUsername('ada').password('enc:secret').build(),
      ]),
      passwordEncoder: encoder,
    );

    final ok = await provider.authenticate(
      UsernamePasswordAuthenticationToken.unauthenticated('ada', 'secret'),
    );
    expect(ok!.isAuthenticated, isTrue);
    await expectLater(
      provider.authenticate(
        UsernamePasswordAuthenticationToken.unauthenticated('ada', 'wrong'),
      ),
      throwsA(isA<BadCredentialsException>()),
    );
    expect(encoder.isolates, hasLength(2));
  });
}
