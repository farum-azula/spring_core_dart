create table orders (
  id integer primary key,
  customer text not null
);

-- The children of an order: its id and the position or key in the list or
-- map of the aggregate.
create table order_lines (
  orders_id integer not null references orders (id),
  orders_key integer not null,
  sku text not null,
  quantity integer not null
);

create table order_notes (
  orders_id integer not null references orders (id),
  orders_key text not null,
  text text not null
);
