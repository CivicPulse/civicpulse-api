import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { readWebData } from './import-web.mjs';
import { testDispatchConcurrency } from './test-dispatch-concurrency.mjs';
const container = process.env.CIVICPULSE_TEST_CONTAINER || 'civicpulse-api-db-test';
function command(args, input) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout;
}
const urlCorpus = JSON.parse(readFileSync('tests/fixtures/cp-source-url-v1.json','utf8'));
urlCorpus.accept.push('https://'+'a'.repeat(63)+'.test/', 'https://'+['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(61)].join('.')+'/');
urlCorpus.reject.push('https://'+'a'.repeat(64)+'.test/', 'https://'+['a'.repeat(63),'b'.repeat(63),'c'.repeat(63),'d'.repeat(62)].join('.')+'/');
const sqlJson = value => "'"+JSON.stringify(value).replaceAll("'", "''")+"'::jsonb";
const urlCasesSql = `
  for value in select item from jsonb_array_elements(${sqlJson(urlCorpus.accept)}) item loop
    select revision into version from public.cms_drafts where kind='event' and id='private-test';
    version:=public.save_draft('event','private-test',base||jsonb_build_object('sourceUrl',value),version);
    begin perform public.publish('event','private-test',version); exception when others then raise exception 'Accepted synthetic URL rejected: %',value; end;
    perform pg_temp.assert((select payload->'sourceUrl'=value from public.content where kind='event' and id='private-test'),'accepted URL original bytes preserved');
  end loop;
  for value in select item from jsonb_array_elements(${sqlJson(urlCorpus.reject.filter(v=>typeof v!=='string'||!v.includes('\u0000')))}) item loop
    perform pg_temp.reject_private(base||jsonb_build_object('sourceUrl',value));
  end loop;
  perform pg_temp.reject_private(base-'sourceUrl');
`;
const database = `civicpulse_test_${Date.now()}`;
command(['exec',container,'createdb','-U','postgres','--template=template0',database]);
try {
  // Auth roles are cluster-wide; the bootstrap is reusable across test databases.
  const bootstrap = readFileSync('tests/bootstrap.sql','utf8').replace(
    /create role (\w+) nologin;/g,
    (_,name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`
  );
  let sql = [bootstrap,...readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort()
    .map(f=>readFileSync(`supabase/migrations/${f}`,'utf8')),...['security.sql','publication.sql','private-events.sql','delivery-status.sql','dispatch.sql','receipt-manifest.sql'].map(file=>readFileSync(`tests/${file}`,'utf8').replace('-- SHARED_URL_PUBLISH_CORPUS',()=>urlCasesSql))].join('\n');
  if (process.argv.includes('--web-data')) {
    const records = await readWebData(new URL('../../civicpulse-web/', import.meta.url).pathname, { rawGeometry: process.argv.includes('--raw-geometry') });
    const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
    sql += `\ncreate temporary table source_issues(document text, problem text); grant insert on source_issues to authenticated;\ninsert into auth.users values ('00000000-0000-4000-8000-000000000001');\ninsert into civicpulse.members(user_id,role) values ('00000000-0000-4000-8000-000000000001','admin');\nset role authenticated;\nselect set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);\n`;
    for (const {kind,payload} of records) {
      const body = `begin perform public.save_draft(${literal(kind)},${literal(payload.id)},${literal(JSON.stringify(payload))}::jsonb,0); perform public.publish(${literal(kind)},${literal(payload.id)},1); exception when others then insert into source_issues values(${literal(kind+'/'+payload.id)},sqlerrm); end`;
      let delimiter;
      do { delimiter = '$audit_' + randomUUID().replaceAll('-', '') + '$'; } while (body.includes(delimiter));
      sql += `do ${delimiter}${body}${delimiter};\n`;
    }
    sql += `reset role; select count(*) as imported_and_published from public.content; select * from source_issues order by document;`;
    if (!process.argv.includes('--raw-geometry')) sql += `do $$ begin if exists(select 1 from source_issues) then raise exception 'Derived import still has publication blockers'; end if; end $$;`;
  }
  const output = command(['exec','-i',container,'psql','-q','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],sql);
  console.log(output.slice(-4000));
  await testDispatchConcurrency(command, container, database);
} finally {
  command(['exec',container,'dropdb','-U','postgres',database]);
}
