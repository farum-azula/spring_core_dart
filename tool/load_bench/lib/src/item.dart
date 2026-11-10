// Scenarios "db-read" and "db-write": a repository of
// spring_boot_starter_data on SQLite (db/migration/V1__items.sql).
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

/// A row of `items`.
@Table('items')
class Item {
  Item({
    required this.name,
    required this.price,
    required this.quantity,
    this.id,
  });

  @Id()
  int? id;

  String name;
  double price;
  int quantity;
}

/// The generator writes the implementation.
abstract interface class ItemRepository
    implements ListCrudRepository<Item, int> {}

/// The body of `POST /db/items`.
class NewItem {
  const NewItem({this.name = '', this.price = 0, this.quantity = 0});

  @NotBlank()
  final String name;

  @PositiveOrZero()
  final double price;

  @PositiveOrZero()
  final int quantity;
}

@RestController()
@RequestMapping('/db/items')
class ItemController {
  ItemController(this._items);

  final ItemRepository _items;

  /// `GET /db/items/{id}`: one row by its key (1 to 1000 exist).
  @GetMapping('/{id}')
  Future<Item> find(@PathVariable() int id) async =>
      await _items.findById(id) ??
      (throw ResponseStatusException(HttpStatus.notFound, 'No item $id'));

  /// `POST /db/items`: one insert, in its own transaction.
  @PostMapping()
  @ResponseStatus(HttpStatus.created)
  Future<Item> add(@RequestBody() @Valid() NewItem item) => _items.save(
    Item(name: item.name, price: item.price, quantity: item.quantity),
  );
}
