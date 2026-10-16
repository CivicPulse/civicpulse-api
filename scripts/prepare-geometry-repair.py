"""Regenerate ONLY the reviewed elementary-zone repair; never edit source data.
Requires: python3 -m pip install -r scripts/requirements-geometry.txt
Usage: python3 scripts/prepare-geometry-repair.py [path/to/civicpulse-web]
"""
import hashlib
import json
from pathlib import Path
import sys

import shapely
from shapely.geometry import mapping, shape

SOURCE_SHA256 = '235080b70b452d65e2796b29cc30ec004d266b25b8f5e68e552e2fec38fd80bb'
SOURCE_PATH = 'public/data/school-zones-elementary.geojson'
EXPECTED = {4: 'school-zones-elementary:5', 9: 'school-zones-elementary:10'}


def prepare(root):
    source = root / SOURCE_PATH
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != SOURCE_SHA256:
        raise ValueError('Source snapshot changed; review it before regenerating repairs')
    if shapely.__version__ != '2.1.2':
        raise ValueError('Use pinned Shapely 2.1.2 to regenerate the reviewed artifact')
    collection = json.loads(original)
    repairs = []
    invalid = {i for i, feature in enumerate(collection['features']) if not shape(feature['geometry']).is_valid}
    if invalid != set(EXPECTED):
        raise ValueError(f'Unexpected invalid features: {invalid}')
    for index, feature_id in EXPECTED.items():
        feature = collection['features'][index]
        if feature['id'] != feature_id:
            raise ValueError('Source feature identity changed')
        geometry = shape(feature['geometry'])
        repaired = shapely.make_valid(geometry, method='linework')
        relative_area_delta = abs(repaired.area - geometry.area) / geometry.area
        if not (geometry.geom_type == repaired.geom_type == 'Polygon' and repaired.is_valid
                and not repaired.is_empty and geometry.boundary.equals(repaired.boundary)
                and geometry.hausdorff_distance(repaired) == 0 and relative_area_delta < 1e-12):
            raise ValueError(f'Repair would change the reviewed boundary or area: {feature_id}')
        repairs.append({
            'featureIndex': index, 'featureId': feature_id,
            'featureName': feature['properties']['name'],
            'reason': shapely.is_valid_reason(geometry),
            'originalGeometry': feature['geometry'],
            'geometry': mapping(repaired),
            'evidence': {
                'originalType': geometry.geom_type, 'derivedType': repaired.geom_type,
                'derivedValid': repaired.is_valid, 'boundaryEquals': True,
                'hausdorffDistanceDegrees': geometry.hausdorff_distance(repaired),
                'originalAreaSquareDegrees': geometry.area,
                'derivedAreaSquareDegrees': repaired.area,
                'relativeAreaDelta': relative_area_delta,
                'originalInteriorRings': len(geometry.interiors),
                'derivedInteriorRings': len(repaired.interiors),
            },
        })
    if source.read_bytes() != original:
        raise ValueError('Source changed during repair generation')
    return {'version': 1, 'sourcePath': SOURCE_PATH, 'sourceSha256': SOURCE_SHA256,
            'method': 'shapely.make_valid(method="linework")',
            'shapelyVersion': shapely.__version__, 'geosVersion': shapely.geos_version_string,
            'repairs': repairs}


if __name__ == '__main__':
    root = Path(sys.argv[1] if len(sys.argv) > 1 else '../civicpulse-web')
    artifact = Path(__file__).resolve().parents[1] / 'data/import-repairs/school-zones-elementary.json'
    artifact.write_text(json.dumps(prepare(root), indent=2) + '\n')
    print(f'Wrote derived geometry artifact: {artifact}')
