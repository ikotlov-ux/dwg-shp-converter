"""Тесты определений систем координат (geoconverter.crs)."""

import unittest

from geoconverter import crs


class TestProjStrings(unittest.TestCase):
    """PROJ-строки должны содержать параметры из R-скрипта v21."""

    def test_mggt_moscow(self):
        proj = crs.MGGT_MOSCOW_PROJ
        for token in (
            "+proj=tmerc",
            "+lat_0=55.66666666667",
            "+lon_0=37.5",
            "+k=1",
            "+x_0=16.098",
            "+y_0=14.512",
            "+ellps=bessel",
            "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507",
            "+units=m",
            "+no_defs",
        ):
            self.assertIn(token, proj, f"МГГТ: отсутствует {token}")

    def test_moscow_bessel_dgi(self):
        proj = crs.MOSCOW_BESSEL_DGI_PROJ
        for token in (
            "+proj=tmerc",
            "+lat_0=55.66666666666666",
            "+lon_0=37.5",
            "+k=1",
            "+x_0=0",
            "+y_0=0",
            "+a=6377397.0",
            "+rf=299.15",
            "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507",
            "+units=m",
            "+no_defs",
        ):
            self.assertIn(token, proj, f"ДГИ: отсутствует {token}")

    def test_moscow_bessel_dgi_shift(self):
        proj = crs.MOSCOW_BESSEL_DGI_SHIFT_PROJ
        self.assertIn("+x_0=7.2", proj)
        self.assertIn("+y_0=16.8", proj)
        self.assertIn("+a=6377397.0", proj)
        self.assertIn("+rf=299.15", proj)
        # Остальные параметры совпадают с базовым ДГИ.
        self.assertEqual(
            proj.replace("+x_0=7.2", "+x_0=0").replace("+y_0=16.8", "+y_0=0"),
            crs.MOSCOW_BESSEL_DGI_PROJ,
        )

    def test_wgs84(self):
        self.assertEqual(crs.WGS84_PROJ, "EPSG:4326")


class TestResolveCrs(unittest.TestCase):
    def test_presets_resolve(self):
        for key in ("wgs84", "mggt", "moscow_bessel_dgi",
                    "moscow_bessel_dgi_shift"):
            self.assertTrue(crs.resolve_crs(key))

    def test_custom(self):
        proj = "+proj=utm +zone=37 +datum=WGS84"
        self.assertEqual(crs.resolve_crs("custom", proj), proj)

    def test_custom_empty_raises(self):
        with self.assertRaises(ValueError):
            crs.resolve_crs("custom", "   ")

    def test_unknown_key_raises(self):
        with self.assertRaises(ValueError):
            crs.resolve_crs("no_such_crs")


class TestDetectCrs(unittest.TestCase):
    """Автоопределение ДГИ по WKT из .prj (логика R-скрипта)."""

    DGI_WKT = (
        'PROJCS["Moscow_bessel",GEOGCS["GCS_Bessel_Moscow",'
        'DATUM["D_Bessel_Moscow",SPHEROID["Bessel_Moscow",6377397.0,299.15]],'
        'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],'
        'PROJECTION["Transverse_Mercator"],'
        'PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],'
        'PARAMETER["Central_Meridian",37.5],PARAMETER["Scale_Factor",1.0],'
        'PARAMETER["Latitude_Of_Origin",55.66666666666666],'
        'UNIT["Meter",1.0]]'
    )

    def test_dgi_by_name(self):
        self.assertEqual(
            crs.detect_crs_from_prj_text(self.DGI_WKT),
            crs.CRS_DETECTED_DGI,
        )

    def test_dgi_by_parameters(self):
        wkt = self.DGI_WKT.replace('PROJCS["Moscow_bessel"', 'PROJCS["X"')
        self.assertEqual(
            crs.detect_crs_from_prj_text(wkt), crs.CRS_DETECTED_DGI)

    def test_not_dgi(self):
        wkt = 'PROJCS["WGS_1984_UTM_Zone_37N",GEOGCS["GCS_WGS_1984"]]'
        self.assertIsNone(crs.detect_crs_from_prj_text(wkt))

    def test_empty(self):
        self.assertIsNone(crs.detect_crs_from_prj_text(""))
        self.assertIsNone(crs.detect_crs_from_prj_text(None))


if __name__ == "__main__":
    unittest.main()
