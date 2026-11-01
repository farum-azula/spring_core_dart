create table authors (
  id integer primary key,
  name text not null
);

create table books (
  id integer primary key,
  title text not null,
  year integer not null,
  author integer references authors (id),
  version integer
);
