"""Тесты оформления вектор -> DWG (geoconverter.features).

Тесты не требуют ezdxf/openpyxl: проверяются чистые функции
(палитра, легенда, категории, ACI) и работа с GeoJSON через stdlib.
"""

import json
import os
import tempfile
import unittest

from geoconverter import features
from geoconverter.crs import PALETTE


class TestPalette(unittest.TestCase):
    def test_palette_20_colors(self):
        self.assertEqual(len(PALETTE), 20)
        for color in PALETTE:
            self.assertRegex(color, r"^#[0-9A-Fa-f]{6}$")

    def test_colors_from_r_script(self):
        # Первые 15 цветов — точно из R-скрипта (.deterministic_hex).
        expected = (
            "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
            "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
            "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5",
        )
        self.assertEqual(tuple(PALETTE[:15]), expected)

    def test_palette_color_cycles(self):
        self.assertEqual(features.palette_color(0), PALETTE[0])
        self.assertEqual(features.palette_color(20), PALETTE[0])
        self.assertEqual(features.palette_color(25), PALETTE[5])


class TestLegendAnchor(unittest.TestCase):
    def test_anchor_right_bottom_with_offset(self):
        xs, ys = [0.0, 100.0, 50.0], [0.0, 200.0, 50.0]
        x, y = features.legend_anchor(xs, ys)
        self.assertAlmostEqual(x, 120.0)  # max(x) + 20
        self.assertAlmostEqual(y, 0.0)    # min(y)

    def test_offset_at_least_20(self):
        x, y = features.legend_anchor([10.0], [10.0], offset=5.0)
        self.assertGreaterEqual(x - 10.0, 20.0)

    def test_empty_coords(self):
        self.assertEqual(features.legend_anchor([], []), (0.0, 0.0))


class TestCategoryColors(unittest.TestCase):
    def test_codes_and_colors(self):
        cats = features.category_colors(["B", "A", "B", None])
        self.assertEqual(cats["B"]["code"], 1)
        self.assertEqual(cats["A"]["code"], 2)
        self.assertEqual(cats[""]["code"], 3)  # None -> ""
        self.assertEqual(cats["B"]["hex"], PALETTE[0])
        self.assertEqual(cats["A"]["hex"], PALETTE[1])

    def test_more_than_20_categories_cycle(self):
        values = [f"v{i}" for i in range(25)]
        cats = features.category_colors(values)
        self.assertEqual(len(cats), 25)
        self.assertEqual(cats["v24"]["hex"], PALETTE[4])


class TestRgbToAci(unittest.TestCase):
    def test_basic_colors(self):
        self.assertEqual(features.rgb_to_aci((255, 0, 0)), 1)    # красный
        self.assertEqual(features.rgb_to_aci((255, 255, 0)), 2)  # жёлтый
        self.assertEqual(features.rgb_to_aci((0, 255, 0)), 3)    # зелёный
        self.assertEqual(features.rgb_to_aci((0, 0, 255)), 5)    # синий

    def test_in_range(self):
        for rgb in ((10, 200, 30), (128, 128, 128), (250, 5, 250)):
            aci = features.rgb_to_aci(rgb)
            self.assertTrue(1 <= aci <= 255)


class TestGeoJsonHelpers(unittest.TestCase):
    def _write_gj(self, tmp, feats):
        path = os.path.join(tmp, "test.geojson")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"type": "FeatureCollection", "features": feats}, fh)
        return path

    def test_iter_points(self):
        feats = [
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [1.5, 2.5]},
             "properties": {"name": "p1"}},
            {"type": "Feature",
             "geometry": {"type": "LineString", "coordinates": [[0, 0], [1, 1]]},
             "properties": {"name": "l1"}},
        ]
        pts = list(features.iter_points(feats))
        self.assertEqual(len(pts), 1)
        self.assertEqual(pts[0][0], 1.5)
        self.assertEqual(pts[0][2]["name"], "p1")

    def test_split_geojson_by_field(self):
        feats = [
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [0, 0]},
             "properties": {"zone": "A"}},
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [1, 1]},
             "properties": {"zone": "B"}},
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [2, 2]},
             "properties": {"zone": "A"}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_gj(tmp, feats)
            parts = features.split_geojson_by_field(path, tmp, "zone")
            self.assertEqual(len(parts), 2)
            names = [name for name, _ in parts]
            self.assertEqual(sorted(names), ["A", "B"])
            for name, ppath in parts:
                with open(ppath, encoding="utf-8") as fh:
                    data = json.load(fh)
                zones = {f["properties"]["zone"] for f in data["features"]}
                self.assertEqual(zones, {name})

    def test_split_no_field_or_single_value(self):
        feats = [
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [0, 0]},
             "properties": {"zone": "A"}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_gj(tmp, feats)
            self.assertEqual(features.split_geojson_by_field(path, tmp, ""), [])
            self.assertEqual(
                features.split_geojson_by_field(path, tmp, "zone"), [])
            self.assertEqual(
                features.split_geojson_by_field(path, tmp, "missing"), [])


class TestOptionsNeedFeatures(unittest.TestCase):
    def test_flags(self):
        self.assertFalse(features.options_need_features({}))
        self.assertTrue(features.options_need_features({"markers": True}))
        self.assertTrue(features.options_need_features({"label_field": "id"}))
        self.assertTrue(features.options_need_features({"legend": True}))
        self.assertTrue(features.options_need_features({"xlsx": True}))
        # Только разбивка по полю — оформление не нужно.
        self.assertFalse(features.options_need_features({"split_field": "zone"}))


if __name__ == "__main__":
    unittest.main()
