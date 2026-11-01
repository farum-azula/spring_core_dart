package dev.farumazula.datareference;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.Version;
import org.springframework.data.relational.core.mapping.Table;

/** Optimistic locking: a stale save fails. */
@Table("accounts")
public record Account(@Id String iban, String owner, @Version Long version) {}
