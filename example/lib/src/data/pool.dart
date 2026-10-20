import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_core_dart_example/src/creation_log.dart';

class Pool {
  Pool(this.size);

  final int size;
}

/// A `FactoryBean`: lookups of [Pool] return [getObject]'s product.
@Component('pool')
class PoolFactory extends FactoryBean<Pool> {
  @Value(r'${pool.size:1}')
  late final int size;

  @override
  Pool getObject() {
    creationLog.add('pool:getObject');
    return Pool(size);
  }
}
