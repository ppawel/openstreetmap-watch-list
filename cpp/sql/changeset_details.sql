create table changeset_details
       (id bigint primary key,
        uid bigint not null,
	closed boolean default false not null,
	last_seen timestamp not null,
	comment text,
	created_by text,
	bot_tag boolean);

create index changeset_details_last_seen_idx 
       on changeset_details(last_seen)
       where not closed;
