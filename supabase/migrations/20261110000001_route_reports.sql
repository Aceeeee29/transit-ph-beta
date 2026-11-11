-- Route reports and verification (phase 3). Like the first two migrations, it
-- only adds new things, because it also runs on the live project.

-- A rider's report of something wrong with a route's details. route_key is a
-- transit_routes id, or gtfs:<route_id> for the DOTC 2013 feed, so there's no
-- foreign key. Reports stay as history after their route is gone.
create table public.route_issues (
  id bigserial primary key,
  route_key text not null,
  reporter_id text not null,                    -- Firebase uid
  type text not null check (type in (
    'wrong_fare', 'wrong_path', 'not_operating', 'wrong_schedule', 'wrong_stop', 'other'
  )),
  fare_paid numeric check (fare_paid > 0),      -- wrong_fare only
  step_index int check (step_index >= 0),       -- which ride a wrong_fare is about
  note text,
  correction_id text,                           -- the drawn fix, for wrong_path
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  settled_by text,                              -- "system" or a Firebase uid
  settled_note text,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index route_issues_open_idx on public.route_issues (route_key, created_at desc)
  where status = 'open';
create index route_issues_reporter_idx on public.route_issues (reporter_id, created_at desc);

-- One open report per rider, route and type. A second one is refused, so a
-- single rider can't add up to "5 riders".
create unique index route_issues_one_open_idx on public.route_issues (route_key, reporter_id, type)
  where status = 'open';

-- Routes riders say may be out of date. Search avoids them and shows a warning.
-- Readable by everyone, like published routes.
create table public.route_outdated (
  route_key text primary key,
  types text[] not null,                        -- the report types that reached the limit
  riders int not null,                          -- the most riders behind one type
  since timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.route_issues enable row level security;
alter table public.route_outdated enable row level security;

create policy public_read on public.route_outdated for select to anon, authenticated using (true);

-- Supabase may hand new tables to these roles by default, so take that back.
revoke all on public.route_issues, public.route_outdated from anon, authenticated;
revoke all on sequence public.route_issues_id_seq from anon, authenticated;
grant select on public.route_outdated to anon, authenticated;

grant all on public.route_issues, public.route_outdated to service_role;
grant all on sequence public.route_issues_id_seq to service_role;
