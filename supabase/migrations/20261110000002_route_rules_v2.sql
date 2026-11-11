-- Route rules, version 2. The phase 2 migration is already on staging, so the
-- changes go here. Like the others, it only adds or replaces, because it also
-- runs on the live project.
--
-- S_OVERLAP and H_REPEAT now need a true match: each line covers most of the
-- other. So the facts also say how much of the other route the new line covers.
-- For a DOTC trip that's the share of the trip's stops the new line passes.

create or replace function public.route_geometry_facts(
  p_route_id text,
  p_contributor text,
  p_geom text,
  p_correction_of text
) returns jsonb
language plpgsql stable
set search_path = extensions, pg_catalog
as $$
declare
  v_line geometry;
  v_is_gtfs boolean := p_correction_of like 'gtfs:%';
  v_target_exists boolean;
  v_target_status text;
  v_target geography;
  v_length_km numeric;
  v_camanava_km numeric;
  v_published jsonb;
  v_gtfs jsonb;
  v_repeat jsonb;
  v_kept numeric;
begin
  if p_correction_of is not null and p_correction_of <> '' then
    if v_is_gtfs then
      if to_regclass('gtfs.routes') is null then
        v_target_exists := null;
      else
        select exists (
          select 1 from gtfs.routes where route_id = substr(p_correction_of, 6)
        ) into v_target_exists;
      end if;
      v_target_status := case when v_target_exists then 'published' end;
    else
      select status::text, geom into v_target_status, v_target
        from public.transit_routes where id = p_correction_of;
      v_target_exists := found;
    end if;
  end if;

  if p_geom is not null then
    v_line := ST_GeomFromEWKT(p_geom);
    v_length_km := round((ST_Length(v_line::geography) / 1000)::numeric, 2);

    select round((coalesce(sum(ST_Length(ST_Intersection(v_line, a.geom::geometry)::geography)), 0) / 1000)::numeric, 2)
      into v_camanava_km
      from public.service_areas a;

    -- The published route that matches best both ways, leaving out the route
    -- itself and its target. A short route along part of a long one scores low
    -- on other_fraction, so it isn't picked over a real match.
    select jsonb_build_object(
             'id', c.id,
             'name', coalesce(c.data->>'startLocation', '?') || ' to ' || coalesce(c.data->>'endLocation', '?'),
             'source', c.source,
             'fraction', c.fraction,
             'other_fraction', c.other_fraction)
      into v_published
      from (
        select r.id, r.data, r.source,
               public.route_line_overlap(v_line, r.geom::geometry) as fraction,
               public.route_line_overlap(r.geom::geometry, v_line) as other_fraction
        from public.transit_routes r
        where r.status = 'published'
          and r.geom is not null
          and r.id <> p_route_id
          and r.id is distinct from p_correction_of
          and ST_DWithin(r.geom, v_line::geography, 30)
      ) c
      order by least(c.fraction, c.other_fraction) desc, c.fraction desc
      limit 1;

    -- The contributor's own recent or moderator-rejected routes. A route the
    -- system rejected doesn't count: fixing and resending it is what we want.
    -- Both ways again: a short correction along part of your own longer route
    -- isn't a repeat of it.
    if p_contributor is not null then
      select jsonb_build_object('id', c.id, 'fraction', c.fraction, 'other_fraction', c.other_fraction, 'status', c.status)
        into v_repeat
        from (
          select r.id, r.status,
                 public.route_line_overlap(v_line, r.geom::geometry) as fraction,
                 public.route_line_overlap(r.geom::geometry, v_line) as other_fraction
          from public.transit_routes r
          where r.contributor_id = p_contributor
            and r.geom is not null
            and r.id <> p_route_id
            and r.id is distinct from p_correction_of
            and (r.status = 'rejected' or r.created_at > now() - interval '7 days')
            and coalesce((
              select d.decision from public.route_decisions d
              where d.route_id = r.id
              order by d.id desc limit 1
            ), '') <> 'auto_rejected'
            and ST_DWithin(r.geom, v_line::geography, 30)
        ) c
        order by least(c.fraction, c.other_fraction) desc, c.fraction desc
        limit 1;
    end if;

    -- How much of the target a correction leaves in place.
    if v_target is not null then
      v_kept := public.route_line_near(v_target::geometry, v_line);
    end if;

    -- The GTFS feed has almost no shapes, so compare stops instead. A trip counts
    -- when it stops along the line in order, without skipping most of its stops.
    -- other_fraction is how many of the trip's stops the line passes.
    if to_regclass('gtfs.stop_times') is not null and not coalesce(v_is_gtfs, false) then
      with near_stops as (
        select s.stop_id,
               ST_LineLocatePoint(v_line, ST_SetSRID(ST_MakePoint(s.stop_lon, s.stop_lat), 4326)) as loc
        from gtfs.stops s
        where s.stop_lat between ST_YMin(v_line) - 0.001 and ST_YMax(v_line) + 0.001
          and s.stop_lon between ST_XMin(v_line) - 0.001 and ST_XMax(v_line) + 0.001
          and ST_DWithin(ST_SetSRID(ST_MakePoint(s.stop_lon, s.stop_lat), 4326)::geography, v_line::geography, 60)
      ), visits as (
        select st.trip_id, st.stop_sequence, n.loc,
               lag(n.loc) over (partition by st.trip_id order by st.stop_sequence) as previous
        from gtfs.stop_times st
        join near_stops n on n.stop_id = st.stop_id
      ), trips as (
        select v.trip_id,
               count(*) as matched,
               max(v.stop_sequence) - min(v.stop_sequence) + 1 as spanned,
               count(*) filter (where v.loc > v.previous) as forward,
               count(*) filter (where v.loc < v.previous) as backward,
               max(v.loc) - min(v.loc) as coverage
        from visits v
        group by v.trip_id
      ), candidates as (
        select c.trip_id, c.coverage,
               c.matched::numeric / (
                 select count(*) from gtfs.stop_times st where st.trip_id = c.trip_id
               ) as stop_share
        from trips c
        where c.matched >= 3
          and c.forward > c.backward
          and c.matched::numeric / c.spanned >= 0.6
      )
      select jsonb_build_object(
               'id', t.route_id,
               'name', coalesce(nullif(r.route_long_name, ''), nullif(r.route_short_name, ''), t.route_id),
               'source', 'gtfs',
               'fraction', round(c.coverage::numeric, 3),
               'other_fraction', round(least(c.stop_share, 1), 3))
        into v_gtfs
        from candidates c
        join gtfs.trips t on t.trip_id = c.trip_id
        left join gtfs.routes r on r.route_id = t.route_id
        order by least(c.coverage, c.stop_share) desc, c.coverage desc
        limit 1;
    end if;
  end if;

  return jsonb_build_object(
    'target_exists', v_target_exists,
    'target_status', v_target_status,
    'length_km', v_length_km,
    'camanava_km', v_camanava_km,
    'published_overlap', v_published,
    'gtfs_overlap', v_gtfs,
    'repeat', v_repeat,
    'correction_kept', v_kept
  );
