-- The table of the database scenarios, with 1000 rows to read
-- (GET /db/items/{id}); POST /db/items adds rows after them.
create table items (
  id integer primary key,
  name text not null,
  price real not null,
  quantity integer not null
);

with recursive numbers (n) as (
  select 1
  union all
  select n + 1 from numbers where n < 1000
)
insert into items (id, name, price, quantity)
select n, 'item ' || n, n * 1.5, n % 100 from numbers;
