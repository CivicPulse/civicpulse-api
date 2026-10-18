#!/usr/bin/env node
// TEST ONLY. PostgreSQL API projections, not a PostgREST/Auth emulator.
import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { createServer } from 'node:http';
import { fileURLToPath } from 'node:url';
import { sourceJsonStats } from '../src/server/github-run-json.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
// Deliberately no database URL/container override or hosted environment loading.
const instance = randomUUID().replaceAll('-', '');
const container = `civicpulse-delivery-fixture-${instance}`;
const args=process.argv.slice(2);
const selectedSource=args.length===3||args.length===5;
const validSource=selectedSource&&args[0]==='--test-only'&&args[1]==='--source-sha'&&args[2].length===40&&/^[0-9a-f]{40}$/.test(args[2]);
const validWorkflow=args.length===3||(args.length===5&&args[3]==='--workflow-file-sha256'&&args[4].length===64&&/^[0-9a-f]{64}$/.test(args[4]));
if (!((args.length===1&&args[0]==='--test-only')||(validSource&&validWorkflow))) { process.stderr.write('Usage: --test-only [--source-sha FULL_LOWERCASE_SHA [--workflow-file-sha256 LOWERCASE_SHA256]]\n'); process.exit(2); }
const workflowSha=args[4]??'a'.repeat(64);

