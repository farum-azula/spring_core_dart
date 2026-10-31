create table orders (
  id integer primary key,
  customer text not null
);

create table order_lines (
  orders_id integer not null references orders (id),
  orders_key integer not null,
  sku text not null,
  quantity integer not null
);
