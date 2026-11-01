-- A second migration, in the same database as the first.
create unique index uq_books_title_year on books (title, year);
