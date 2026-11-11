-- The table of the rate limiter's SQL store (JdbcRateLimitStore) on
-- PostgreSQL. Copy it into the application's migrations when the store
-- does not create the table itself (spring.data.jdbc.rate-limit.create-table).
--
-- One row is one bucket; the times are seconds since 1970. Unlogged: a
-- bucket lost in a crash is a full bucket, and counting writes no WAL.
create unlogged table if not exists rate_limit (
  key text primary key,
  tokens double precision not null,
  allowed boolean not null,
  updated_at double precision not null,
  expires_at double precision not null
);
create index if not exists rate_limit_expires_at
  on rate_limit (expires_at);
