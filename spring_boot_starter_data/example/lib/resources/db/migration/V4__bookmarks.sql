-- A bookmark references its book (Bookmark.bookId: @Reference(Book)); the
-- action is the one of @OnDelete, an index serves the foreign key, and the
-- unique constraint is the @UniqueConstraint of the class.
create table bookmarks (
  id integer primary key,
  book_id integer not null references books (id) on delete cascade,
  page integer not null,
  constraint uq_bookmarks_book_id_page unique (book_id, page)
);

create index idx_bookmarks_book_id on bookmarks (book_id);
