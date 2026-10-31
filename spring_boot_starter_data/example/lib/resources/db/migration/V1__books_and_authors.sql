create table authors (
  id integer primary key,
  name text not null
);

create table books (
  id integer primary key,
  title text not null,
  year integer not null,
  subtitle text,
  in_stock integer not null,
  author integer references authors (id),
  version integer,
  created_at text,
  modified_at text,
  created_by text,
  modified_by text
);

create index books_year on books (year);
