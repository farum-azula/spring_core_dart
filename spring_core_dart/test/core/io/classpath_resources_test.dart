@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

void main() {
  ClasspathResources.registerAll(const {
    'app/greeting.txt': EmbeddedResource.text('hello'),
    'app/logo.bin': EmbeddedResource.base64('AAEC'),
    'config/application.properties': EmbeddedResource.text('from=classpath'),
  });

  test('classpath: serves embedded text and binary files', () {
    final loader = DefaultResourceLoader();
    expect(
      loader.getResource('classpath:app/greeting.txt').readAsStringSync(),
      'hello',
    );
    expect(loader.getResource('classpath:/app/logo.bin').readAsBytesSync(), [
      0,
      1,
      2,
    ]);
    expect(
      loader.getResource('classpath:app/./greeting.txt').description,
      'class path resource [app/greeting.txt]',
    );
  });

  test('the first registration of a path wins', () {
    ClasspathResources.registerAll(const {
      'app/greeting.txt': EmbeddedResource.text('other'),
    });
    expect(
      ClasspathResources.resolve('app/greeting.txt').readAsStringSync(),
      'hello',
    );
  });

  test('@Value-style conversion String -> Resource', () {
    final resource = DefaultConversionService().convert<Resource>(
      'classpath:app/greeting.txt',
    );
    expect(resource.readAsStringSync(), 'hello');
  });

  test('config data reads classpath:/config/ by default', () {
    final environment = StandardEnvironment(systemEnvironment: {});
    ConfigDataEnvironment(environment).processAndApplySync();
    expect(environment.getProperty('from'), 'classpath');
  });

  test('an unknown path is not embedded', () {
    expect(ClasspathResources.resolve('missing.txt').exists(), isFalse);
  });

  test('added directories shadow embedded files, newest first', () {
    final test = Directory.systemTemp.createTempSync('cp_test_');
    final other = Directory.systemTemp.createTempSync('cp_other_');
    addTearDown(() {
      test.deleteSync(recursive: true);
      other.deleteSync(recursive: true);
    });
    File('${test.path}/app/greeting.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('from test resources');
    File('${test.path}/only-in-test.txt').writeAsStringSync('test only');
    File('${other.path}/only-in-test.txt').writeAsStringSync('newest');

    final removeTest = ClasspathResources.addDirectory('${test.path}/');
    final loader = DefaultResourceLoader();
    String read(String location) =>
        loader.getResource(location).readAsStringSync();

    expect(read('classpath:app/greeting.txt'), 'from test resources');
    expect(read('classpath:/only-in-test.txt'), 'test only');
    expect(read('classpath:app/logo.bin'), isNotEmpty); // embedded fallback

    final removeOther = ClasspathResources.addDirectory(other.path);
    expect(ClasspathResources.directories, [other.path, test.path]);
    expect(read('classpath:only-in-test.txt'), 'newest');
    removeOther();
    removeOther(); // idempotent

    removeTest();
    expect(ClasspathResources.directories, isEmpty);
    expect(read('classpath:app/greeting.txt'), isNot('from test resources'));
    expect(ClasspathResources.resolve('only-in-test.txt').exists(), isFalse);
  });
}
