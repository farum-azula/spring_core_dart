// The Maven modules tool/check_vulnerabilities.dart --maven reads from
// what tool/gradle/build_classpath.init.gradle prints.
import 'dart:io';

import 'package:test/test.dart';

import '../check_vulnerabilities.dart';

void main() {
  test('reads group:name:version lines, once each', () {
    expect(
      mavenModules('''
CLASSPATH org.bouncycastle:bcprov-jdk18on:1.86
CLASSPATH com.google.guava:guava:33.7.2-jre
CLASSPATH org.bouncycastle:bcprov-jdk18on:1.86
io.netty:netty-codec-http:4.1.139.Final
Some other output of Gradle
CLASSPATH not-a-module
'''),
      {
        ('org.bouncycastle:bcprov-jdk18on', '1.86'),
        ('com.google.guava:guava', '33.7.2-jre'),
        ('io.netty:netty-codec-http', '4.1.139.Final'),
      },
    );
  });

  test('every Flutter package of the repository has its lock file checked', () {
    final repository = Directory(
      Directory.current.path.endsWith('/tool')
          ? Directory.current.parent.path
          : Directory.current.path,
    );
    final listed = git(repository, ['ls-files', '*pubspec.yaml']);
    final flutter = [
      for (final path in listed)
        if (File('${repository.path}/$path')
            .readAsStringSync()
            .contains('sdk: flutter'))
          path.replaceFirst('pubspec.yaml', 'pubspec.lock'),
    ];
    expect(flutterLocks.toSet(), containsAll(flutter));
  });
}

List<String> git(Directory directory, List<String> arguments) {
  final result = Process.runSync(
    'git',
    arguments,
    workingDirectory: directory.path,
  );
  return [
    for (final line in (result.stdout as String).split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}
