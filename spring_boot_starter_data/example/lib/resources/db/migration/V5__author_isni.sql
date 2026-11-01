-- Author.isni is @Unique: a unique index (several rows may hold null).
alter table authors add column isni text;

create unique index uq_authors_isni on authors (isni);

-- The books' foreign key to authors, as the starter writes it, has an index.
create index idx_books_author on books (author);
