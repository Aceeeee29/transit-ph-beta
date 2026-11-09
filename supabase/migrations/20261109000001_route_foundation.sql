-- Route foundation (phase 1). Rider and OpenStreetMap routes move here from
-- Firestore. This file only adds new things. It must never drop or change
-- anything that already exists, because it also runs on the live project.

create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron;

create type public.route_status as enum ('pending', 'published', 'rejected', 'withdrawn');
create type public.route_verification as enum ('unverified', 'verified');
create type public.route_source as enum ('rider', 'osm');

-- Routes

create table public.transit_routes (
  id text primary key,                          -- keeps the Firestore id
  source public.route_source not null,
  contributor_id text,                          -- Firebase uid. Null means "Former rider"
  contributor_name text,
  status public.route_status not null default 'pending',
  verification public.route_verification not null default 'unverified',
  correction_of text,                           -- target route id, or gtfs:<route_id>
  data jsonb not null default '{}',             -- the app's Route.toJson() shape
  geom extensions.geography(LineString, 4326),  -- null for old routes with no path
  start_pt extensions.geography(Point, 4326),
  end_pt extensions.geography(Point, 4326),
  views int not null default 0,
  upvotes int not null default 0,
  downvotes int not null default 0,
  feedback_summary jsonb not null default
    '{"fareAccurateYes":0,"fareAccurateNo":0,"scheduleAccurateYes":0,"scheduleAccurateNo":0,"stillOperatingYes":0,"stillOperatingNo":0}',
  revision int not null default 1,
  created_at timestamptz default now(),         -- null for old routes with no date
  updated_at timestamptz default now(),
  published_at timestamptz,
  rejected_at timestamptz
);

create index transit_routes_status_idx on public.transit_routes (status);
create index transit_routes_contributor_idx on public.transit_routes (contributor_id, status);
create index transit_routes_geom_idx on public.transit_routes using gist (geom);

-- Decisions have no foreign key on purpose. They outlive a purged route, so we
-- can still see why it was rejected.
create table public.route_decisions (
  id bigserial primary key,
  route_id text not null,
  revision int not null,
  actor text not null,                          -- "system" or a Firebase uid
  decision text not null,
  reason_codes text[] not null default '{}',
  note text,
  created_at timestamptz default now()
);

create index route_decisions_route_idx on public.route_decisions (route_id, created_at desc);

create table public.rejection_reasons (
  code text primary key,
  label text not null,
  needs_note boolean not null
);

insert into public.rejection_reasons (code, label, needs_note) values
  ('incomplete', 'Missing information', false),
  ('outside_area', 'Outside the service area', false),
  ('wrong_path', 'Path doesn''t match the real route', false),
  ('wrong_fare', 'Fare is wrong', false),
  ('duplicate', 'Already exists', false),
  ('not_operating', 'Route no longer runs', false),
  ('unsafe_or_spam', 'Spam or unsafe content', false),
  ('other', 'Other', true);

-- Votes, views and feedback go when their route goes.

