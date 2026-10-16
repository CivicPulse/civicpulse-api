import { spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { readWebData } from './import-web.mjs';
const container = process.env.CIVICPULSE_TEST_CONTAINER || 'civicpulse-api-db-test';
function command(args, input) {
  const result = spawnSync('podman', args, { input, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  return result.stdout;
}
const database = `civicpulse_test_${Date.now()}`;
command(['exec',container,'createdb','-U','postgres','--template=template0',database]);
try {
  // Auth roles are cluster-wide; the bootstrap is reusable across test databases.
  const bootstrap = readFileSync('tests/bootstrap.sql','utf8').replace(
    /create role (\w+) nologin;/g,
    (_,name) => `do $$ begin create role ${name} nologin; exception when duplicate_object then null; end $$;`
  );
  let sql = [bootstrap,...readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')).sort()
    .map(f=>readFileSync(`supabase/migrations/${f}`,'utf8')),readFileSync('tests/security.sql','utf8')].join('\n');
  if (process.argv.includes('--web-data')) {
    const records = await readWebData(new URL('../../civicpulse-web/', import.meta.url).pathname);
    const literal = value => "'" + String(value).replaceAll("'", "''") + "'";
    sql += `\ncreate temporary table source_issues(document text, problem text); grant insert on source_issues to authenticated;\ninsert into auth.users values ('00000000-0000-4000-8000-000000000001');\ninsert into civicpulse.members(user_id,role) values ('00000000-0000-4000-8000-000000000001','admin');\nset role authenticated;\nselect set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);\n`;
    for (const {kind,payload} of records) {
      const body = `begin perform public.save_draft(${literal(kind)},${literal(payload.id)},${literal(JSON.stringify(payload))}::jsonb,0); perform public.publish(${literal(kind)},${literal(payload.id)},1); exception when others then insert into source_issues values(${literal(kind+'/'+payload.id)},sqlerrm); end`;
      let delimiter;
      do { delimiter = '$audit_' + randomUUID().replaceAll('-', '') + '$'; } while (body.includes(delimiter));
      sql += `do ${delimiter}${body}${delimiter};\n`;
    }
    sql += `reset role; select count(*) as imported_and_published from public.content; select * from source_issues order by document;`;
  }
  const output = command(['exec','-i',container,'psql','-q','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1'],sql);
  console.log(output.slice(-4000));
} finally {
  command(['exec',container,'dropdb','-U','postgres',database]);
}
