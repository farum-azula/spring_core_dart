// The supplier's JSON. Plain immutable classes: the Feign clients use
// them, so the generator introspects them (no annotations).

/// What the supplier asks for a book and how many copies it has.
class Offer {
  const Offer({required this.isbn, required this.price, required this.copies});

  final String isbn;
  final double price;
  final int copies;
}

class DeliveryRequest {
  const DeliveryRequest({required this.isbn, required this.copies});

  final String isbn;
  final int copies;

  @override
  String toString() => '$copies x $isbn';
}

/// What the supplier sends; `copies` may be fewer than asked for.
class Delivery {
  const Delivery({required this.isbn, required this.copies, this.reference});

  final String isbn;
  final int copies;
  final String? reference;
}
