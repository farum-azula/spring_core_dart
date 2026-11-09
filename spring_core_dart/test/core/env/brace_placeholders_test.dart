// {{key}} placeholders: a known key replaced, an unknown one kept, \{{
// written as text, ${...} left alone.
import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  final values = {'site.version': '0.7.2', 'name': 'Ada'};
  String resolve(String text) => BracePlaceholders.resolve(text, values.get);

  test('a known key is replaced, spaces allowed', () {
    expect(resolve('^{{site.version}} and {{ name }}'), '^0.7.2 and Ada');
  });

  test("an unknown key stays, so another tool's placeholder is kept", () {
    expect(resolve('GET {{baseUrl}}/books'), 'GET {{baseUrl}}/books');
    expect(resolve('{{}} {{a b}}'), '{{}} {{a b}}');
  });

  test(r'\{{ writes {{; ${...} is not touched', () {
    expect(resolve(r'\{{site.version}}'), '{{site.version}}');
    expect(
      resolve(r'${site.version} {{site.version}}'),
      r'${site.version} 0.7.2',
    );
  });
}

extension on Map<String, String> {
  String? get(String key) => this[key];
}