create table public.route_votes (
  route_id text not null references public.transit_routes (id) on delete cascade,
  user_id text not null,
  vote text not null check (vote in ('up', 'down')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (route_id, user_id)
);

create table public.route_views (
  route_id text not null references public.transit_routes (id) on delete cascade,
  user_id text not null,
  created_at timestamptz default now(),
  primary key (route_id, user_id)
);

create table public.route_quality_feedback (
  route_id text not null references public.transit_routes (id) on delete cascade,
  user_id text not null,
  fare_accurate boolean,
  schedule_accurate boolean,
  still_operating boolean,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (route_id, user_id)
);

-- Database functions. Only routes-api calls these, using the service role.
-- Each one locks the route row first, so two riders tapping at the same moment
-- can't lose a count. They mirror today's logic in RouteService.

-- Same date format as the app's toIso8601String, because the app reads it back.
create function public.route_iso(p_time timestamptz) returns text
language sql immutable
set search_path = ''
as $$
  select to_char(p_time at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

-- Runs when a rider opens a route. One call gives the screen everything it needs.
create function public.route_open(p_route text, p_user text) returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_summary jsonb;
  v_vote text;
  v_feedback public.route_quality_feedback;
  v_last timestamptz;
  v_inserted int;
begin
  select feedback_summary into v_summary
    from public.transit_routes where id = p_route for update;
  if not found then
    raise exception 'route_not_found';
  end if;

  insert into public.route_views (route_id, user_id)
    values (p_route, p_user)
    on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    update public.transit_routes
      set views = views + 1, updated_at = now()
      where id = p_route;
  end if;

  select vote into v_vote
    from public.route_votes where route_id = p_route and user_id = p_user;
  select * into v_feedback
    from public.route_quality_feedback where route_id = p_route and user_id = p_user;
  v_last := coalesce(v_feedback.updated_at, v_feedback.created_at);

  return jsonb_build_object(
    'vote', v_vote,
    'feedback', case when v_feedback.route_id is null then null else jsonb_build_object(
      'fareAccurate', coalesce(v_feedback.fare_accurate, true),
      'scheduleAccurate', coalesce(v_feedback.schedule_accurate, true),
      'stillOperating', coalesce(v_feedback.still_operating, true)
    ) end,
    'nextFeedbackAt', public.route_iso(v_last + interval '30 days'),
    'summary', v_summary
  );
end;
$$;

-- Tapping the same vote again removes it. Switching needs removing it first.
create function public.route_vote(p_route text, p_user text, p_up boolean) returns text
language plpgsql
set search_path = ''
as $$
declare
  v_existing text;
  v_next text := case when p_up then 'up' else 'down' end;
  v_change int;
begin
  perform 1 from public.transit_routes where id = p_route for update;
  if not found then
    raise exception 'route_not_found';
  end if;

  select vote into v_existing
    from public.route_votes where route_id = p_route and user_id = p_user;

  if v_existing is null then
    insert into public.route_votes (route_id, user_id, vote)
      values (p_route, p_user, v_next);
    v_change := 1;
  elsif v_existing = v_next then
    delete from public.route_votes where route_id = p_route and user_id = p_user;
    v_change := -1;
  else
    raise exception 'remove_first';
  end if;

  update public.transit_routes
    set upvotes = case when p_up then greatest(upvotes + v_change, 0) else upvotes end,
        downvotes = case when p_up then downvotes else greatest(downvotes + v_change, 0) end,
        updated_at = now()
    where id = p_route;

  return case when v_change = 1 then v_next else null end;
end;
$$;

-- A rider can give feedback on a route once every 30 days.
create function public.route_quality_feedback(
  p_route text,
  p_user text,
  p_fare boolean,
  p_schedule boolean,
  p_operating boolean
) returns void
language plpgsql
set search_path = ''
as $$
declare
  v_last timestamptz;
  v_summary jsonb;
begin
  select feedback_summary into v_summary
    from public.transit_routes where id = p_route for update;
  if not found then
    raise exception 'route_not_found';
  end if;

  select coalesce(updated_at, created_at) into v_last
    from public.route_quality_feedback where route_id = p_route and user_id = p_user;
  if v_last is not null and now() < v_last + interval '30 days' then
    raise exception 'feedback_cooldown:%', public.route_iso(v_last + interval '30 days');
  end if;

  insert into public.route_quality_feedback
      (route_id, user_id, fare_accurate, schedule_accurate, still_operating)
    values (p_route, p_user, p_fare, p_schedule, p_operating)
    on conflict (route_id, user_id) do update set
      fare_accurate = excluded.fare_accurate,
      schedule_accurate = excluded.schedule_accurate,
      still_operating = excluded.still_operating,
      updated_at = now();

  -- Old routes can be missing a counter or hold it as 3.0, so read it safely.
  update public.transit_routes
    set updated_at = now(),
        feedback_summary = v_summary || jsonb_build_object(
          'lastFeedbackAt', public.route_iso(now()),
          'fareAccurateYes', coalesce((v_summary->>'fareAccurateYes')::numeric::int, 0) + (case when p_fare then 1 else 0 end),
          'fareAccurateNo', coalesce((v_summary->>'fareAccurateNo')::numeric::int, 0) + (case when p_fare then 0 else 1 end),
          'scheduleAccurateYes', coalesce((v_summary->>'scheduleAccurateYes')::numeric::int, 0) + (case when p_schedule then 1 else 0 end),
          'scheduleAccurateNo', coalesce((v_summary->>'scheduleAccurateNo')::numeric::int, 0) + (case when p_schedule then 0 else 1 end),
          'stillOperatingYes', coalesce((v_summary->>'stillOperatingYes')::numeric::int, 0) + (case when p_operating then 1 else 0 end),
          'stillOperatingNo', coalesce((v_summary->>'stillOperatingNo')::numeric::int, 0) + (case when p_operating then 0 else 1 end)
        )
    where id = p_route;
end;
$$;

-- Who can do what. RLS is the second lock. Grants are the first.

alter table public.transit_routes enable row level security;
alter table public.route_decisions enable row level security;
alter table public.rejection_reasons enable row level security;
alter table public.route_votes enable row level security;
alter table public.route_views enable row level security;
alter table public.route_quality_feedback enable row level security;

create policy published_read on public.transit_routes
  for select to anon, authenticated
  using (status = 'published');

-- Supabase may hand new public tables to these roles by default, so take that
-- back on purpose. A modified app must never be able to write here directly.
revoke all on
  public.transit_routes,
  public.route_decisions,
  public.rejection_reasons,
  public.route_votes,
  public.route_views,
  public.route_quality_feedback
  from anon, authenticated;
revoke all on sequence public.route_decisions_id_seq from anon, authenticated;

grant select on public.transit_routes to anon, authenticated;

grant all on
  public.transit_routes,
  public.route_decisions,
  public.rejection_reasons,
  public.route_votes,
  public.route_views,
  public.route_quality_feedback
  to service_role;
grant all on sequence public.route_decisions_id_seq to service_role;

-- Functions can be called by everyone unless we say otherwise.
revoke execute on function public.route_iso(timestamptz) from public, anon, authenticated;
revoke execute on function public.route_open(text, text) from public, anon, authenticated;
revoke execute on function public.route_vote(text, text, boolean) from public, anon, authenticated;
revoke execute on function public.route_quality_feedback(text, text, boolean, boolean, boolean) from public, anon, authenticated;

grant execute on function public.route_iso(timestamptz) to service_role;
grant execute on function public.route_open(text, text) to service_role;
grant execute on function public.route_vote(text, text, boolean) to service_role;
grant execute on function public.route_quality_feedback(text, text, boolean, boolean, boolean) to service_role;

-- The 3 GTFS files we never imported. The schema already exists on the live
-- project, but a new staging project starts empty.

create schema if not exists gtfs;
grant usage on schema gtfs to anon, authenticated, service_role;

create table gtfs.agency (
  agency_id text primary key,
  agency_name text,
  agency_url text,
  agency_timezone text,
  agency_lang text,
  agency_phone text
);

create table gtfs.calendar (
  service_id text primary key,
  monday smallint,
  tuesday smallint,
  wednesday smallint,
  thursday smallint,
  friday smallint,
  saturday smallint,
  sunday smallint,
  start_date text,
  end_date text
);

-- The key lets the import script run twice without doubling the rows.
create table gtfs.frequencies (
  trip_id text not null,
  start_time text not null,
  end_time text,
  headway_secs int,
  exact_times smallint,
  primary key (trip_id, start_time)
);

alter table gtfs.agency enable row level security;
alter table gtfs.calendar enable row level security;
alter table gtfs.frequencies enable row level security;

create policy public_read on gtfs.agency for select to anon, authenticated using (true);
create policy public_read on gtfs.calendar for select to anon, authenticated using (true);
create policy public_read on gtfs.frequencies for select to anon, authenticated using (true);

grant select on gtfs.agency, gtfs.calendar, gtfs.frequencies to anon, authenticated;
grant all on gtfs.agency, gtfs.calendar, gtfs.frequencies to service_role;

-- Rejected routes are kept 30 days so the contributor can fix and resubmit.
select cron.schedule(
  'purge-rejected-routes',
  '0 3 * * *',
  $$delete from public.transit_routes where status = 'rejected' and rejected_at < now() - interval '30 days'$$
);
