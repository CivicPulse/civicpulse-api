import json
from pathlib import Path
import unittest
from shapely.geometry import shape


class ReviewedGeometryTests(unittest.TestCase):
    def test_only_reviewed_features_and_boundary_equivalence(self):
        artifact = json.loads((Path(__file__).resolve().parents[1] / 'data/import-repairs/school-zones-elementary.json').read_text())
        self.assertEqual([r['featureId'] for r in artifact['repairs']], ['school-zones-elementary:5', 'school-zones-elementary:10'])
        for repair in artifact['repairs']:
            with self.subTest(feature=repair['featureId']):
                original, derived = shape(repair['originalGeometry']), shape(repair['geometry'])
                self.assertFalse(original.is_valid)
                self.assertTrue(derived.is_valid)
                self.assertFalse(derived.is_empty)
                self.assertEqual(original.geom_type, 'Polygon')
                self.assertEqual(derived.geom_type, 'Polygon')
                self.assertTrue(original.boundary.equals(derived.boundary))
                self.assertEqual(original.hausdorff_distance(derived), 0)
                self.assertLess(abs(original.area-derived.area)/original.area, 1e-12)
                self.assertEqual(len(derived.interiors), 1)


if __name__ == '__main__':
    unittest.main()
