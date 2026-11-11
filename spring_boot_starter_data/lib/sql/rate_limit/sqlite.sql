-- The table of the rate limiter's SQL store (JdbcRateLimitStore) on
-- SQLite. Copy it into the application's migrations when the store does
-- not create the table itself (spring.data.jdbc.rate-limit.create-table).
--
-- One row is one bucket; the times are seconds since 1970.
create table if not exists rate_limit (
  key text primary key,
  tokens real not null,
  allowed integer not null,
  updated_at real not null,
  expires_at real not null
) without rowid;
create index if not exists rate_limit_expires_at
  on rate_limit (expires_at);
