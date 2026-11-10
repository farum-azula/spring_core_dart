// Scenarios "json" and "json-post": a list of objects written by the
// ObjectMapper, and a JSON body read and validated.
import 'package:load_bench/src/bench_properties.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
@RequestMapping('/json')
class JsonController {
  JsonController(BenchProperties properties)
    : _products = [
        for (var i = 1; i <= properties.json.items; i++)
          Product(
            id: i,
            name: 'Product $i',
            description: 'The product number $i of the load bench.',
            price: 9.99 + i,
            inStock: i.isEven,
            tags: ['bench', 'tag-${i % 7}', 'group-${i % 3}'],
            createdAt: DateTime.utc(2026).add(Duration(hours: i)),
          ),
      ];

  final List<Product> _products;

  /// `GET /json`: `bench.json.items` objects (50), serialized on every
  /// request.
  @GetMapping()
  List<Product> list() => _products;

  /// `POST /json`: the body is read into a [NewProduct] and validated; a
  /// violation is a 400 with the field errors.
  @PostMapping()
  @ResponseStatus(HttpStatus.created)
  Product create(@RequestBody() @Valid() NewProduct product) => Product(
    id: _products.length + 1,
    name: product.name,
    description: product.description,
    price: product.price,
    inStock: product.quantity > 0,
    tags: product.tags,
    createdAt: DateTime.utc(2026),
  );
}

/// One object of `GET /json`.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.inStock,
    required this.tags,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String description;
  final double price;
  final bool inStock;
  final List<String> tags;
  final DateTime createdAt;
}

/// The body of `POST /json`. Missing JSON properties keep the defaults
/// here, so they are reported as field errors.
class NewProduct {
  const NewProduct({
    this.name = '',
    this.description = '',
    this.price = 0,
    this.quantity = 0,
    this.tags = const [],
  });

  @NotBlank()
  @Size(max: 80)
  final String name;

  @Size(max: 400)
  final String description;

  @Positive()
  final double price;

  @PositiveOrZero()
  @Max(10000)
  final int quantity;

  @Size(max: 10)
  final List<String> tags;
}
