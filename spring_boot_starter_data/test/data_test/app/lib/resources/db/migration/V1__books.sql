create table books (
  id integer primary key,
  title text not null,
  year integer not null,
  created_by text,
  created_at text
);
