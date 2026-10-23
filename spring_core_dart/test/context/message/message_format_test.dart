import 'package:spring_core_dart/context.dart';
import 'package:test/test.dart';

void main() {
  String f(String pattern, [List<Object?> args = const []]) =>
      MessageFormat.format(pattern, args);

  test('placeholders and missing arguments', () {
    expect(f('Hello {0}, {1}!', ['Ada', 'Linus']), 'Hello Ada, Linus!');
    expect(f('{1} {0}', ['a', 'b']), 'b a');
    expect(f('{0} and {2}', ['x']), 'x and {2}');
    expect(f('null: {0}', [null]), 'null: null');
    expect(f('{ 0 }', ['spaced']), 'spaced');
  });

  test('quoting', () {
    expect(f("It''s {0}", ['ok']), "It's ok");
    expect(f("'{0}' is literal", ['x']), '{0} is literal');
    expect(f("'quoted ''inner'' text' {0}", ['x']), "quoted 'inner' text x");
    expect(f("unterminated 'quote {0}", ['x']), 'unterminated quote {0}');
  });

  test('numbers', () {
    expect(f('{0}', [1234567]), '1,234,567');
    expect(f('{0}', [1234.5678]), '1,234.568');
    expect(f('{0}', [-0.0001]), '0');
    expect(f('{0,number}', [1000.5]), '1,000.5');
    expect(f('{0,number,integer}', [2.5]), '2');
    expect(f('{0,number,integer}', [3.5]), '4');
    expect(f('{0,number,percent}', [0.256]), '26%');
    expect(f('{0,number,currency}', [3]), '3.00');
    expect(f('{0,number,#.##}', [3.14159]), '3.14');
    expect(f('{0,number,0.00}', [3.1]), '3.10');
    expect(f('{0,number,#,##0.0}', [12345.67]), '12,345.7');
    expect(f('{0,number,000}', [7]), '007');
    expect(f('{0,number,\$#.00}', [5]), r'$5.00');
    expect(f('{0,number,#%}', [0.5]), '50%');
    expect(f('{0,number,#.#}', [0.25]), '.2');
    expect(f('{0,number}', ['not a number']), 'not a number');
    expect(f('{0}', [double.nan]), 'NaN');
    expect(f('{0}', [double.infinity]), '∞');
    expect(f('{0}', [double.negativeInfinity]), '-∞');
    expect(f('{0}', [1e21]), '1,000,000,000,000,000,000,000');
    expect(f('{0,number,#.####}', [1.5e-5]), '0');
    expect(f('{0,number,#.######}', [1.5e-5]), '.000015');
  });

  test('dates and times', () {
    final date = DateTime.utc(2026, 10, 20, 9, 5, 7);
    expect(f('{0,date}', [date]), '2026-10-20');
    expect(f('{0,time}', [date]), '09:05:07');
    expect(f('{0}', [date]), '2026-10-20 09:05');
    expect(f('{0,date}', ['x']), 'x');
    expect(f('{0,time}', ['y']), 'y');
  });

  test('choice', () {
    const pattern =
        'There {0,choice,0#are no files|1#is one file|1<are {0,number,integer} files}.';
    expect(f(pattern, [0]), 'There are no files.');
    expect(f(pattern, [1]), 'There is one file.');
    expect(f(pattern, [1234]), 'There are 1,234 files.');
    expect(f(pattern, [-1]), 'There are no files.');
    expect(f('{0,choice,-∞#neg|0#zero|0<pos|∞#inf}', [double.infinity]), 'inf');
    expect(f('{0,choice,-Infinity#neg|0#zero}', [-5]), 'neg');
    expect(f('{0,choice,0#a|Infinity#b}', [3]), 'a');
  });

  test('quotes inside choice and style', () {
    expect(f("{0,choice,0#a'|'b|1#c}", [0]), 'a|b');
    expect(f("{0,choice,0#a'|'b|1#c}", [1]), 'c');
    expect(f("{0,choice,0#it''s none|1#'{'one'}'}", [0]), "it's none");
    expect(f("{0,choice,0#it''s none|1#'{'one'}'}", [1]), '{one}');
    expect(f("{0,choice,0#x',' y|1#z}", [0]), 'x, y');
  });

  test('errors', () {
    expect(() => f('{x}', ['a']), throwsFormatException);
    expect(() => f('{0,unknown}', ['a']), throwsFormatException);
    expect(() => f('{0', ['a']), throwsFormatException);
    expect(() => f('{0,choice,0#a}', ['x']), throwsFormatException);
    expect(() => f('{0,choice,zero}', [1]), throwsFormatException);
    expect(() => f('{0,choice,x#a}', [1]), throwsFormatException);
    expect(() => f('{0,number,abc}', [1]), throwsFormatException);
  });
}
