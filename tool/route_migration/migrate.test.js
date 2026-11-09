// Run with: node --test "tool/route_migration/*.test.js"
const test = require('node:test');
const assert = require('node:assert/strict');
const { plain, ownerOf, toRow, toVoteRow, toViewRow, toFeedbackRow } = require('./migrate.js');

// A Firestore REST document, as the API returns it.
function doc(id, fields = {}) {
  return { name: `projects/p/databases/(default)/documents/routes/${id}`, fields };
}
const s = (stringValue) => ({ stringValue });
const n = (v) => ({ integerValue: String(v) });
const d = (doubleValue) => ({ doubleValue });
const t = (timestampValue) => ({ timestampValue });
const point = (lat, lng) => ({ mapValue: { fields: { lat: d(lat), lng: d(lng) } } });
const list = (...values) => ({ arrayValue: { values } });

const noOwners = new Map();

test('plain turns Firestore values into normal JSON', () => {
  assert.deepEqual(
    plain({
      mapValue: {
        fields: {
          a: s('x'),
          b: n(3),
          c: d(1.5),
          e: { booleanValue: true },
          f: { nullValue: null },
          g: t('2026-01-01T00:00:00Z'),
          h: list(n(1)),
          i: { arrayValue: {} },
        },
      },
    }),
    { a: 'x', b: 3, c: 1.5, e: true, f: null, g: '2026-01-01T00:00:00Z', h: [1], i: [] },
  );
});

test('an approved route is published and verified', () => {
  const row = toRow(doc('r1', { approvalStatus: s('approved'), updatedAt: t('2026-02-02T00:00:00Z') }), noOwners).row;
  assert.equal(row.status, 'published');
  assert.equal(row.verification, 'verified');
  assert.equal(row.published_at, '2026-02-02T00:00:00Z');
  assert.equal(row.rejected_at, null);
});

test('an old route with no status, path or dates is published, and does not crash', () => {
  const { row, problems } = toRow(doc('old', {}), noOwners);
  assert.equal(row.status, 'published');
  assert.equal(row.geom, null);
  assert.equal(row.created_at, null);
  assert.equal(row.updated_at, null);
  assert.ok(problems.includes('no_created_at'));
  assert.ok(problems.includes('no_path'));
});

test('a pending route stays pending and unverified', () => {
  const { row } = toRow(doc('r1', { approvalStatus: s('pending') }), noOwners);
  assert.equal(row.status, 'pending');
  assert.equal(row.verification, 'unverified');
  assert.equal(row.published_at, null);
});

test('a rejected route keeps the date it was rejected', () => {
  const { row } = toRow(doc('r1', { approvalStatus: s('rejected'), updatedAt: t('2026-03-03T00:00:00Z') }), noOwners);
  assert.equal(row.status, 'rejected');
  assert.equal(row.rejected_at, '2026-03-03T00:00:00Z');
});

test('an unknown status needs a person to look, so it stays out of public view', () => {
  const { row, problems } = toRow(doc('r1', { approvalStatus: s('weird') }), noOwners);
  assert.equal(row.status, 'pending');
  assert.ok(problems.includes('unknown_status'));
});

test('timestamps become ISO text, inside data too', () => {
  const { row } = toRow(
    doc('r1', { createdAt: t('2026-01-01T00:00:00Z'), editedAt: t('2026-01-05T00:00:00Z') }),
    noOwners,
  );
  assert.equal(row.created_at, '2026-01-01T00:00:00Z');
  assert.equal(row.data.editedAt, '2026-01-05T00:00:00Z');
  assert.equal(row.data.createdAt, undefined);
});

test('source comes from the id', () => {
  assert.equal(toRow(doc('osm-bus-1'), noOwners).row.source, 'osm');
  assert.equal(toRow(doc('2026-01-01 10:00:00.000'), noOwners).row.source, 'rider');
});

test('geom is built longitude first, and one point is no line', () => {
  const two = toRow(doc('r1', { pathPoints: list(point(14.65, 120.98), point(14.66, 120.99)) }), noOwners).row;
  assert.equal(two.geom, 'SRID=4326;LINESTRING(120.98 14.65,120.99 14.66)');
  const one = toRow(doc('r2', { pathPoints: list(point(14.65, 120.98)) }), noOwners);
  assert.equal(one.row.geom, null);
  assert.ok(one.problems.includes('no_path'));
});

test('start and end points are built longitude first', () => {
  const { row } = toRow(
    doc('r1', { startLat: d(14.65), startLng: d(120.98), endLat: d(14.7), endLng: n(121) }),
    noOwners,
  );
  assert.equal(row.start_pt, 'SRID=4326;POINT(120.98 14.65)');
  assert.equal(row.end_pt, 'SRID=4326;POINT(121 14.7)');
});

test('counters move to columns, and bad ones become 0', () => {
  const { row } = toRow(doc('r1', { views: n(7), upvotes: s('3'), downvotes: n(-2) }), noOwners);
  assert.equal(row.views, 7);
  assert.equal(row.upvotes, 3);
  assert.equal(row.downvotes, 0);
  assert.equal(row.data.views, undefined);
});