end;
$$;

-- "create or replace" keeps the old grants, but say them again so this file
-- stands on its own.
revoke execute on function public.route_geometry_facts(text, text, text, text) from public, anon, authenticated;
grant execute on function public.route_geometry_facts(text, text, text, text) to service_role;

-- Modern jeepneys have their own LTFRB rate. A jeepney fare anywhere from the
-- traditional rate to the modern one passes S_FARE_RANGE, the way bus fares
-- can be ordinary or aircon.
alter table public.fare_rules drop constraint if exists fare_rules_mode_check;
alter table public.fare_rules add constraint fare_rules_mode_check
  check (mode in ('jeepney', 'jeepney_modern', 'bus', 'bus_aircon', 'fx_van', 'tricycle'));

-- The LTFRB fare guides effective September 28, 2026 (Metro Manila buses). New
-- rows, so the old estimates stay on record. FX/vans keep the estimate: LTFRB
-- only gives ₱2.60 per km with no base fare, which would reject the fixed fares
-- most UV Express trips charge. Tricycle fares are set by each city.
--
-- effective_from is today, not September 28. The estimate rows above got the
-- date their migration ran, and the newest date wins, so an earlier date here
-- would leave the estimates in use. The source keeps the real date.
insert into public.fare_rules (mode, base, base_km, per_km, effective_from, source) values
  ('jeepney', 14, 4, 2.00, current_date, 'LTFRB (effective 2026-09-28)'),
  ('jeepney_modern', 17, 4, 2.40, current_date, 'LTFRB (effective 2026-09-28)'),
  ('bus', 15, 5, 2.49, current_date, 'LTFRB (effective 2026-09-28)'),
  ('bus_aircon', 18, 5, 2.98, current_date, 'LTFRB (effective 2026-09-28)');
