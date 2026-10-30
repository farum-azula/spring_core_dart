// The Maven modules tool/check_vulnerabilities.dart --maven reads from
// what tool/gradle/build_classpath.init.gradle prints.
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
}