test('a feedback summary always has all 6 counters', () => {
  const { row } = toRow(
    doc('r1', { feedbackSummary: { mapValue: { fields: { fareAccurateYes: n(4), lastFeedbackAt: t('2026-01-01T00:00:00Z') } } } }),
    noOwners,
  );
  assert.equal(row.feedback_summary.fareAccurateYes, 4);
  assert.equal(row.feedback_summary.stillOperatingNo, 0);
  assert.equal(row.feedback_summary.lastFeedbackAt, '2026-01-01T00:00:00Z');
});

test('every row has the same columns, because bulk inserts require it', () => {
  const full = toRow(doc('r1', { approvalStatus: s('rejected'), correctionOf: s('r9'), createdAt: t('2026-01-01T00:00:00Z') }), noOwners).row;
  const bare = toRow(doc('r2'), noOwners).row;
  assert.deepEqual(Object.keys(full).sort(), Object.keys(bare).sort());
});

test('correctionOf and revision are carried over', () => {
  const { row } = toRow(doc('r1', { correctionOf: s('gtfs:X') }), noOwners);
  assert.equal(row.correction_of, 'gtfs:X');
  assert.equal(row.revision, 1);
});

// Owners

test('owner fields are tried in the same order as the app', () => {
  assert.equal(ownerOf({ contributorId: 'a', userId: 'b' }), 'a');
  assert.equal(ownerOf({ contributorId: '  ', userId: 'b' }), 'b');
  assert.equal(ownerOf({ contributorEmail: 'c@x.ph', email: 'd@x.ph' }), 'c@x.ph');
  assert.equal(ownerOf({ userEmail: 'c@x.ph' }), 'c@x.ph');
  assert.equal(ownerOf({ email: 'd@x.ph' }), 'd@x.ph');
  assert.equal(ownerOf({}), null);
});

test('a uid owner is kept as it is', () => {
  const { row, problems } = toRow(doc('r1', { contributorId: s('uid-1') }), noOwners);
  assert.equal(row.contributor_id, 'uid-1');
  assert.equal(problems.includes('unresolved_owner'), false);
});

test('an email owner becomes their uid', () => {
  const uids = new Map([['rider@x.ph', 'uid-9']]);
  const { row, problems } = toRow(doc('r1', { contributorId: s('Rider@X.ph') }), uids);
  assert.equal(row.contributor_id, 'uid-9');
  assert.equal(problems.includes('unresolved_owner'), false);
});

test('an email with no account is not given to anyone, and is reported', () => {
  const { row, problems } = toRow(doc('r1', { contributorId: s('gone@x.ph') }), noOwners);
  assert.equal(row.contributor_id, null);
  assert.ok(problems.includes('unresolved_owner'));
});

test('emails never reach data, because anyone can read published rows', () => {
  const { row } = toRow(
    doc('r1', {
      contributorId: s('rider@x.ph'),
      userId: s('uid-1'),
      contributorEmail: s('rider@x.ph'),
      userEmail: s('rider@x.ph'),
      email: s('rider@x.ph'),
      startLocation: s('A'),
    }),
    new Map([['rider@x.ph', 'uid-1']]),
  );
  assert.equal(JSON.stringify(row.data).includes('rider@x.ph'), false);
  assert.equal(row.data.startLocation, 'A');
  assert.equal(row.data.id, 'r1');
});

test('any email left in data is reported, wherever it is', () => {
  const { problems } = toRow(doc('r1', { shortDescription: s('call me at rider@x.ph') }), noOwners);
  assert.ok(problems.includes('email_in_data'));
});

test('a Former rider route keeps its label', () => {
  const { row } = toRow(
    doc('r1', { contributorId: { nullValue: null }, contributorName: s('Former rider'), contributorClosed: { booleanValue: true } }),
    noOwners,
  );
  assert.equal(row.contributor_id, null);
  assert.equal(row.contributor_name, 'Former rider');
  assert.equal(row.data.contributorClosed, true);
  assert.equal(row.data.contributorName, undefined);
});

// Votes, views and feedback

test('a vote row uses the doc id as the user', () => {
  const vote = { name: 'x/routeVotes/uid-1', fields: { vote: s('up'), createdAt: t('2026-01-01T00:00:00Z') } };
  assert.deepEqual(toVoteRow('r1', vote), {
    route_id: 'r1',
    user_id: 'uid-1',
    vote: 'up',
    created_at: '2026-01-01T00:00:00Z',
    updated_at: null,
  });
});

test('a vote that is not up or down is skipped', () => {
  assert.equal(toVoteRow('r1', { name: 'x/routeVotes/u', fields: { vote: s('sideways') } }), null);
});

test('view and feedback rows carry their dates', () => {
  assert.deepEqual(toViewRow('r1', { name: 'x/routeViews/u', fields: {} }), { route_id: 'r1', user_id: 'u', created_at: null });
  assert.deepEqual(
    toFeedbackRow('r1', {
      name: 'x/routeFeedback/u',
      fields: { fareAccurate: { booleanValue: true }, stillOperating: { booleanValue: false }, updatedAt: t('2026-01-02T00:00:00Z') },
    }),
    {
      route_id: 'r1',
      user_id: 'u',
      fare_accurate: true,
      schedule_accurate: null,
      still_operating: false,
      created_at: null,
      updated_at: '2026-01-02T00:00:00Z',
    },
  );
});
