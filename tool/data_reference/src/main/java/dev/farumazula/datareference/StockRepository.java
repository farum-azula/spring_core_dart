package dev.farumazula.datareference;

import java.util.List;
import java.util.Optional;

import org.springframework.data.relational.core.sql.LockMode;
import org.springframework.data.relational.repository.Lock;
import org.springframework.data.repository.CrudRepository;

public interface StockRepository extends CrudRepository<Stock, Long> {
    @Lock(LockMode.PESSIMISTIC_WRITE)
    Optional<Stock> findBySku(String sku);

    @Lock(LockMode.PESSIMISTIC_READ)
    List<Stock> findByQuantityLessThan(long quantity);
}
