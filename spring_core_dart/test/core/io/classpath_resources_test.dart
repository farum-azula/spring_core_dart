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
}
