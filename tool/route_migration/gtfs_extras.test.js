const test = require('node:test');
const assert = require('node:assert/strict');
const { parseCsv, toRecords } = require('./gtfs_extras.js');

test('quoted values keep their commas and quotes', () => {
  assert.deepEqual(parseCsv('a,b\n"x, y","say ""hi"""\n'), [
    ['a', 'b'],
    ['x, y', 'say "hi"'],
  ]);
});

test('Windows line endings and a missing last newline are fine', () => {
  assert.deepEqual(parseCsv('a,b\r\n1,2\r\n3,4'), [
    ['a', 'b'],
    ['1', '2'],
    ['3', '4'],
  ]);
});

test('numbers become numbers, and blanks become null', () => {
  assert.deepEqual(
    toRecords('trip_id,start_time,headway_secs,exact_times\nt1,05:37:00,3600,\n', ['headway_secs', 'exact_times']),
    [{ trip_id: 't1', start_time: '05:37:00', headway_secs: 3600, exact_times: null }],
  );
});

test('a byte order mark and blank lines are ignored', () => {
  assert.deepEqual(toRecords('﻿agency_id,agency_name\nLRTA,Light Rail\n\n', []), [
    { agency_id: 'LRTA', agency_name: 'Light Rail' },
  ]);
});
