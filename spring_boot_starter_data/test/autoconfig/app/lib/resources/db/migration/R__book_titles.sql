drop view if exists book_titles;
create view book_titles as select id, title from books;
