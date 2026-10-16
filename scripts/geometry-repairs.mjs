import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const artifactBytes = readFileSync(new URL('../data/import-repairs/school-zones-elementary.json', import.meta.url));
const artifact = JSON.parse(artifactBytes);
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

export function applyReviewedGeometryRepair(layerId, sourceBytes) {
  const geojson = JSON.parse(sourceBytes.toString('utf8'));
  if (layerId !== 'school-zones-elementary') return { geojson };
  if (sha256(sourceBytes) !== artifact.sourceSha256)
    throw new Error('Elementary-zone source snapshot changed; geometry repair requires review. Use --raw-geometry only to inspect the new source.');
  for (const repair of artifact.repairs) {
    const feature = geojson.features[repair.featureIndex];
    if (feature.id !== repair.featureId || feature.geometry.type !== 'Polygon')
      throw new Error(`Reviewed repair does not match feature ${repair.featureId}`);
    // Only derived geometry changes; all original feature IDs and properties remain.
    feature.geometry = structuredClone(repair.geometry);
  }
  return { geojson, importProvenance: {
    sourcePath: artifact.sourcePath, sourceSha256: artifact.sourceSha256,
    repairArtifact: 'data/import-repairs/school-zones-elementary.json',
    repairArtifactSha256: sha256(artifactBytes), method: artifact.method,
    repairedFeatureIds: artifact.repairs.map(repair => repair.featureId),
    originalSourcePreserved: true,
  } };
}
