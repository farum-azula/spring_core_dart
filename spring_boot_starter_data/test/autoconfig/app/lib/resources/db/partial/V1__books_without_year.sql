create table authors (
  id integer primary key,
  name text not null
);

create table books (
  id integer primary key,
  title text not null,
  author integer,
  version integer
);

create table orders (
  id integer primary key,
  customer text not null
);

create table order_lines (
  orders_id integer not null,
  orders_key integer not null,
  sku text not null,
  quantity integer not null
);
