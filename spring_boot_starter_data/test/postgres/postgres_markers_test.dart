// The `?` markers of a statement written for every database, turned into
// PostgreSQL's `$1`, and what is left alone.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

String _sql(String sql) => PostgresMarkers.rewrite(sql).sql;

int _count(String sql) => PostgresMarkers.rewrite(sql).count;

void main() {
  test('each marker becomes the next number', () {
    final rewritten = PostgresMarkers.rewrite(
      'select * from books where year > ? and title like ? limit ?',
    );
    expect(
      rewritten.sql,
      r'select * from books where year > $1 and title like $2 limit $3',
    );
    expect(rewritten.count, 3);
  });

  test('a statement without markers is returned as it is', () {
    const sql = "select 'x' from t";
    expect(PostgresMarkers.rewrite(sql).sql, same(sql));
    expect(_count(sql), 0);
  });

  test('strings, identifiers and comments are left alone', () {
    expect(_sql("select '?', ?"), r"select '?', $1");
    expect(_sql("select 'it''s ?', ?"), r"select 'it''s ?', $1");
    expect(_sql('select "a?" , ?'), r'select "a?" , $1');
    expect(_sql('select "a""?" , ?'), r'select "a""?" , $1');
    expect(_sql('select 1 -- ?\n, ?'), 'select 1 -- ?\n, \$1');
    expect(_sql('select 1 /* ? */, ?'), r'select 1 /* ? */, $1');
    // PostgreSQL's comments nest.
    expect(_sql('select /* a /* ? */ ? */ ?'), r'select /* a /* ? */ ? */ $1');
    expect(_count("select '?' -- ?\n"), 0);
  });

  test('a backslash escapes in E strings only', () {
    expect(_sql(r"select E'\' ?', ?"), r"select E'\' ?', $1");
    // A plain string ends at its quote: `'\'` is one backslash.
    expect(_sql(r"select '\', ?"), r"select '\', $1");
    expect(
      _sql(r"select x like ? escape '\', y = ?"),
      r"select x like $1 escape '\', y = $2",
    );
    // Not an E string: the `e` belongs to a name.
    expect(_sql(r"select name'\', ?"), r"select name'\', $1");
  });

  test('dollar quoted bodies are left alone', () {
    expect(_sql(r'select $$ ? $$, ?'), r'select $$ ? $$, $1');
    expect(_sql(r'select $fn$ ? $$ ? $fn$, ?'), r'select $fn$ ? $$ ? $fn$, $1');
    // A parameter already numbered is not a tag, and an identifier with a
    // dollar does not start a quote.
    expect(_sql(r'select $1, ?'), r'select $1, $1');
    expect(_sql(r'select a$b$, ?'), r'select a$b$, $1');
  });

  test('?? is a literal ? (the jsonb operators)', () {
    expect(_sql("select data ?? 'k', ?"), r"select data ? 'k', $1");
    expect(_sql('select data ??| ?'), r'select data ?| $1');
    expect(_count('select ?? ?? ??'), 0);
  });

  test('an unterminated string or comment does not loop or throw', () {
    expect(_sql("select 'abc ?"), "select 'abc ?");
    expect(_sql('select /* abc ?'), 'select /* abc ?');
    expect(_sql(r'select $$ abc ?'), r'select $$ abc ?');
  });
}