const database = `civicpulse_m2_${instance}`;
const actor = '00000000-0000-4000-8000-000000000041';
const key = 'local-m2-fixture-only';
const runId='9007199254740993:1', sourceSha=args[2]??'f'.repeat(40), baselineId='fixture-deployment';
const kinds = ['organization', 'calendar', 'event', 'layer', 'map'];
const ids = { organization: 'm1-organization', calendar: 'm1-calendar', event: 'm1-withdraw-event', privateEvent: 'm1-private-event', layer: 'm1-withdraw-layer', derived: 'event-locations', map: 'm1-withdraw-map' };
const sentinels = { event: 'M1_WITHDRAW_EVENT_7fd91', layer: 'M1_WITHDRAW_LAYER_7fd91', feature: 'M1_WITHDRAW_FEATURE_7fd91', map: 'M1_WITHDRAW_MAP_7fd91' };
const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
const json = value => `${literal(JSON.stringify(value))}::jsonb`;
const emit = value => process.stdout.write(JSON.stringify(value) + '\n');
let created = false, closing = false, phase = 'container';
const replies=new Map(), calls=[];
function command(args, input) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8', maxBuffer: 16781313, timeout: 60000 });
  if (result.status !== 0) {
    const code = /ERROR:\s+([A-Z0-9]{5}):/.exec(result.stderr || '')?.[1];
    throw Object.assign(new Error('disposable_sql_failed'), { code: code || 'fixture_sql_error' });
  }
  return result.stdout.trim();
}
function sql(statement) {
  return command(['exec', '-i', container, 'psql', '-qAtX', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose'], statement);
}
const asAdmin = statement => `set session authorization authenticated; set "request.jwt.claim.sub"=${literal(actor)}; ${statement} reset session authorization;`;
const asAnon = statement => `set session authorization anon; ${statement} reset session authorization;`;
function manifest() { return JSON.parse(sql(asAnon('select public.publication_manifest();'))); }
function cleanup() {
  if (!created) return;
  const inspected = JSON.parse(command(['inspect', container]))[0];
  if (inspected.Config.Labels?.['org.civicpulse.fixture'] !== instance || inspected.HostConfig.NetworkMode !== 'none') throw new Error('unsafe_cleanup_target');
  command(['rm','--force','--volumes',container]); created=false;
}
function definition(name) {
  const text=readFileSync(root+'tests/enrollment-source.sql','utf8');
  const start=text.indexOf(`create function pg_temp.${name}()`);
  const end=text.indexOf('$$;',start);
  if(start<0 || end<0) throw new Error('fixture_definition_missing');
  return text.slice(start,end+3);
}
const asMachine=(cap,statement)=>`set session authorization cp_m21_${cap}; ${statement} reset session authorization;`;
const challenge=expression=>one(asMachine('reconciler',`select (v-'config')||jsonb_build_object('config_json',(v->'config')::text) from (select ${expression} as v) q;`));
const one=statement=>JSON.parse(sql(statement).split('\n').at(-1));
const uid=value=>{ if(typeof value!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value)) throw new Error('invalid_request'); return literal(value)+'::uuid'; };
function claimTuple() {
  const value=one("select coalesce((select civicpulse_delivery.build_claim_result(j) from civicpulse_delivery.build_jobs j order by fence desc limit 1),'null'::jsonb);");
  if(!value) throw new Error('claim_required');
  return `${uid(value.job_id)},${uid(value.lease_id)},${literal(value.fence)}::bigint`;
}
function operation(name,args) {
  const fields={openBaseline:[],recordBaseline:['challenge_id','evidence_json'],approveBaseline:['observation_id'],openSource:[],recordSource:['challenge_id','evidence_json'],claim:[],heartbeat:[],transition:['expected_state','state','evidence'],inspect:[]}[name];
  if(!fields || !exactKeys(args,fields) || Object.keys(args).length!==fields.length) throw new Error('invalid_request');
  if(name==='openBaseline') return challenge(`civicpulse_delivery.open_provider_observation('baseline',null,null,${literal(baselineId)})`);
  if(name==='recordBaseline') {
    if(typeof args.evidence_json!=='string'||Buffer.byteLength(args.evidence_json)>8388608) throw new Error('invalid_request');
    sourceJsonStats(args.evidence_json,true);
    return one(asMachine('reconciler',`select civicpulse_delivery.record_provider_observation(${uid(args.challenge_id)},${literal(args.evidence_json)}::jsonb);`));
  }
  if(name==='approveBaseline') {
    uid(args.observation_id);
    const epoch=manifest().dataset_epoch;
    const output=sql(`begin; ${asMachine('operator',`select civicpulse_delivery.approve_epoch_baseline(${uid(epoch)},${literal(baselineId)},${json({observation_id:args.observation_id})},'test-only fixture baseline'); select civicpulse_delivery.set_pipeline_paused(false,'test-only fixture ready');`)} commit;`);
    const results=output.split('\n').map(JSON.parse); return {baseline:results[0],pipeline:results[1]};
  }
  if(name==='openSource') return challenge(`civicpulse_delivery.open_source_observation(${literal(runId)},${literal(sourceSha)},'claim',null)`);
  if(name==='recordSource') {
    if(typeof args.evidence_json!=='string'||Buffer.byteLength(args.evidence_json)>8388608) throw new Error('invalid_request');
    sourceJsonStats(args.evidence_json,true);
    return one(asMachine('reconciler',`select civicpulse_delivery.record_source_observation(${uid(args.challenge_id)},${literal(args.evidence_json)}::jsonb);`));
  }
  if(name==='claim') return one(asMachine('runner',`select civicpulse_delivery.claim_build(${literal(runId)},${literal(sourceSha)});`));
  if(name==='heartbeat') return one(asMachine('runner',`select civicpulse_delivery.heartbeat_build(${claimTuple()});`));
  if(name==='transition') {
    if(!['queued','exporting','building','validating','ready'].includes(args.expected_state)||!['exporting','building','validating','ready','failed'].includes(args.state)) throw new Error('invalid_request');
    return one(asMachine('runner',`select civicpulse_delivery.transition_build(${claimTuple()},${literal(args.expected_state)},${literal(args.state)},${json(args.evidence)});`));
  }
  return {...one(`select jsonb_build_object('manifest',public.publication_manifest(),'job',(select jsonb_build_object('job_id',job_id,'state',state,'fence',fence::text,'source_sha',source_sha,'generation',target_generation::text,'snapshot_sha256',snapshot_sha256,'artifact_sha256',artifact_sha256) from civicpulse_delivery.build_jobs order by fence desc limit 1),'precision_preserved',coalesce((select evidence->'protection_before'->'classic'->'fixture_number_tokens'='[9007199254740993,0.12345678901234567890123456789,1e-400]'::jsonb and evidence->'protection_before'->'rulesets'->0->>'id'='9007199254740993' and evidence->'run_before'->>'actor_id'='9007199254740995' from civicpulse_delivery.observations where evidence ? 'run_before' limit 1),false),'receipts',(select count(*) from civicpulse_delivery.observations),'consumed_receipts',(select count(*) from civicpulse_delivery.observations where consumed_at is not null),'external_authority',(select external_authority from civicpulse_delivery.enrollment_state),'live_inventory_complete',(select live_inventory_complete from civicpulse_delivery.pipeline_state));`),calls:[...calls]};
}
const exactKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).every(k => keys.includes(k));
function integer(value, fallback, min, max) {
  if (value === undefined || value === null) return fallback;
  if (!/^(0|[1-9][0-9]*)$/.test(String(value))) throw new Error('invalid_request');
  const n = Number(value);
  if (!Number.isSafeInteger(n) || n < min || n > max) throw new Error('invalid_request');
  return n;
}
async function body(request) {
  let buffer = '';
  for await (const chunk of request) {
    buffer += chunk.toString('utf8');
    if (Buffer.byteLength(buffer) > 4096) throw new Error('invalid_request');
  }
  return buffer ? JSON.parse(buffer) : {};
}
const server = createServer(async (request, response) => {
  try {
    if (closing || request.headers.apikey !== key) { response.writeHead(403).end(); return; }
    const url = new URL(request.url, 'http://127.0.0.1');
    let result;
    if (request.method === 'POST' && url.pathname === '/rest/v1/rpc/publication_manifest' && !url.search) {
      const input = await body(request);
      if (!exactKeys(input, []) || Object.keys(input).length) throw new Error('invalid_request');
      result = sql(asAnon('select public.publication_manifest();'));
    } else if (request.method === 'GET' && url.pathname === '/rest/v1/content') {
      const q = url.searchParams;
      if ([...q.keys()].some(k => !['select', 'order', 'kind', 'limit', 'offset'].includes(k) || q.getAll(k).length !== 1) || q.get('select') !== '*' || q.get('order') !== 'kind.asc,id.asc') throw new Error('invalid_request');
      const kind = q.get('kind');
      if (kind !== null && !kinds.some(k => kind === `eq.${k}`)) throw new Error('invalid_request');
      const limit = integer(q.get('limit'), 100, 1, 1000), offset = integer(q.get('offset'), 0, 0, 2147483647);
      result = sql(asAnon(`select coalesce(jsonb_agg(to_jsonb(p) order by kind collate "C",id collate "C"),'[]'::jsonb) from (select * from public.content ${kind ? `where kind=${literal(kind.slice(3))}` : ''} order by kind collate "C",id collate "C" limit ${limit} offset ${offset}) p;`));
    } else if (request.method === 'POST' && url.pathname === '/rest/v1/rpc/layer_geojson' && !url.search) {
      const input = await body(request);
      if (!exactKeys(input, ['p_layer_id', 'p_limit', 'p_offset']) || typeof input.p_layer_id !== 'string' || !/^[a-z0-9-]{1,128}$/.test(input.p_layer_id)) throw new Error('invalid_request');
      const limit = integer(input.p_limit, 500, 1, 1000), offset = integer(input.p_offset, 0, 0, 2147483647);
      result = sql(asAnon(`select public.layer_geojson(${literal(input.p_layer_id)},${limit},${offset});`));
    } else { response.writeHead(404).end(); return; }
    response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store, max-age=0' }).end(result);
  } catch (error) {
    response.writeHead(error.code === 'P0002' ? 404 : 400, { 'Content-Type': 'application/json' }).end(JSON.stringify({ code: error.code || '22023', message: 'fixture_request_rejected' }));
  }
});
async function close(id) {
  if (closing) return;
  closing = true;
  await new Promise(resolve => server.close(resolve));
  try {
    cleanup();
    if (id !== undefined) emit({ type: 'result', id, command: 'close', result: {closed:true} });
  } catch {
    emit({ type: 'error', id: id ?? null, code: 'fixture_cleanup_failed' });
    process.exitCode = 1;
  } finally { process.stdin.destroy(); }
}
try {
  phase='container';
  created=true; // A timed-out create can still have committed; cleanup checks our unique label.
  command(['run','--detach','--pull=never','--network=none','--name',container,'--label',`org.civicpulse.fixture=${instance}`,'--env','POSTGRES_HOST_AUTH_METHOD=trust','docker.io/postgis/postgis:16-3.5']);
  created=true;
  const inspection=JSON.parse(command(['inspect',container]))[0];
  if(inspection.Config.Image!=='docker.io/postgis/postgis:16-3.5'||inspection.HostConfig.NetworkMode!=='none'||inspection.Mounts?.some(m=>m.Type==='bind')) throw new Error('unsafe_fixture_container');
  for(let attempt=0;;attempt++) {
    const ready=spawnSync('podman',['exec',container,'pg_isready','-U','postgres'],{stdio:'ignore',timeout:5000});
    const processName=spawnSync('podman',['exec',container,'cat','/proc/1/comm'],{encoding:'utf8',timeout:5000});
    if(ready.status===0&&processName.status===0&&processName.stdout.trim()==='postgres') break;
    if(attempt>=120) throw new Error('fixture_database_timeout');
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  command(['exec',container,'createdb','-U','postgres','--template=template0',database]);
  phase = 'migrations';
  const bootstrap = readFileSync(root + 'tests/bootstrap.sql', 'utf8').replace(/create role (\w+) nologin;/g, (_, name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`);
  sql(bootstrap + '\n' + readdirSync(root + 'supabase/migrations').filter(f => f.endsWith('.sql')).sort().map(f => readFileSync(root + 'supabase/migrations/' + f, 'utf8')).join('\n'));
  phase = 'seed';
  const event = { id: ids.event, title: sentinels.event, start: '2026-11-01T12:00:00-05:00', end: '2026-11-01T13:00:00-05:00', category: 'Community', location: 'Synthetic library', address: 'Synthetic public address', sample: false, sourceUrl: 'https://example.org/m1', sourceChecked: '2026-10-17', organizationId: ids.organization, calendarIds: [ids.calendar], coordinates: [-83.6, 32.8] };
  const privateEvent = { ...event, id: ids.privateEvent, title: 'M1 retained private event', addressPrivate: true, address: 'Private location — see organizer for details', location: 'Private location — see organizer for details' }; delete privateEvent.coordinates;
  const records = [
    ['organization', { id: ids.organization, name: 'M1 organization' }],
    ['calendar', { id: ids.calendar, name: 'M1 calendar', organizationId: ids.organization }],
    ['event', event], ['event', privateEvent],
    ['layer', { id: ids.layer, name: sentinels.layer, kind: 'point', geojson: { type: 'FeatureCollection', features: [0, 1].map(i => ({ type: 'Feature', id: `m1-feature-${i}`, properties: { name: sentinels.feature + i }, geometry: { type: 'Point', coordinates: [-83.6 + i / 100, 32.8] } })) } }],
    ['layer', { id: ids.derived, name: 'M1 event locations', kind: 'point', dynamic: 'events' }],
    ['map', { id: ids.map, name: sentinels.map, layers: [ids.layer, ids.derived] }],
  ];
  sql(`insert into auth.users values (${literal(actor)}); insert into civicpulse.members values (${literal(actor)},'admin');` + asAdmin(records.map(([kind, payload]) => `select public.save_draft(${literal(kind)},${literal(payload.id)},${json(payload)},0); select public.publish(${literal(kind)},${literal(payload.id)},1);`).join('\n')) + `
    create role cp_m21_operator nologin; create role cp_m21_reconciler nologin; create role cp_m21_runner nologin;
    grant usage on schema civicpulse_delivery to cp_m21_operator,cp_m21_reconciler,cp_m21_runner;
    insert into civicpulse_delivery.machine_registry(role_name,role_oid,capability,enabled,expires_at)
      select rolname,oid,case rolname when 'cp_m21_operator' then 'publication_operator' when 'cp_m21_reconciler' then 'reconciler' else 'runner' end,true,clock_timestamp()+interval '1 hour'
      from pg_roles where rolname in ('cp_m21_operator','cp_m21_reconciler','cp_m21_runner');
    grant execute on function civicpulse_delivery.enroll_delivery_config(uuid,jsonb,text),civicpulse_delivery.approve_bootstrap(uuid,bigint,jsonb,text),civicpulse_delivery.approve_epoch_baseline(uuid,text,jsonb,text),civicpulse_delivery.set_pipeline_paused(boolean,text) to cp_m21_operator;
    grant execute on function civicpulse_delivery.open_provider_observation(text,uuid,uuid,text),civicpulse_delivery.record_provider_observation(uuid,jsonb),civicpulse_delivery.open_source_observation(text,text,text,uuid),civicpulse_delivery.record_source_observation(uuid,jsonb) to cp_m21_reconciler;
    grant execute on function civicpulse_delivery.claim_build(text,text),civicpulse_delivery.heartbeat_build(uuid,uuid,bigint),civicpulse_delivery.transition_build(uuid,uuid,bigint,text,text,jsonb) to cp_m21_runner;`);
  phase='operator-bootstrap';
  phase='config-definition';
  const policyJson='{"classic":{"required_status_checks":{"strict":true,"contexts":["civicpulse-validate"]},"fixture_number_tokens":[9007199254740993,0.12345678901234567890123456789,1e-400]},"rulesets":[{"id":9007199254740993,"source_type":"Repository","source":"CivicPulse/fixture","enforcement":"disabled","bypass_actors":[]}],"effective_rules":[]}';
  const configJson=sql(definition('config')+` select jsonb_set(jsonb_set(jsonb_set(pg_temp.config(),'{source,protection_bundle}',${literal(policyJson)}::jsonb),'{source,workflow_path}','".github/workflows/validate.yml"'::jsonb),'{source,workflow_file_sha256}',to_jsonb(${literal(workflowSha)}::text));`);
  phase='enroll';
  sql(asMachine('operator',`select civicpulse_delivery.enroll_delivery_config(null,${literal(configJson)}::jsonb,'test-only fixture config');`));
  phase='pre-manifest';
  const before=manifest();
  phase='bootstrap';
  sql(asMachine('operator',`select civicpulse_delivery.approve_bootstrap(${uid(before.dataset_epoch)},${literal(before.generation)}::bigint,${json(before)},'test-only exact fixture inventory');`));
  // Test-only debounce clock change; no receipt/approval/job/live is seeded.
  sql("update civicpulse_delivery.outbox set occurred_at=occurred_at-interval '3 minutes';");
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  emit({type:'ready',schema_version:1,test_only:true,fixture_id:database,url:`http://127.0.0.1:${server.address().port}`,publishableKey:key,
    config_json:configJson,dataset_epoch:manifest().dataset_epoch,manifest:manifest(),expected:{ids,counts:{organization:1,calendar:1,event:2,layer:2,map:1},generation:'8',sentinels},
    inputs:{run_id:runId,source_sha:sourceSha,baseline:{deployment_id:baselineId,source_sha:'c'.repeat(40),artifact_sha256:'d'.repeat(64),served_inventory_sha256:'e'.repeat(64)}}});
  let pending = Buffer.alloc(0);
  process.stdin.on('data', chunk => {
    pending = Buffer.concat([pending, chunk]);
    while (pending.includes(10)) {
      const end = pending.indexOf(10), line = pending.subarray(0, end); pending = pending.subarray(end + 1);
      let input;
      try {
        if (line.length > 16781312) throw new Error();
        input = JSON.parse(line.toString('utf8'));
        if(JSON.stringify(input)!==line.toString('utf8')||!Buffer.from(line.toString('utf8'),'utf8').equals(line))throw new Error();
        if (!exactKeys(input, ['id', 'command', 'args']) || typeof input.id !== 'string' || !/^[a-zA-Z0-9_-]{1,64}$/.test(input.id) || !['openBaseline','recordBaseline','approveBaseline','openSource','recordSource','claim','heartbeat','transition','inspect','close'].includes(input.command) || closing) throw new Error();
        if (input.command === 'close') { if (input.args !== undefined && (!exactKeys(input.args,[]) || Object.keys(input.args).length)) throw new Error(); void close(input.id).catch(() => { process.exitCode = 1; }); return; }
        const encoded=JSON.stringify(input);
        if(replies.has(input.id)) { const saved=replies.get(input.id); if(saved.encoded!==encoded) throw new Error('request_id_reused'); emit(saved.response); continue; }
        if(replies.size>=256) throw new Error('fixture_request_limit');
        const response={type:'result',id:input.id,command:input.command,result:operation(input.command,input.args ?? {})};
        if(calls.length<512)calls.push({sequence:calls.length+1,id:input.id,command:input.command,outcome:'result',code:null});
        replies.set(input.id,{encoded,response}); emit(response);
      } catch (error) { if(['openBaseline','recordBaseline','approveBaseline','openSource','recordSource','claim','heartbeat','transition','inspect','close'].includes(input?.command)&&calls.length<512) calls.push({sequence:calls.length+1,id:typeof input.id==='string'&&/^[a-zA-Z0-9_-]{1,64}$/.test(input.id)?input.id:null,command:input.command,outcome:'error',code:error?.code || 'invalid_fixture_command'}); emit({ type: 'error', id: typeof input?.id === 'string' && /^[a-zA-Z0-9_-]{1,64}$/.test(input.id) ? input.id : null, code: error?.code || 'invalid_fixture_command' }); }
    }
    if (pending.length > 16781312) { emit({ type: 'error', id: null, code: 'fixture_line_too_large' }); void close().catch(() => { process.exitCode = 1; }); }
  });
  process.stdin.on('end', () => { void close().catch(() => { process.exitCode = 1; }); });
  for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => { void close().catch(() => { process.exitCode = 1; }); });
} catch (error) {
  emit({ type: 'error', id: null, code: 'fixture_start_failed', phase, sqlstate: error.code || null });
  try { cleanup(); } catch { emit({ type: 'error', id: null, code: 'fixture_cleanup_failed' }); }
  process.exitCode = 1;
}
