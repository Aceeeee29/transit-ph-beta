# Changelog

## v1.0.35 — October 26, 2026

- New launch screen with the TransitPH logo, shown until the app is
  ready instead of a blank screen and a loading spinner
- With no internet, the app shows only your downloaded routes, and back
  no longer takes you to Home. Everything comes back on its own once
  you're online again
- The weather on Home now shows up by itself once location is turned on
  or allowed, and again when the internet comes back, so you no longer
  have to tap "Weather"
- Fixed the Joined date going missing for new accounts (including
  accounts made again after being deleted); missing dates are restored
- You can no longer report your own post
- Fixed buttons doing things twice when tapped quickly, like sending a
  route twice, approving twice, saving Settings and then closing it, or
  starting the update download twice

## v1.0.34 — October 25, 2026

- Fixed the terms and consent screen flickering or coming back after
  you had already accepted
- New Contribute tutorial: a guided tour that highlights each part of
  the screen and shows an example route being drawn; replay it from
  Settings or the ? button. Your own drawing comes back when it ends
- Contribute now shows the line of the step you're still drawing, not
  only the saved ones
- You can delete your account in Settings. Your posts, comments and
  routes still waiting for review are removed; approved routes stay
  and are shown as by "Former rider"
- Short trips you can walk now show a walk-only option first, and rides
  that don't save at least 5 minutes are left out
- The app no longer asks for microphone access

## v1.0.33 — October 24, 2026

- Fixed the map staying grey (only the route lines showing) when you
  open a downloaded route with no internet
- Generated routes no longer make you walk along a jeepney, tricycle or
  FX road to its stop and then ride back over the same stretch: you
  board where your walk first reaches its road, and get off where your
  next walk leaves it
- Report button on generated routes too, also while following; reports
  show on every route on that road, like on rider routes
- A rider's note on a route (like where to wait for the jeep) only shows
  when you board where that note applies
- You can have at most 3 routes waiting for review at a time
- New accounts need a stronger password: at least 8 characters with an
  uppercase letter, a lowercase letter, a number and a special
  character, no spaces; a checklist shows what's still missing as you
  type
- Appearance option "Follow phone" is now called "System"

## v1.0.32 — October 21, 2026

- Fixed rider routes showing "0 min" or "0 m" in your Profile, the
  Moderator panel and route previews: routes saved that way now show a
  time and distance worked out from their drawn line
- Saved times like "1 h 5 min" are read correctly (they were shown as
  15 minutes)
- Contribute shows the time and fare while you're still drawing a step,
  not only after you save it

## v1.0.31 — October 19, 2026

- Following a route now shows the ride you're on at the top: where to
  ride or walk to, how far and how long until that part ends, and its
  fare, with the next step shown under it
- "Get off soon": about 300 m before the end of a jeep, bus or train
  ride, the app warns you and your phone buzzes, even in your pocket
- Press Start once: if your location isn't ready yet, the app waits for
  it and starts by itself
- More room for the map while following: the bottom tabs hide until you
  stop or arrive, and the place category buttons are gone from route
  views
- New route drawer, the same on rider routes, generated routes and
  find-a-way trips: X to stop on the left, time in the middle with the
  distance and fare under it, and a whole-route button on the right
- Fixed the whole-route button zooming to the wrong place; on find-a-way
  trips it now shows the way to the rider route too
- Smaller start and end markers, plus small dots where you change
  vehicles
- New contribute tutorial with real screenshots of each step, and new
  welcome cards for new accounts
- Updated Terms and Conditions and Privacy Policy (you'll be asked to
  accept them once)
- Long place names and labels no longer get cut off with "…" on Home
  route cards, the fare matrix and elsewhere

## v1.0.30 — October 17, 2026

- Fixed routes drawn in Contribute showing "0 m · 0 min": distance, time
  and fare now come from the actual line, and routes you submit save
  their real distance
- Distances to places and per-step distances and fares on a route are
  exact instead of rounded to whole kilometers
- While following a route, finished steps are crossed out and marked
  "Done", on generated routes too
- Contribute no longer fills in the start and end locations from the map:
  type them yourself in Basic Info (both are needed to submit)

## v1.0.29 — October 17, 2026

- Far from a route when you press Start? The app offers to find a way to
  its start using rider routes, and shows both as one trip (for example
  "VGC → Monumento + Monumento → STI")
- Route reports are shared with everyone: a report shows as a warning on
  every route and generated trip on the same road for a day, and the
  riders who shared those routes are notified. Moderators can keep or
  remove reports
- Generated routes measure the walk to your first ride and from your last
  ride along the actual streets, so a tricycle nearby is used instead of
  a long walk around the block
- Every option that rides mostly on rider routes is marked
  "Rider-verified", and the one with less walking is listed first
- Student, PWD and senior discount applies only to jeepney and bus fares
- Fixed "Failed to submit route" when sending an edited route for review

## v1.0.28 — October 15, 2026

- Generated routes use rider routes near you: if one starts within a
  20-minute walk of where you are (or ends that close to where you're
  going), it's always one of the options, listed first
- A short ride beats a long walk: if a tricycle or jeep passes closer,
  the route rides it instead of walking you a kilometer to the next one
- Walking distances are measured along the streets, and walking lines
  on the map follow them instead of cutting through houses
- Places outside the Philippines no longer come up when searching (a
  search for "Galicia Obando" landed in Spain)
- Faster on home internet with broken IPv6 (some fiber connections):
  route lines, place search and weather no longer hang
- The map stays on Metro Manila: zooming out stops once the whole city
  fills the screen, in route views too (they stretch to fit routes that
  leave the city)
- Your position on the map is a 3D arrow that turns with your phone's
  compass when walking and with the road when riding
- Pressing Start in Follow Route tilts the map and turns it to face
  where you're going
- Jumping to the CAMANAVA area from Metro Manila now lands on CAMANAVA
- Announcements have a new look that works in dark mode, with the date
  and a "Don't show again" link
- Home section titles without emojis; "Matching Routes" is shorter

## v1.0.27 — October 15, 2026

- New map engine on every map (Map tab, route view, Follow Route,
  generated routes, drawing a route): panning and zooming are smooth,
  without the freezes when pinching
- 3D view: a 2D/3D button tilts the map and buildings stand up
- Follow Route turns the map so the way you're going is up and tilts
  into 3D; it goes back to flat and north up when you stop
- Over 1,500 more places on the map (schools, hospitals, malls,
  attractions, parks) from OpenStreetMap, alongside TransitPH's own
- Place chips now highlight: the map starts clean, and places show
  when you zoom in to street level; pick a chip to see that kind of
  place even when zoomed out. "All" highlights everything, tap it again
  to clear
- Drawing a route: the handles still drag and long-press as before, and
  the map no longer jumps when switching between browsing and drawing
- Dark mode fixes for the "Generated automatically" notice and the
  "Most rider-verified" badge
