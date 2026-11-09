"""Геопространственный конвертер DWG/DXF/SHP/GeoJSON/GPKG.

Python-версия R-скрипта convert_dwg_to_shp_v21.r:
перевод векторных данных между DWG, DXF, SHP, GeoJSON и GPKG
с перепроецированием между настраиваемыми системами координат.

Модули:
    crs      — определения систем координат (СК), палитра цветов;
    core     — вызовы ogr2ogr и ODA File Converter (subprocess);
    features — маркеры, подписи, легенда, XLSX (ezdxf + openpyxl);
    gui      — графический интерфейс на tkinter (русский язык).
"""

__version__ = "1.1.0"

# Ключи СК, используемые в GUI (переопределять не рекомендуется).
CRS_WGS84 = "wgs84"
CRS_MGGT = "mggt"
CRS_MOSCOW_BESSEL_DGI = "moscow_bessel_dgi"
CRS_MOSCOW_BESSEL_DGI_SHIFT = "moscow_bessel_dgi_shift"
CRS_MSK_BORSHCHEVIK = "msk_borshchevik"
CRS_CUSTOM = "custom"

# Поддерживаемые входные и выходные форматы.
INPUT_EXTENSIONS = (".dwg", ".dxf", ".shp", ".geojson", ".gpkg")
OUTPUT_FORMATS = ("DWG", "DXF", "SHP", "GeoJSON", "GPKG")
