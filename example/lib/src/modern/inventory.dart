/// Beans written with the newest Dart syntax: primary constructors,
/// `class const`, `new`/`factory` constructor declarations and private
/// named parameters.
library;

import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks methods counted by [CountingAspect].
class Counted {
  /// Creates the marker.
  const Counted();
}

/// Primary constructor with an injected configuration value.
@Component()
class InventorySettings(@Value(r'${pool.size:1}') final int capacity);

/// `class const` with an empty primary constructor.
@Component()
class const SkuFormat() {
  /// Normalizes [sku] to upper case.
  String format(String sku) => sku.toUpperCase();
}

/// Stock of SKUs.
abstract interface class Inventory {
  /// Adds [sku]; `false` when the inventory is full.
  @Counted()
  bool add(String sku);

  /// The SKUs added so far.
  List<String> get items;
}

/// In-body `new(...)` constructor with a private named parameter
/// (`this._format` is passed as `format:`); `new empty()` is ignored
/// because the unnamed constructor wins.
@Service()
class InMemoryInventory implements Inventory {
  /// Capacity settings.
  final InventorySettings settings;
  final SkuFormat _format;
  final _items = <String>[];

  new(this.settings, {required this._format});
  new empty() : this(InventorySettings(0), format: const SkuFormat());

  @override
  bool add(String sku) {
    if (_items.length >= settings.capacity) {
      return false;
    }
    _items.add(_format.format(sku));
    return true;
  }

  @override
  List<String> get items => List.unmodifiable(_items);
}

/// An `@Autowired` factory constructor declared with `factory name(...)`.
@Service()
class InventoryReport {
  /// The reported inventory.
  final Inventory inventory;
  new _(this.inventory);

  /// The constructor used for injection.
  @Autowired()
  factory of(Inventory inventory) => InventoryReport._(inventory);

  /// For example `2 items`.
  String summary() => '${inventory.items.length} items';
}

/// A configuration class with a primary constructor.
@Configuration()
class InventoryConfig(final InventorySettings settings) {
  /// Half the capacity.
  @Bean()
  @Qualifier('reorderLevel')
  int reorderLevel() => settings.capacity ~/ 2;
}

/// Validated form whose properties come from a primary constructor.
@Introspected()
class StockForm(@NotBlank() var String sku, {@Min(1) var int quantity = 1});

/// Counts `@Counted` calls; works through the generated proxy.
@Aspect()
@Component()
class CountingAspect {
  /// Number of advised calls.
  int calls = 0;

  /// Counts one call.
  @Before('@annotation(Counted)')
  void count() => calls++;
}
