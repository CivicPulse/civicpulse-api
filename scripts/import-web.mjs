import { readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isDeepStrictEqual } from 'node:util';
import { normalizeReviewedPrivateEvents } from './private-events.mjs';
import { applyReviewedGeometryRepair } from './geometry-repairs.mjs';
import { createCivicPulseClient } from '../src/client.mjs';

// Match civicpulse-web/src/lib/events.ts: refreshed Mobilize records supersede
// manual records by source URL; calendar memberships are inferred the same way.
export function mergeEvents(catalog, sources) {
  const [manual, mobilize, mgdsa, mgrls, bcsd] = sources;
  const refreshed = new Set(mobilize.map(event => event.sourceUrl));
  const records = [...manual.filter(event => !refreshed.has(event.sourceUrl || '')), ...mgdsa, ...mobilize, ...mgrls, ...bcsd];
  const seen = new Set();
  return records.map(item => {
    if (item.sample !== false) throw new Error(`Cannot import sample event ${item.id}`);
    if (seen.has(item.id)) throw new Error(`Duplicate event ID: ${item.id}`);
    seen.add(item.id);
    const organizationId = item.organizationId || (item.sourceGroup === 'mgdsa' ? 'mgdsa' : undefined);
    const inferred = catalog.calendars.find(calendar => calendar.sourceCalendar && calendar.sourceCalendar === item.sourceCalendar)
      || catalog.calendars.find(calendar => calendar.organizationId === organizationId);
    const calendarIds = [...new Set(item.calendarIds || (inferred ? [inferred.id] : []))];
    if (!catalog.organizations.some(org => org.id === organizationId) || !calendarIds.length ||
      calendarIds.some(id => !catalog.calendars.some(calendar => calendar.id === id && calendar.organizationId === organizationId)))
      throw new Error(`Invalid organization/calendar membership: ${item.id}`);
    return { ...item, organizationId, calendarIds };
  }).sort((a,b) => a.start.localeCompare(b.start));
}
export async function readWebData(root, { rawGeometry = false } = {}) {
  const json = async file => JSON.parse(await readFile(join(root,file),'utf8'));
  const catalog = await json('src/data/calendars.json');
  const sources = await Promise.all(['events','mobilize-events','mgdsa-events','mgrls-events','bcsd-events'].map(name => json(`src/data/${name}.json`)));
  // Run via tsx: imports the project's authoritative catalog, including its imports.
  const { maps, layers } = await import(pathToFileURL(join(root,'src/data/maps.ts')).href);
  const layerRecords = await Promise.all(layers.map(async layer => {
    if (layer.id === 'event-locations') return { ...layer, dynamic: 'events' };
    const filename = ({ 'commission-districts':'commission_districts', 'polling-places':'polling_places', 'voting-precincts':'voting_precincts' })[layer.id] || layer.id;
    const bytes = await readFile(join(root, `public/data/${filename}.geojson`));
    return { ...layer, ...(rawGeometry ? { geojson: JSON.parse(bytes) } : applyReviewedGeometryRepair(layer.id, bytes)) };
  }));
  return [...catalog.organizations.map(payload=>({kind:'organization',payload})),
    ...catalog.calendars.map(payload=>({kind:'calendar',payload})),
    ...normalizeReviewedPrivateEvents(mergeEvents(catalog,sources), await readFile(join(root,'src/data/mobilize-events.json'))).map(payload=>({kind:'event',payload})),
    ...layerRecords.map(payload=>({kind:'layer',payload})),
    ...maps.map(payload=>({kind:'map',payload}))];
}
export async function importDrafts(client, records) {
  const report = { created:0, unchanged:0, conflicts:[] };
  for (const {kind,payload} of records) {
    const existing = await client.getDraft(kind,payload.id);
    if (existing) {
      if (isDeepStrictEqual(existing.payload,payload)) report.unchanged++;
      else report.conflicts.push(`${kind}/${payload.id}`);
      continue; // Never overwrite editorial work, including changed imports.
    }
    await client.saveDraft(kind,payload,0);
    report.created++;
  }
  return report;
}
async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log('npm run import:web -- [--web-root ../civicpulse-web] [--raw-geometry] [--apply]\nDefaults to a read-only inventory. --apply creates missing drafts only; never publishes or overwrites.');
    return;
  }
  for (let i=0;i<args.length;i++) {
    if (args[i]==='--web-root') { if (!args[++i] || args[i].startsWith('--')) throw new Error('--web-root needs a path'); }
    else if (!['--apply','--raw-geometry'].includes(args[i])) throw new Error(`Unknown option: ${args[i]}`);
  }
  const index = args.indexOf('--web-root');
  const root = resolve(index < 0 ? '../civicpulse-web' : args[index+1]);
  const records = await readWebData(root, { rawGeometry: args.includes('--raw-geometry') });
  const counts = Object.fromEntries(['organization','calendar','event','layer','map'].map(kind=>[kind,records.filter(r=>r.kind===kind).length]));
  console.log(JSON.stringify({mode:args.includes('--apply')?'create-drafts':'dry-run',root,counts,geometry:args.includes('--raw-geometry')?'original':'reviewed-hash-gated-repairs'},null,2));
  if (!args.includes('--apply')) return;
  const { SUPABASE_URL:url, SUPABASE_PUBLISHABLE_KEY:publishableKey, CIVICPULSE_ACCESS_TOKEN:accessToken } = process.env;
  if (!accessToken) throw new Error('CIVICPULSE_ACCESS_TOKEN must be an invited staff user access token');
  const client = createCivicPulseClient({url,publishableKey,accessToken});
  if (!['editor','admin'].includes(await client.role())) throw new Error('The access token must belong to invited staff');
  const report = await importDrafts(client,records);
  console.log(JSON.stringify(report,null,2));
  if (report.conflicts.length) process.exitCode=2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error=>{ console.error(error.message); process.exitCode=1; });
}
