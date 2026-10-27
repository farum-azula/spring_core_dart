// Aspects (chapter 6): code that runs around methods of other beans
// without editing them. The audit aspect is the outer one (`@Order(1)`):
// its @Before runs before the timing aspect's @Around starts, its @After
// after it ends.
import 'dart:async';

import 'package:neon_books_server/src/aop/timed.dart';
import 'package:neon_books_server/src/app.spring.dart';
import 'package:neon_books_server/src/orders/order.dart';
import 'package:spring_core_dart/spring_core_dart.dart';

@Aspect()
@Component()
@Order(1)
@Log(topic: 'neon.audit')
class AuditAspect {
  /// A named pointcut: the shop's services, by class (`within`) and by
  /// bean name (`bean`).
  @Pointcut('within(OrderService) || bean(catalogService)')
  void shopServices() {}

  /// `args(isbn)` binds the call's argument to the parameter of that name.
  @Before('shopServices() && execution(* remove(..)) && args(isbn)')
  void beforeRemove(String isbn) => log.info('removing book $isbn');

  /// Runs only when the result is an Order (the parameter type filters).
  @AfterReturning('shopServices() && execution(* place(..))')
  void placed(CustomerOrder order) =>
      log.info('order ${order.id} placed by ${order.customer}');

  /// Runs for exceptions only (errors pass by); the exception is rethrown
  /// afterwards.
  @AfterThrowing('shopServices()')
  void failed(JoinPoint call, Exception error) =>
      log.warning('${call.toShortString()} failed: $error');

  /// After every call of the supplier's Feign clients (also failed ones).
  @After('bean(supplierOffers) || bean(supplierDeliveries)')
  void afterSupplierCall(JoinPoint call) =>
      log.debug('supplier call ${call.signature.name}${call.args}');
}

@Aspect()
@Component()
@Order(2)
@Log(topic: 'neon.timing')
class TimingAspect {
  /// Every method marked `@Timed()`; `timed` binds the annotation.
  @Around('@annotation(timed)')
  Object? time(ProceedingJoinPoint call, Timed timed) {
    final watch = Stopwatch()..start();
    void done() => log.debug(
      '${call.signature.name} took ${watch.elapsedMicroseconds / 1000} ms',
    );
    final result = call.proceed();
    if (result is Future<Object?>) {
      return result.whenComplete(done);
    }
    done();
    return result;
  }
}
