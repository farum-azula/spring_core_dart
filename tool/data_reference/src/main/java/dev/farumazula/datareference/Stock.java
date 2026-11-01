package dev.farumazula.datareference;

import org.springframework.data.annotation.Id;
import org.springframework.data.relational.core.mapping.Table;

/** What the pessimistic locks are taken on. */
@Table("stock")
public record Stock(@Id Long id, String sku, long quantity) {}
