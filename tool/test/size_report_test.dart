// tool/size_report.dart: counting the generated sources and aggregating the
// VM's instruction sizes, on small fixtures (nothing is compiled).
import 'dart:convert';

import 'package:test/test.dart';

import '../size_report.dart';

void main() {
  group('countLines', () {
    test('counts a last line without a newline', () {
      expect(countLines(utf8.encode('')), 0);
      expect(countLines(utf8.encode('a')), 1);
      expect(countLines(utf8.encode('a\n')), 1);
      expect(countLines(utf8.encode('a\nb')), 2);
      expect(countLines(utf8.encode('a\n\nb\n')), 3);
    });
  });

  group('countSources', () {
    final report = countSources(
      {
        'pkg_b/lib/b.spring.dart': utf8.encode('x\ny\n'),
        'example/app/bin/main.spring.dart': utf8.encode('one\n'),
        'pkg_b/example/e.spring.dart': utf8.encode('a\nb\nc'),
        'loose.spring.dart': utf8.encode('z\n'),
      },
      packageDirs: {'.', 'pkg_b', 'example/app'},
    );

    test('lists the files by path', () {
      expect(report.files.map((file) => file.path), [
        'example/app/bin/main.spring.dart',
        'loose.spring.dart',
        'pkg_b/example/e.spring.dart',
        'pkg_b/lib/b.spring.dart',
      ]);
    });

    test('totals lines and bytes', () {
      expect(report.totalLines, 1 + 1 + 3 + 2);
      expect(report.totalBytes, 4 + 2 + 5 + 4);
    });

    test('groups by the deepest package directory', () {
      expect(report.byPackage, {
        '.': (lines: 1, bytes: 2),
        'example/app': (lines: 1, bytes: 4),
        'pkg_b': (lines: 5, bytes: 9),
      });
    });

    test('packageOf needs a whole directory name', () {
      expect(packageOf('pkg_bb/a.spring.dart', {'pkg_b'}), '.');
      expect(packageOf('a/b/c.dart', {'a', 'a/b'}), 'a/b');
    });

    test('toJson has the totals', () {
      expect(report.toJson(), containsPair('generatedLines', 7));
    });
  });

  group('aggregateInstructions', () {
    const root = '/repo';
    final report = aggregateInstructions([
      {'l': 'dart:core', 'c': 'String', 'n': 'trim', 's': 100},
      {'l': 'dart:core', 'n': 'print', 's': 50},
      {'l': 'package:foo/src/a.dart', 'n': 'a', 's': 30},
      {'l': 'package:foo/b.dart', 'c': 'B', 'n': 'b', 's': 20},
      {
        'l': 'package:foo/app.spring.dart',
        'c': 'ServiceProxy',
        'n': 'call',
        's': 40,
      },
      {'l': 'package:foo/app.spring.dart', 'n': r'$init', 's': 10},
      {
        'l': 'file:///repo/example/app/bin/main.spring.dart',
        'c': 'RepoProxy',
        'n': 'save',
        's': 25,
      },
      {
        'l': 'file:///repo/example/app/bin/main.spring.dart',
        'c': 'ProxyFactory',
        'n': 'make',
        's': 5,
      },
      {'n': 'stub', 's': 7},
    ], repoRoot: root);

    test('totals every function', () {
      expect(report.totalInstructions, 287);
    });

    test('sums the .spring.dart libraries, largest first', () {
      expect(report.generatedByLibrary, {
        'package:foo/app.spring.dart': 50,
        'example/app/bin/main.spring.dart': 30,
      });
      expect(
        report.generatedByLibrary.keys.first,
        'package:foo/app.spring.dart',
      );
      expect(report.generatedInstructions, 80);
    });

    test('counts the ...Proxy classes of generated libraries only', () {
      expect(report.proxyInstructions, 65);
    });

    test('groups packages, keeps dart: and relativizes file:', () {
      expect(report.topLibraries, {
        'dart:core': 150,
        'package:foo': 100,
        'example/app/bin/main.spring.dart': 30,
        '<unknown>': 7,
      });
    });

    test('keeps the largest $topLibraryCount libraries', () {
      final many = aggregateInstructions([
        for (var i = 0; i < 20; i++) {'l': 'package:p$i/a.dart', 's': i},
      ], repoRoot: root);
      expect(many.topLibraries, hasLength(topLibraryCount));
      expect(many.topLibraries.keys.first, 'package:p19');
    });
  });

  group('checkBudget', () {
    final report = {
      'sources': {'generatedLines': 100},
      'apps': {
        'a': {'generatedInstructions': 50, 'snapshotBytes': 1000},
      },
    };

    test('passes within the budget', () {
      expect(
        checkBudget(report, {
          'sources': {'generatedLines': 100},
          'apps': {
            'a': {'generatedInstructions': 50, 'snapshotBytes': 1000},
            'not_compiled': {'generatedInstructions': 0},
          },
        }),
        isEmpty,
      );
    });

    test('gives the AOT measures 1% of headroom, not the sources', () {
      expect(
        checkBudget(report, {
          'sources': {'generatedLines': 100},
          'apps': {
            'a': {'generatedInstructions': 50, 'snapshotBytes': 990},
          },
        }),
        isEmpty,
      );
      expect(
        checkBudget(report, {
          'sources': {'generatedLines': 99},
          'apps': {
            'a': {'generatedInstructions': 50, 'snapshotBytes': 989},
          },
        }),
        [
          'sources.generatedLines: 100 > 99 (+1)',
          'apps.a.snapshotBytes: 1000 > 989 (+11)',
        ],
      );
    });

    test('reports what exceeds it', () {
      expect(
        checkBudget(report, {
          'sources': {'generatedLines': 90},
          'apps': {
            'a': {'generatedInstructions': 40, 'snapshotBytes': 1000},
          },
        }),
        [
          'sources.generatedLines: 100 > 90 (+10)',
          'apps.a.generatedInstructions: 50 > 40 (+10)',
        ],
      );
    });
  });
}
