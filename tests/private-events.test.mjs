import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { normalizeReviewedPrivateEvents, privateEventFields, privateLocationPlaceholder } from '../scripts/private-events.mjs';
const source = new URL('../../civicpulse-web/src/data/mobilize-events.json', import.meta.url);
test('private normalization rejects unreviewed source bytes', () => {
  assert.throws(() => normalizeReviewedPrivateEvents([], Buffer.from('[]')), /snapshot changed/);
});
test('reviewed 81 private occurrences preserve source evidence and public identity', { skip: !existsSync(source) }, () => {
  const bytes = readFileSync(source), original = JSON.parse(bytes), before = structuredClone(original);
  const derived = normalizeReviewedPrivateEvents(original, bytes);
  assert.equal(derived.filter(row => row.addressPrivate === true).length, 81);
  derived.forEach((row, index) => {
    assert.equal(row.id, original[index].id);
    if (row.addressPrivate !== true) return assert.deepEqual(row, original[index]);
    assert.equal(row.address, privateLocationPlaceholder);
    assert.equal(row.location, privateLocationPlaceholder);
    assert.ok(row.coordinates == null);
    assert.ok(Object.keys(row).every(key => privateEventFields.has(key)));
    for (const key of Object.keys(row)) {
      if (!['address', 'location'].includes(key)) assert.deepEqual(row[key], original[index][key]);
    }
  });
  assert.deepEqual(original, before);
  assert.deepEqual(readFileSync(source), bytes);
  const privateRow = original.find(row => row.addressPrivate === true);
  assert.throws(() => normalizeReviewedPrivateEvents([{ ...privateRow, id: 'unreviewed' }], bytes), /Unreviewed/);
  assert.throws(() => normalizeReviewedPrivateEvents([{ ...privateRow, coordinates: [0, 0] }], bytes), /coordinates/);
});
