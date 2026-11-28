import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:test/test.dart';

IpAddress _ip(String text) => IpAddress.parse(text);

Matcher _denied(String reason) => throwsA(
  isA<FilteredHostException>()
      .having((error) => error.reason, 'reason', contains(reason))
      .having((error) => error.isRetryable, 'isRetryable', isFalse),
);

void main() {
  group('IpAddress', () {
    test('reads IPv4 strictly and IPv6 in every form', () {
      expect(_ip('10.0.0.5').bytes, [10, 0, 0, 5]);
      expect(_ip('[::1]').toString(), '::1');
      expect(_ip('fe80::1%en0').toString(), 'fe80::1');
      expect(_ip('2001:DB8:0:0:0:0:0:7').toString(), '2001:db8::7');
      for (final notALiteral in [
        'api.neon.books',
        '0x7f.1',
        '0177.0.0.1',
        '127.1',
        '256.0.0.1',
        '',
      ]) {
        expect(IpAddress.tryParse(notALiteral), isNull, reason: notALiteral);
      }
    });

    test('an IPv6 address carrying an IPv4 one is that IPv4 address', () {
      expect(_ip('::ffff:127.0.0.1').embeddedIPv4, _ip('127.0.0.1'));
      expect(_ip('64:ff9b::a9fe:a9fe').embeddedIPv4, _ip('169.254.169.254'));
      expect(_ip('2002:0a00:0001::').embeddedIPv4, _ip('10.0.0.1'));
      expect(_ip('::1').embeddedIPv4, isNull);
      expect(_ip('2001:db8::1').embeddedIPv4, isNull);
    });

    test('CIDR blocks of IPv4 and IPv6', () {
      final private = IpAddressRange.parse('172.16.0.0/12');
      expect(private.contains(_ip('172.31.255.1')), isTrue);
      expect(private.contains(_ip('172.32.0.1')), isFalse);
      expect(private.contains(_ip('::ffff:172.20.0.1')), isTrue);
      final ula = IpAddressRange.parse('fd00::/8');
      expect(ula.contains(_ip('fd12::1')), isTrue);
      expect(ula.contains(_ip('fe80::1')), isFalse);
      expect(private.covers(IpAddressRange.parse('172.16.4.0/24')), isTrue);
      expect(private.covers(IpAddressRange.parse('0.0.0.0/0')), isFalse);
      expect(() => IpAddressRange.parse('10.0.0.0/33'), throwsFormatException);
    });
  });

  group('InetAddressFilter, as Spring Boot 4.1', () {
    test('factories and combinators', () {
      final filter = InetAddressFilter.of([
        '192.168.0.0/24',
      ]).andNot(InetAddressFilter.of(['192.168.0.1']));
      expect(filter.matches(_ip('192.168.0.7')), isTrue);
      expect(filter.matches(_ip('192.168.0.1')), isFalse);
      expect(
        InetAddressFilter.externalAddresses.matches(_ip('8.8.8.8')),
        isTrue,
      );
      expect(
        InetAddressFilter.externalAddresses.matches(_ip('10.0.0.1')),
        isFalse,
      );
      expect(InetAddressFilter.internalAddresses.matches(_ip('::1')), isTrue);
      expect(InetAddressFilter.multicast.matches(_ip('224.0.0.1')), isTrue);
      expect(InetAddressFilter.routable.matches(_ip('0.0.0.0')), isFalse);
      expect(InetAddressFilter.none.negate().matches(_ip('1.1.1.1')), isTrue);
      expect(
        InetAddressFilter.adapt((a) => a.isV4)
            .or(InetAddressFilter.none)
            .matches(_ip('::2')),
        isFalse,
      );
    });
  });

  group('AllowedAddresses: the host of the URL', () {
    final allowed = AllowedAddresses([
      'api.neon.books',
      '*.cdn.neon.books',
      'https://auth.neon.books/realms/shop',
      '203.0.113.7',
      '198.51.100.0/24',
    ]);

    test('host names on the list, in any case, a trailing dot ignored', () {
      allowed
        ..checkUrl(Uri.parse('https://API.neon.books./books'))
        ..checkUrl(Uri.parse('https://eu.cdn.neon.books/a.png'))
        ..checkUrl(Uri.parse('https://auth.neon.books/token'));
      expect(
        () => allowed.checkUrl(Uri.parse('https://cdn.neon.books/')),
        _denied('not on the allow list'),
      );
      expect(
        () => allowed.checkUrl(Uri.parse('https://evil.example/')),
        _denied('not on the allow list'),
      );
    });

    test('a relative URL (the page in a browser) passes', () {
      allowed.checkUrl(Uri.parse('/api/books'));
    });

    test('address literals by address and block', () {
      allowed
        ..checkUrl(Uri.parse('http://203.0.113.7/'))
        ..checkUrl(Uri.parse('http://198.51.100.20:8080/'));
      expect(
        () => allowed.checkUrl(Uri.parse('http://8.8.8.8/')),
        _denied('not on the allow list'),
      );
    });

    test('loopback and private literals are denied until listed', () {
      final none = AllowedAddresses(['*']);
      for (final url in [
        'http://127.0.0.1/',
        'http://[::1]/',
        'http://10.1.2.3/',
        'http://192.168.1.1/',
        'http://[fd00::1]/',
        'http://[::ffff:127.0.0.1]/',
        'http://0.0.0.0/',
      ]) {
        expect(
          () => none.checkUrl(Uri.parse(url)),
          _denied('which is denied unless'),
          reason: url,
        );
      }
      AllowedAddresses(['10.0.0.0/8', '::1', '127.0.0.1'])
        ..checkUrl(Uri.parse('http://10.1.2.3/'))
        ..checkUrl(Uri.parse('http://[::1]:8080/'))
        ..checkUrl(Uri.parse('http://[::ffff:127.0.0.1]/'));
    });

    test('a block wider than the restricted one opens nothing in it', () {
      final wide = AllowedAddresses(['0.0.0.0/0', '::/0'])
        ..checkUrl(Uri.parse('http://8.8.8.8/'));
      expect(
        () => wide.checkUrl(Uri.parse('http://10.0.0.1/')),
        _denied('private'),
      );
      expect(
        () => wide.checkUrl(Uri.parse('http://[fe80::1]/')),
        _denied('link-local'),
      );
    });

    test('cloud metadata is denied unless its own address is listed', () {
      for (final entries in [
        ['*'],
        ['169.254.0.0/16'],
        ['0.0.0.0/0'],
        ['fd00::/8'],
      ]) {
        final list = AllowedAddresses(entries);
        expect(
          () => list.checkUrl(Uri.parse('http://169.254.169.254/latest')),
          _denied('cloud metadata'),
          reason: '$entries',
        );
        expect(
          () => list.checkUrl(Uri.parse('http://[fd00:ec2::254]/')),
          _denied('cloud metadata'),
          reason: '$entries',
        );
      }
      AllowedAddresses([
        '169.254.169.254',
      ]).checkUrl(Uri.parse('http://169.254.169.254/latest'));
      // The link-local block opens the rest of it.
      AllowedAddresses([
        '169.254.0.0/16',
      ]).checkUrl(Uri.parse('http://169.254.1.1/'));
    });

    test('the message names the remedy', () {
      final list = AllowedAddresses.none(
        remedy: 'add it to spring.http.clients.allowed-addresses',
      );
      expect(
        () => list.checkUrl(Uri.parse('https://api.neon.books/')),
        throwsA(
          isA<FilteredHostException>().having(
            (error) => error.message,
            'message',
            'Outgoing call to "api.neon.books" denied: the host is not on '
                'the allow list; add it to '
                'spring.http.clients.allowed-addresses',
          ),
        ),
      );
    });

    test('entries that are no host, address or block are refused', () {
      for (final entry in [
        '',
        'api.neon.books:8443',
        'a/b',
        'a*.b',
        '1.2.3.4/40',
      ]) {
        expect(
          () => AllowedAddresses([entry]),
          throwsArgumentError,
          reason: entry,
        );
      }
    });
  });

  group('AllowedAddresses: resolved addresses (DNS rebinding)', () {
    test('a name on the list opens only public addresses', () {
      final list = AllowedAddresses(['api.neon.books']);
      expect(
        list.allowedAddressesOf('api.neon.books', [_ip('93.184.215.14')]),
        [
          _ip('93.184.215.14'),
        ],
      );
      expect(
        () => list.allowedAddressesOf('api.neon.books', [_ip('127.0.0.1')]),
        _denied('it resolves to 127.0.0.1 (loopback)'),
      );
      expect(
        () => list.allowedAddressesOf('api.neon.books', [
          _ip('169.254.169.254'),
        ]),
        _denied('cloud metadata'),
      );
    });

    test('the denied addresses of a mixed answer are dropped', () {
      final list = AllowedAddresses(['api.neon.books']);
      expect(
        list.allowedAddressesOf('api.neon.books', [
          _ip('10.0.0.7'),
          _ip('93.184.215.14'),
          _ip('::ffff:127.0.0.1'),
        ]),
        [_ip('93.184.215.14')],
      );
    });

    test('a private network is opened by its block', () {
      final list = AllowedAddresses(['inventory.internal', '10.20.0.0/16']);
      expect(
        list.allowedAddressesOf('inventory.internal', [_ip('10.20.1.2')]),
        [
          _ip('10.20.1.2'),
        ],
      );
      expect(
        () => list.allowedAddressesOf('inventory.internal', [_ip('10.21.0.1')]),
        _denied('private'),
      );
    });

    test('localhost may resolve to loopback, nothing else private', () {
      final list = AllowedAddresses(['localhost', '*.localhost']);
      expect(
        list.allowedAddressesOf('localhost', [_ip('127.0.0.1'), _ip('::1')]),
        [
          _ip('127.0.0.1'),
          _ip('::1'),
        ],
      );
      expect(list.allowedAddressesOf('app.localhost', [_ip('127.0.0.1')]), [
        _ip('127.0.0.1'),
      ]);
      expect(
        () => list.allowedAddressesOf('localhost', [_ip('10.0.0.1')]),
        _denied('private'),
      );
      // The literal is not the name.
      expect(
        () => list.checkUrl(Uri.parse('http://127.0.0.1/')),
        _denied('loopback'),
      );
    });

    test('the InetAddressFilter must match as well', () {
      final list = AllowedAddresses([
        'api.neon.books',
      ], filter: InetAddressFilter.of(['93.184.215.0/24']));
      expect(
        list.allowedAddressesOf('api.neon.books', [_ip('93.184.215.14')]),
        [
          _ip('93.184.215.14'),
        ],
      );
      expect(
        () => list.allowedAddressesOf('api.neon.books', [_ip('8.8.8.8')]),
        _denied('InetAddressFilter'),
      );
    });
  });

  group('AllowedAddresses.allowHostName: names learned at run time', () {
    test('a plain name joins the list, its public addresses only', () {
      final list = AllowedAddresses(['sso.neon.books']);
      expect(
        () => list.checkUrl(Uri.parse('https://token.neon.books/t')),
        _denied('not on the allow list'),
      );
      expect(list.allowHostName('Token.Neon.Books.'), isTrue);
      list.checkUrl(Uri.parse('https://token.neon.books/t'));
      expect(
        list.allowedAddressesOf('token.neon.books', [_ip('93.184.215.14')]),
        [_ip('93.184.215.14')],
      );
      expect(
        () => list.allowedAddressesOf('token.neon.books', [
          _ip('169.254.169.254'),
        ]),
        _denied('cloud metadata'),
      );
    });

    test('never a literal, a block, a wildcard or a localhost name', () {
      final list = AllowedAddresses.none();
      for (final refused in [
        '',
        ' ',
        '169.254.169.254',
        '10.0.0.5',
        '::1',
        '[::1]',
        '10.0.0.0/8',
        '*',
        '*.neon.books',
        'localhost',
        'app.localhost',
        'api.neon.books:8443',
        'user@api.neon.books',
      ]) {
        expect(list.allowHostName(refused), isFalse, reason: refused);
      }
      expect(list.toString(), 'AllowedAddresses()');
      expect(
        () => list.checkUrl(Uri.parse('http://169.254.169.254/')),
        _denied('cloud metadata'),
      );
    });
  });
}
