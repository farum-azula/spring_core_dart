// AllowedOrigins against Spring 7.0.10's CorsConfiguration.checkOrigin:
// every expected value below is what Spring returned for the same
// configuration and origin (a run of CorsConfiguration, October 2026),
// except for origins longer than 1024 characters, never allowed here.
import 'dart:math';

import 'package:spring_web_dart/spring_web_dart.dart';
import 'package:spring_web_dart/src/server/allowed_origins.dart'
    show matchesOriginPattern;
import 'package:test/test.dart';

String? check(
  String? origin, {
  List<String> origins = const [],
  List<String> patterns = const [],
  bool allowCredentials = false,
}) => AllowedOrigins(
  allowedOrigins: origins,
  allowedOriginPatterns: patterns,
).checkOrigin(origin, allowCredentials: allowCredentials);

void main() {
  group('allowedOrigins, as Spring', () {
    test('compared without case; the origin is echoed as sent', () {
      const shop = ['https://shop.example'];
      expect(
        check('https://shop.example', origins: shop),
        'https://shop.example',
      );
      expect(
        check('HTTPS://SHOP.EXAMPLE', origins: shop),
        'HTTPS://SHOP.EXAMPLE',
      );
      // No default port, scheme or suffix games.
      expect(check('https://shop.example:443', origins: shop), isNull);
      expect(check('http://shop.example', origins: shop), isNull);
      expect(check('https://shop.example.evil', origins: shop), isNull);
      // Blank, or white space around: not allowed.
      expect(check(null, origins: shop), isNull);
      expect(check('', origins: shop), isNull);
      expect(check('  ', origins: shop), isNull);
      expect(check(' https://shop.example', origins: shop), isNull);
    });

    test('a trailing slash is ignored, in the value and in the origin '
        '(once)', () {
      expect(
        check('https://shop.example', origins: ['https://shop.example/']),
        'https://shop.example',
      );
      expect(
        check('https://shop.example/', origins: ['https://shop.example']),
        'https://shop.example/',
      );
      expect(
        check('https://shop.example/', origins: ['https://shop.example//']),
        isNull,
      );
      expect(
        AllowedOrigins(allowedOrigins: ['https://shop.example/'])
            .allowedOrigins,
        ['https://shop.example'],
      );
    });

    test('a value with commas lists several, trimmed; one without is '
        'kept as it is', () {
      expect(
        check(
          'https://b.example',
          origins: ['https://a.example, https://b.example'],
        ),
        'https://b.example',
      );
      expect(
        check(
          'https://a.example',
          origins: ['https://a.example,https://b.example'],
        ),
        'https://a.example',
      );
      expect(
        check('https://a.example', origins: ['https://a.example,']),
        'https://a.example',
      );
      expect(
        check(
          'https://b.example',
          origins: ['https://a.example, ,https://b.example'],
        ),
        'https://b.example',
      );
      expect(
        AllowedOrigins(
          allowedOrigins: ['https://a.example, https://b.example/'],
        ).allowedOrigins,
        ['https://a.example', 'https://b.example'],
      );
      // Not split, not trimmed.
      expect(
        check('https://shop.example', origins: [' https://shop.example']),
        isNull,
      );
      expect(check('null', origins: ['null']), 'null');
    });

    test('"*" allows every origin, but not with credentials', () {
      expect(check('https://any.example', origins: ['*']), '*');
      expect(
        check('https://x.example', origins: ['https://a.example, *']),
        '*',
      );
      expect(
        AllowedOrigins(allowedOrigins: ['https://a.example, *'])
            .allowsAnyOrigin,
        isTrue,
      );
      for (final origins in [
        ['*'],
        ['https://a.example, *'],
      ]) {
        expect(
          () => check(
            'https://x.example',
            origins: origins,
            allowCredentials: true,
          ),
          throwsA(isA<StateError>()),
        );
      }
      // Also next to patterns, as Spring.
      expect(
        () => check(
          'https://x.b.example',
          origins: ['*'],
          patterns: ['https://*.b.example'],
          allowCredentials: true,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        check(
          'https://shop.example',
          origins: ['https://shop.example'],
          allowCredentials: true,
        ),
        'https://shop.example',
      );
    });
  });

  group('allowedOriginPatterns, as Spring', () {
    test('a port list takes the listed ports only', () {
      const list = ['http://localhost:[8080,8081]'];
      expect(
        check('http://localhost:8080', patterns: list),
        'http://localhost:8080',
      );
      expect(check('http://localhost:8082', patterns: list), isNull);
      expect(check('http://localhost', patterns: list), isNull);
      expect(check('http://localhost:80801', patterns: list), isNull);
      // Not a port list (a space): a literal that matches nothing.
      expect(
        check(
          'http://localhost:8080',
          patterns: ['http://localhost:[8080, 8081]'],
        ),
        isNull,
      );
    });

    test('[*] takes any port, or none', () {
      const any = ['http://localhost:[*]'];
      expect(
        check('http://localhost:8080', patterns: any),
        'http://localhost:8080',
      );
      expect(check('http://localhost', patterns: any), 'http://localhost');
      expect(check('http://localhost:8080.evil.com', patterns: any), isNull);
      expect(check('http://localhost.evil.com', patterns: any), isNull);
      expect(check('http://localhost:', patterns: any), isNull);
      expect(check('https://localhost:8080', patterns: any), isNull);
    });

    test('* matches any part of the origin, the rest is literal and '
        'compared with case', () {
      const sub = ['https://*.example.com'];
      expect(
        check('https://a.example.com', patterns: sub),
        'https://a.example.com',
      );
      expect(
        check('https://a.b.example.com', patterns: sub),
        'https://a.b.example.com',
      );
      expect(
        check('https://a.example.com/', patterns: sub),
        'https://a.example.com/',
      );
      expect(check('https://example.com', patterns: sub), isNull);
      expect(check('https://a.example.com.evil', patterns: sub), isNull);
      expect(check('https://a.example.com.', patterns: sub), isNull);
      expect(check('http://a.example.com', patterns: sub), isNull);
      expect(check('https://a.example.com:8443', patterns: sub), isNull);
      expect(check('https://A.EXAMPLE.COM', patterns: sub), isNull);
      expect(check(' https://a.example.com', patterns: sub), isNull);
      expect(check('https://a.example.com ', patterns: sub), isNull);
      expect(
        check('https://a.example.com', patterns: ['https://*.Example.com']),
        isNull,
      );
      expect(
        check('https://SHOP.example', patterns: ['https://shop.example']),
        isNull,
      );
      expect(
        check('https://a.example.com', patterns: ['https://*.example.com/']),
        'https://a.example.com',
      );
      expect(
        check(
          'https://a.example.com:8081',
          patterns: ['https://*.example.com:[8080,8081]'],
        ),
        'https://a.example.com:8081',
      );
      expect(
        check('https://a.example.com', patterns: ['https://*.example.com:[*]']),
        'https://a.example.com',
      );
      expect(
        check('https://shop.example:8443', patterns: ['https://*']),
        'https://shop.example:8443',
      );
      expect(
        check('https://[::1]', patterns: ['https://[*]']),
        'https://[::1]',
      );
      expect(
        check('https://shop.example', patterns: ['*://shop.example']),
        'https://shop.example',
      );
      expect(check('null', patterns: ['null']), 'null');
    });

    test('a pattern "*" echoes any origin, also with credentials', () {
      expect(
        check('https://anything.example', patterns: ['*']),
        'https://anything.example',
      );
      expect(check('null', patterns: ['*']), 'null');
      expect(
        check('https://x.example', patterns: ['*'], allowCredentials: true),
        'https://x.example',
      );
    });

    test('commas split patterns, not port lists', () {
      expect(
        check(
          'https://x.b.example',
          patterns: ['https://*.a.example, https://*.b.example'],
        ),
        'https://x.b.example',
      );
      const mixed = ['http://localhost:[8080,8081], https://*.example'];
      expect(
        check('http://localhost:8081', patterns: mixed),
        'http://localhost:8081',
      );
      expect(check('https://x.example', patterns: mixed), 'https://x.example');
      expect(
        AllowedOrigins(allowedOriginPatterns: mixed).allowedOriginPatterns,
        ['http://localhost:[8080,8081]', 'https://*.example'],
      );
    });

    test('origins first, then patterns', () {
      expect(
        check(
          'https://x.b.example',
          origins: ['https://a.example'],
          patterns: ['https://*.b.example'],
        ),
        'https://x.b.example',
      );
      expect(
        check(
          'https://a.example',
          origins: ['https://a.example'],
          patterns: ['https://*.b.example'],
        ),
        'https://a.example',
      );
      expect(
        check(
          'https://c.example',
          origins: ['https://a.example'],
          patterns: ['https://*.b.example'],
        ),
        isNull,
      );
    });
  });

  group("the eighth review: a * matches any text, as Spring's .*", () {
    test('also the scheme and its //: patterns that start or end with *', () {
      for (final (pattern, origin) in [
        ('*.example.com', 'https://a.example.com'),
        ('*:[8080]', 'https://a.example:8080'),
        ('*localhost*', 'http://localhost:3000'),
        ('*://app.example', 'https://app.example'),
        ('http*://localhost:[*]', 'https://localhost:3000'),
      ]) {
        expect(check(origin, patterns: [pattern]), origin, reason: pattern);
      }
      expect(check('https://a.example:8081', patterns: ['*:[8080]']), isNull);
      expect(check('https://b.example', patterns: ['*localhost*']), isNull);
    });

    test(r'also "/", "\", "?", "#", "@" and white space, which no browser '
        'puts in an origin', () {
      for (final origin in [
        'https://evil.com/.example.com',
        'https://evil.com?.example.com',
        'https://evil.com#.example.com',
        'https://evil.com@a.example.com',
        r'https://evil.com\.example.com',
        'https://evil.com .example.com',
        'https://evil.com\t.example.com',
      ]) {
        expect(
          check(origin, patterns: ['https://*.example.com']),
          origin,
          reason: _visible(origin),
        );
      }
      expect(
        check('https://evil.com/path', patterns: ['https://*']),
        'https://evil.com/path',
      );
    });

    test("but not a line terminator, as Java's .", () {
      for (final terminator in ['\n', '\r', '\u0085', '\u2028', '\u2029']) {
        expect(
          check('https://a${terminator}b.example.com', patterns: ['https://*']),
          isNull,
          reason: _visible(terminator),
        );
        // Literal in the pattern, it matches itself.
        expect(
          check(
            'https://a${terminator}b.example.com',
            patterns: ['https://a$terminator*'],
          ),
          'https://a${terminator}b.example.com',
          reason: _visible(terminator),
        );
      }
    });
  });

  group('the seventh review: a long Origin', () {
    // A Vercel-style preview pattern with three `*`: each was a
    // backtracking class of a regular expression (16 KB took 1.7 s with
    // two, 48 KB 15.7 s; 1 MB, which dart:io accepts in a header, hours).
    const pattern = 'https://*-*-*.vercel.app';
    final huge = 'https://${'-' * (1 << 20)}x';

    test('a 1 MB origin is refused at once, whatever the patterns', () {
      final watch = Stopwatch()..start();
      expect(check(huge, patterns: [pattern]), isNull);
      expect(check(huge, patterns: ['*://*-*-*:[*]', 'https://*']), isNull);
      expect(check(huge, origins: ['*']), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('the bound: 1024 characters are checked, 1025 are not', () {
      String origin(int length) {
        const head = 'https://a-b-';
        const tail = '.vercel.app';
        return '$head${'c' * (length - head.length - tail.length)}$tail';
      }

      expect(AllowedOrigins.maxOriginLength, 1024);
      expect(origin(1024), hasLength(1024));
      expect(check(origin(1024), patterns: [pattern]), origin(1024));
      expect(check(origin(1025), patterns: [pattern]), isNull);
      expect(check(origin(1024), origins: [origin(1024)]), origin(1024));
      expect(check(origin(1025), origins: [origin(1025)]), isNull);
      expect(check(origin(1025), origins: ['*']), isNull);
    });

    test('without the bound, the match takes time linear in the origin', () {
      final watch = Stopwatch()..start();
      expect(matchesOriginPattern(pattern, huge), isFalse);
      expect(matchesOriginPattern('*://*-*-*.app:[*]', '$huge:1'), isFalse);
      final long = 'https://${'a-' * (1 << 19)}x.vercel.app';
      expect(matchesOriginPattern(pattern, long), isTrue);
      expect(
        matchesOriginPattern('https://*-*.*.*:[8080,8081]', '$long:8081'),
        isTrue,
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test("a `*` matches what Spring's regular expression matches, for "
        'every UTF-16 code unit', () {
      final reference = RegExp('^a$_javaDot*b\$');
      for (var unit = 0; unit <= 0xFFFF; unit++) {
        final origin = 'a${String.fromCharCode(unit)}b';
        if (matchesOriginPattern('a*b', origin) != reference.hasMatch(origin)) {
          fail('U+${unit.toRadixString(16)}');
        }
      }
    });

    test("the same answers as Spring's regular expression, on 50 000 "
        'random patterns and origins', () {
      final random = Random(7);
      const units = [
        'a', 'b', 'A', '-', '.', ':', '1', '8', '0', '[', ']', ',', //
        '/', r'\', '?', '#', '@', ' ', '\t', '\n', '\r', '\u00a0', //
        '\u2028', '\u2029', '\u0085', '\u00e9', '%',
      ];
      String unit({required bool stars}) => stars && random.nextInt(4) == 0
          ? '*'
          : units[random.nextInt(units.length)];
      String text(int max, {bool stars = false}) => [
        for (var i = random.nextInt(max + 1); i > 0; i--) unit(stars: stars),
      ].join();
      const ports = ['', ':[*]', ':[8080]', ':[1,80,8080]', ':[]', ':[8,]'];
      for (var i = 0; i < 50000; i++) {
        final pattern =
            text(8, stars: true) + ports[random.nextInt(ports.length)];
        final origin = switch (random.nextInt(3)) {
          // Something close to the pattern: its stars filled in.
          0 =>
            pattern
                .replaceAll(RegExp(r':\[(\*|[\d,]*)\]$'), ':80')
                .replaceAllMapped('*', (_) => text(3)),
          _ => text(12) + (random.nextBool() ? ':8080' : ''),
        };
        expect(
          matchesOriginPattern(pattern, origin),
          _reference(pattern)?.hasMatch(origin) ?? true,
          reason: '${_visible(pattern)} ${_visible(origin)}',
        );
      }
    });
  });
}

// [text] with its invisible characters escaped, for failure messages.
String _visible(String text) => Uri.encodeComponent(text);

// What the `.` of a Java regular expression matches: any character but a
// line terminator (Dart's `.` takes U+0085).
const _javaDot = r'[^\n\r\u0085\u2028\u2029]';

// A pattern compiled as Spring 7.0.10's CorsConfiguration.OriginPattern
// compiles it: the port list cut off with PORTS_PATTERN, the rest quoted
// (`\Q...\E`) with each `*` a `.*`, then `(:\d+)?` for `[*]` or
// `:(p1|p2)` (`null`: the pattern "*", any origin).
RegExp? _reference(String pattern) {
  if (pattern == '*') {
    return null;
  }
  var value = pattern;
  String? ports;
  if (RegExp('^($_javaDot*):\\[(\\*|\\d+(?:,\\d+)*)\\]\$').firstMatch(pattern)
      case final match?) {
    value = match[1]!;
    ports = match[2];
  }
  final regex = StringBuffer('^')
    ..write(
      value.split('*').map(RegExp.escape).join('$_javaDot*'),
    );
  if (ports != null) {
    regex.write(
      ports == '*' ? r'(?::\d+)?' : ':(?:${ports.replaceAll(',', '|')})',
    );
  }
  regex.write(r'$');
  return RegExp(regex.toString());
}
