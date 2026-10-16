import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { applyReviewedGeometryRepair } from '../scripts/geometry-repairs.mjs';
const source = new URL('../../civicpulse-web/public/data/school-zones-elementary.geojson',import.meta.url);
test('unknown source bytes are rejected, never automatically repaired',()=>{
  assert.throws(()=>applyReviewedGeometryRepair('school-zones-elementary',Buffer.from('{"features":[]}')),/snapshot changed/);
});
test('unrelated layers pass through without repair or invented provenance',()=>{
  const raw=Buffer.from('{"type":"FeatureCollection","features":[]}');
  assert.deepEqual(applyReviewedGeometryRepair('other',raw),{geojson:JSON.parse(raw)});
});
test('reviewed snapshot preserves every field except the two derived geometries', {skip:!existsSync(source)},()=>{
  const bytes=readFileSync(source), original=JSON.parse(bytes);
  const result=applyReviewedGeometryRepair('school-zones-elementary',bytes);
  assert.deepEqual(result.importProvenance.repairedFeatureIds,['school-zones-elementary:5','school-zones-elementary:10']);
  for (let i=0;i<original.features.length;i++) {
    const derived=result.geojson.features[i];
    if ([4,9].includes(i)) {
      assert.notDeepEqual(derived.geometry,original.features[i].geometry);
      assert.deepEqual({...derived,geometry:original.features[i].geometry},original.features[i]);
    } else assert.deepEqual(derived,original.features[i]);
  }
  assert.deepEqual(readFileSync(source),bytes);
  assert.throws(()=>applyReviewedGeometryRepair('school-zones-elementary',Buffer.concat([bytes,Buffer.from('\n')])),/snapshot changed/);
});
