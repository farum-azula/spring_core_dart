/// Builds the text of a receipt, line by line: a new one for every
/// receipt (a prototype bean, see ShopConfig).
class ReceiptBuilder {
  ReceiptBuilder(this.shopName, this.createdAt);

  final String shopName;
  final DateTime createdAt;
  final _lines = <String>[];

  void add(String line) => _lines.add(line);

  String build() =>
      [shopName, createdAt.toIso8601String(), ..._lines].join('\n');
}
