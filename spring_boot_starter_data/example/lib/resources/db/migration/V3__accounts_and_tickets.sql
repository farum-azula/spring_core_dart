-- An id the application gives, and a version that is a time stamp.
create table accounts (
  iban text primary key,
  owner text not null,
  version integer not null
);

create table tickets (
  id integer primary key,
  subject text not null,
  stamp text
);
