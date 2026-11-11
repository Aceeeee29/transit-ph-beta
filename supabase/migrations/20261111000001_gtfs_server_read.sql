-- The server function reads the DOTC feed to check routes: overlaps, repeats,
-- reports and corrections of GTFS routes. On the live project the gtfs tables
-- were made by hand and only the app's public roles could read them, so every
-- one of those checks failed there and fell back to a moderator.
-- Read only. Nothing else changes.
grant usage on schema gtfs to service_role;
grant select on all tables in schema gtfs to service_role;
