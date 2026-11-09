"""Смоук-тест оформления DXF (требует ezdxf + openpyxl; пропускается без них)."""

import json
import os
import tempfile
import unittest

from geoconverter import features

try:
    import ezdxf  # noqa: F401
    import openpyxl  # noqa: F401
    HAS_LIBS = True
except ImportError:
    HAS_LIBS = False


@unittest.skipUnless(HAS_LIBS, "ezdxf/openpyxl не установлены")
class TestApplyDwgFeatures(unittest.TestCase):
    def _setup(self, tmp):
        feats = [
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [100.0, 200.0]},
             "properties": {"name": "P1", "zone": "A"}},
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [150.0, 180.0]},
             "properties": {"name": "P2", "zone": "B"}},
            {"type": "Feature",
             "geometry": {"type": "Point", "coordinates": [120.0, 150.0]},
             "properties": {"name": "P3", "zone": "A"}},
        ]
        gj = os.path.join(tmp, "pts.geojson")
        with open(gj, "w", encoding="utf-8") as fh:
            json.dump({"type": "FeatureCollection", "features": feats}, fh)
        dxf = os.path.join(tmp, "pts.dxf")
        ezdxf.new("R2010").saveas(dxf)
        return gj, dxf

    def test_markers_labels_legend_xlsx(self):
        import ezdxf
        from openpyxl import load_workbook

        with tempfile.TemporaryDirectory() as tmp:
            gj, dxf = self._setup(tmp)
            opts = {
                "geojson_source": gj, "markers": True, "marker_diameter": 2.0,
                "color_field": "zone", "label_field": "name",
                "label_height": 2.5, "legend": True, "xlsx": True,
            }
            created = features.apply_dwg_features(dxf, opts, tmp, log=lambda m: None)

            doc = ezdxf.readfile(dxf)
            msp = doc.modelspace()
            circles = [e for e in msp if e.dxftype() == "CIRCLE"]
            hatches = [e for e in msp if e.dxftype() == "HATCH"]
            texts = [e for e in msp if e.dxftype() == "TEXT"]
            # 3 маркера + 2 маркера легенды; у маркеров — заливка.
            self.assertEqual(
                len([c for c in circles if c.dxf.layer == "point_markers"]), 3)
            self.assertEqual(
                len([c for c in circles if c.dxf.layer == "point_legend"]), 2)
            self.assertEqual(len(hatches), 5)
            self.assertEqual(
                len([t for t in texts if t.dxf.layer == "labels"]), 3)
            self.assertEqual(
                sorted(t.dxf.text for t in texts
                       if t.dxf.layer == "point_legend"), ["1", "2"])
            # True color у маркеров (по категориям зоны A и B).
            tcs = {c.dxf.true_color for c in circles
                   if c.dxf.layer == "point_markers"}
            self.assertEqual(len(tcs), 2)

            # XLSX: листы points и legend.
            self.assertEqual(len(created), 1)
            wb = load_workbook(created[0])
            self.assertIn("points", wb.sheetnames)
            self.assertIn("legend", wb.sheetnames)
            ws = wb["points"]
            self.assertEqual(ws.max_row, 4)  # заголовок + 3 точки
            self.assertEqual(
                [c.value for c in ws[1]], ["name", "zone", "X", "Y"])
            ws2 = wb["legend"]
            self.assertEqual(
                [c.value for c in ws2[1]],
                ["legend_code", "original_value", "hex_color", "aci_color"])
            self.assertEqual(ws2.max_row, 3)  # заголовок + 2 категории

    def test_no_options_no_changes(self):
        """Без опций оформления DXF не изменяется, XLSX не создаётся."""
        with tempfile.TemporaryDirectory() as tmp:
            gj, dxf = self._setup(tmp)
            created = features.apply_dwg_features(
                dxf, {"split_field": "zone"}, tmp, log=lambda m: None)
            self.assertEqual(created, [])


if __name__ == "__main__":
    unittest.main()
