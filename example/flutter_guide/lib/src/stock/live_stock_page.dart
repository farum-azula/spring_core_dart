import 'package:flutter/material.dart';
import 'package:neon_books_app/src/stock/live_stock.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

/// The Live stock screen: the stock changes as the server sends them.
/// The stream is open while the screen is (`start` in `initState`, `stop`
/// in `dispose`).
class LiveStockPage extends SpringStatefulWidget<(LiveStock,)> {
  const LiveStockPage({super.key});

  @override
  State<LiveStockPage> createState() => _LiveStockPageState();
}

class _LiveStockPageState extends SpringState<LiveStockPage, (LiveStock,)> {
  late final LiveStock _stock;

  @override
  void initState() {
    super.initState();
    _stock = beans.$1;
    _stock.start();
  }

  @override
  void dispose() {
    _stock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (stock,) = beans;
    final recent = stock.recent;
    return Column(
      children: [
        ListTile(
          leading: Icon(
            stock.live ? Icons.sensors : Icons.sensors_off,
            color: stock.live ? Theme.of(context).colorScheme.primary : null,
          ),
          title: Text(
            context.message(stock.live ? 'stock.live' : 'stock.offline'),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: recent.isEmpty
              ? Center(child: Text(context.message('stock.waiting')))
              : ListView(
                  children: [
                    for (final change in recent)
                      ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(change.isbn),
                        trailing: Text(
                          context.message(
                            'stock.available',
                            args: [change.available],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
