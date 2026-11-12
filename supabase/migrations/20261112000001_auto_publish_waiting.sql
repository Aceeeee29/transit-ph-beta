-- A route that waits 7 days for a moderator, when the only thing holding it
-- back is "new contributor", goes live as Unverified. The Unverified badge and
-- rider reports already cover the risk of a new rider's route, and a rider
-- shouldn't wait forever because moderators are busy. Any other flag keeps the
-- route in the queue, where it shows as overdue.
--
-- Only routes whose checks ran on rule version 3 or newer count. Older checks
-- didn't look at names or long straight lines, so those routes stay with
-- moderators.
--
-- Corrections are left out: approving one merges it into another route, which
-- only the server function does. Staff routes never qualify, because their
-- checks skip "new contributor".

create or replace function public.auto_publish_waiting_routes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_route record;
  v_count integer := 0;
begin
  for v_route in
    select r.id, r.revision
    from public.transit_routes r
    where r.status = 'pending'
      and r.correction_of is null
      -- The checks put it in the queue at this revision, 7 or more days ago,
      -- and nobody has done anything with it since.
      and exists (
        select 1
        from (
          select d.actor, d.decision, d.revision, d.created_at
          from public.route_decisions d
          where d.route_id = r.id
          order by d.created_at desc, d.id desc
          limit 1
        ) latest
        where latest.actor = 'system'
          and latest.decision = 'flagged'
          and latest.revision = r.revision
          and latest.created_at <= now() - interval '7 days'
      )
      -- "New contributor" is flagged, by the current rules...
      and exists (
        select 1 from public.route_checks c
        where c.route_id = r.id and c.revision = r.revision
          and c.code = 'S_NEW_CONTRIBUTOR' and c.result = 'flag'
          and c.rule_version >= 3
      )
      -- ...and nothing else is flagged or failed.
      and not exists (
        select 1 from public.route_checks c
        where c.route_id = r.id and c.revision = r.revision
          and (c.result = 'fail' or (c.result = 'flag' and c.code <> 'S_NEW_CONTRIBUTOR'))
      )
    for update of r skip locked
  loop
    -- Same as the server function's "published" outcome.
    update public.transit_routes
      set status = 'published',
          verification = 'unverified',
          published_at = now(),
          rejected_at = null,
          updated_at = now(),
          data = data || '{"isEdited": false}'::jsonb
      where id = v_route.id and status = 'pending';
    if found then
      insert into public.route_decisions (route_id, revision, actor, decision, note)
        values (
          v_route.id,
          v_route.revision,
          'system',
          'auto_published',
          'No moderator review in 7 days, and the only flag was a new contributor.'
        );
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

-- Only the scheduled job (and the service role) runs it.
revoke all on function public.auto_publish_waiting_routes() from public, anon, authenticated;
grant execute on function public.auto_publish_waiting_routes() to service_role;

select cron.schedule(
  'auto-publish-waiting-routes',
  '17 * * * *',
  $$select public.auto_publish_waiting_routes()$$
);
