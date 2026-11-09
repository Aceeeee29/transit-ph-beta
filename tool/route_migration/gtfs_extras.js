// Loads the 3 GTFS files we never imported (agency, calendar, frequencies) into
// the gtfs schema. Safe to run twice, because the tables have unique keys.
//
// Usage: node tool/route_migration/gtfs_extras.js --target staging
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const LIVE_SUPABASE_REF = 'rruijvorkljjpfkbamls';
const ZIP = path.join(os.homedir(), 'Downloads', 'gtfs-master-sakay.ph.zip');
const CHUNK_SIZE = 500;

const TABLES = [
  { name: 'agency', key: 'agency_id', numbers: [] },
  {
    name: 'calendar',
    key: 'service_id',
    numbers: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'],
  },
  { name: 'frequencies', key: 'trip_id,start_time', numbers: ['headway_secs', 'exact_times'] },
];

// Handles quoted values, since agency names can hold commas.
function parseCsv(text) {
  const rows = [];
  let row = [];
  let value = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') {
        value += '"';
        i++;
      } else if (c === '"') quoted = false;
      else value += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') {
      row.push(value);
      value = '';
    } else if (c === '\n') {
      row.push(value.replace(/\r$/, ''));
      rows.push(row);
      row = [];
      value = '';
    } else value += c;
  }
  if (value !== '' || row.length > 0) {
    row.push(value.replace(/\r$/, ''));
    rows.push(row);
  }
  return rows;
}

function toRecords(text, numbers) {
  const [head, ...rows] = parseCsv(text.replace(/^﻿/, ''));
  return rows
    .filter((row) => row.some((v) => v !== ''))
    .map((row) =>
      Object.fromEntries(
        head.map((column, i) => {
          const value = row[i] ?? '';
          if (numbers.includes(column)) return [column, value === '' ? null : Number(value)];
          return [column, value === '' ? null : value];
        }),
      ),
    );
}

function readEnvFile(file) {
  const env = {};
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const at = line.indexOf('=');
    if (at > 0) env[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return env;
}

function supabaseTarget(args) {
  const target = args[args.indexOf('--target') + 1];
  if (target === 'staging') {
    const env = readEnvFile('.env.staging');
    if (env.SUPABASE_URL.includes(LIVE_SUPABASE_REF)) throw new Error('.env.staging points at the live project. Stopping.');
    return { url: env.SUPABASE_URL, key: env.SUPABASE_SERVICE_ROLE_KEY };
  }
  if (target === 'prod') {
    if (!args.includes('--i-mean-live')) throw new Error('--target prod also needs --i-mean-live.');
    const { SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: key } = process.env;
    if (!url || !key) throw new Error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in this shell first.');
    return { url, key };
  }
  throw new Error('Use --target staging or --target prod.');
}

async function main(args) {
  const { url, key } = supabaseTarget(args);
  for (const { name, key: conflict, numbers } of TABLES) {
    const text = execFileSync('unzip', ['-p', ZIP, `gtfs-master/${name}.txt`], {
      encoding: 'utf8',
      maxBuffer: 50 * 1024 * 1024,
    });
    const records = toRecords(text, numbers);
    for (let start = 0; start < records.length; start += CHUNK_SIZE) {
      const response = await fetch(`${url}/rest/v1/${name}?on_conflict=${conflict}`, {
        method: 'POST',
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          'Content-Type': 'application/json',
          'Content-Profile': 'gtfs',
          Prefer: 'resolution=merge-duplicates,return=minimal',
        },
        body: JSON.stringify(records.slice(start, start + CHUNK_SIZE)),
      });
      if (!response.ok) throw new Error(`Writing ${name}: ${response.status} ${(await response.text()).slice(0, 300)}`);
    }
    const counted = await fetch(`${url}/rest/v1/${name}?select=*&limit=1`, {
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Accept-Profile': 'gtfs', Prefer: 'count=exact' },
    });
    console.log(`gtfs.${name}: read ${records.length}, now ${counted.headers.get('content-range')?.split('/')[1]} rows`);
  }
}

module.exports = { parseCsv, toRecords };

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
