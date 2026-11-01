-- A second migration: both are applied to the in-memory database.
create unique index uq_books_title_year on books (title, year);
