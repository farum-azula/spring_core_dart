-- Repeatable: run again whenever this file changes.
drop view if exists author_book_counts;

create view author_book_counts as
select a.id, a.name, count(b.id) as books
from authors a
left join books b on b.author = a.id
group by a.id, a.name;
