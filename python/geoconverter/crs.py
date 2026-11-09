"""Определения систем координат (СК) и палитра цветов.

Параметры СК перенесены из R-скрипта convert_dwg_to_shp_v21.r (v21).
Каждая СК описывается PROJ-строкой, которая передаётся ogr2ogr
в аргументы -s_srs / -t_srs как один элемент списка аргументов.
"""

from __future__ import annotations

import re

# ---------------------------------------------------------------------------
# PROJ-строки СК (точно из R-скрипта)
# ---------------------------------------------------------------------------

# WGS84 — географическая система (широта/долгота), EPSG:4326.
WGS84_PROJ = "EPSG:4326"

# МГГТ Москвы (MGGT Moscow local): поперечная Меркатора на эллипсоиде Бесселя,
# центральный меридиан 37.5, широта начала 55.66666666667,
# ложные восток/север 16.098 / 14.512 + датумный сдвиг на WGS84.
# (см. write_mggt_moscow_prj_file в R-скрипте: x_0=16.098, y_0=14.512,
#  TOWGS84 316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507).
MGGT_MOSCOW_PROJ = (
    "+proj=tmerc +lat_0=55.66666666667 +lon_0=37.5 +k=1 "
    "+x_0=16.098 +y_0=14.512 +ellps=bessel "
    "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507 "
    "+units=m +no_defs"
)

# Moscow_bessel ДГИ (поставка ДГИ, Zony_OOZT_DGI-E-114072-26.prj):
# поперечная Меркатора на сфероиде Bessel_Moscow (a=6377397.0, rf=299.15),
# центральный меридиан 37.5, широта начала 55.66666666666666,
# ложные восток/север 0. В .prj заказчика датумного сдвига нет, поэтому
# пресет ДОБАВЛЯЕТ известный MGGT TOWGS84 (как и в R-скрипте).
MOSCOW_BESSEL_DGI_PROJ = (
    "+proj=tmerc +lat_0=55.66666666666666 +lon_0=37.5 +k=1 "
    "+x_0=0 +y_0=0 +a=6377397.0 +rf=299.15 "
    "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507 "
    "+units=m +no_defs"
)

# Moscow_bessel ДГИ со смещением (ручная поправка по контрольной точке):
# результат на ~7.2 м восточнее и ~16.8 м севернее истинного положения,
# поэтому ложные восток/север увеличены (0 -> 7.2 / 16.8), что смещает
# результат на юго-запад. Остальные параметры совпадают с ДГИ.
MOSCOW_BESSEL_DGI_SHIFT_X = 7.2
MOSCOW_BESSEL_DGI_SHIFT_Y = 16.8
MOSCOW_BESSEL_DGI_SHIFT_PROJ = (
    "+proj=tmerc +lat_0=55.66666666666666 +lon_0=37.5 +k=1 "
    f"+x_0={MOSCOW_BESSEL_DGI_SHIFT_X} +y_0={MOSCOW_BESSEL_DGI_SHIFT_Y} "
    "+a=6377397.0 +rf=299.15 "
    "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507 "
    "+units=m +no_defs"
)

# МСК Борщевика (локальная СК Москвы для выгрузок борщевика ДЗЗ / обращений):
# поперечная Меркатора на эллипсоиде Красовского, центральный меридиан 37.5,
# широта начала 0, ложные восток/север 1250000 / -1050000 + сдвиг СК-42 -> WGS84.
MSK_BORSHCHEVIK_PROJ = (
    "+proj=tmerc +lat_0=0 +lon_0=37.5 +k=1 "
    "+x_0=1250000 +y_0=-1050000 +ellps=krass "
    "+towgs84=23.57,-140.95,-79.8,0,0,0,0 "
    "+units=m +no_defs"
)

# Порядок пресетов в выпадающих списках GUI. Ключ "custom" означает
# пользовательскую PROJ-строку из поля ввода.
CRS_PRESETS: dict[str, dict] = {
    "wgs84": {
        "label": "WGS84 (EPSG:4326)",
        "proj": WGS84_PROJ,
    },
    "mggt": {
        "label": "МГГТ Москвы (x_0=16.098, y_0=14.512)",
        "proj": MGGT_MOSCOW_PROJ,
    },
    "moscow_bessel_dgi": {
        "label": "Moscow_bessel ДГИ (x_0=0, y_0=0)",
        "proj": MOSCOW_BESSEL_DGI_PROJ,
    },
    "moscow_bessel_dgi_shift": {
        "label": "Moscow_bessel ДГИ (смещение x=7.2, y=16.8)",
        "proj": MOSCOW_BESSEL_DGI_SHIFT_PROJ,
    },
    "msk_borshchevik": {
        "label": "МСК Борщевика (x_0=1250000, y_0=-1050000)",
        "proj": MSK_BORSHCHEVIK_PROJ,
    },
    "custom": {
        "label": "Пользовательская PROJ-строка",
        "proj": "",
    },
}

CRS_KEYS = list(CRS_PRESETS)

# Ключ СК, который предлагается при автоопределении по .prj (паттерн ДГИ).
CRS_DETECTED_DGI = "moscow_bessel_dgi"


def crs_label(key: str) -> str:
    """Человекочитаемое название пресета СК по его ключу."""
    return CRS_PRESETS[key]["label"]


def resolve_crs(key: str, custom_proj: str = "") -> str:
    """Вернуть строку -s_srs/-t_srs (PROJ или EPSG:...) для ogr2ogr.

    Параметры
    ---------
    key : str
        Ключ пресета из CRS_PRESETS либо "custom".
    custom_proj : str
        PROJ-строка (или EPSG:код) для ключа "custom".

    Исключения
    ----------
    ValueError — если ключ неизвестен или пользовательская строка пуста.
    """
    if key == "custom":
        value = (custom_proj or "").strip()
        if not value:
            raise ValueError(
                "Пользовательская PROJ-строка пуста: введите её в поле ввода."
            )
        return value
    try:
        return CRS_PRESETS[key]["proj"]
    except KeyError as exc:  # pragma: no cover - защита от опечаток
        raise ValueError(f"Неизвестный пресет СК: {key!r}") from exc


# ---------------------------------------------------------------------------
# Категориальная палитра (из R-скрипта .deterministic_hex + 5 цветов tab20)
# ---------------------------------------------------------------------------

# 15 цветов взяты из R-скрипта (палитра matplotlib tab20, первые 15),
# 5 последних добавлены для полных 20 категорий.
PALETTE = (
    "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
    "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
    "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5",
    "#c49c94", "#f7b6d2", "#c7c7c7", "#dbdb8d", "#9edae5",
)


def palette_color(index: int) -> str:
    """Цвет палитры по индексу категории (с циклическим повтором)."""
    return PALETTE[index % len(PALETTE)]


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    """'#RRGGBB' -> (r, g, b). Некорректная строка даёт чёрный."""
    m = re.fullmatch(r"#?([0-9A-Fa-f]{6})", (value or "").strip())
    if not m:
        return (0, 0, 0)
    h = m.group(1)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# ---------------------------------------------------------------------------
# Автоопределение исходной СК по .prj (WKT)
# ---------------------------------------------------------------------------

def detect_crs_from_prj_text(wkt: str) -> str | None:
    """Определить ключ пресета СК по тексту WKT из .prj-файла.

    Логика из detect_shp_crs R-скрипта: паттерн заказчика ДГИ —
    сфероид Bessel_Moscow / имя Moscow_bessel, центральный меридиан 37.5,
    широта начала ~55.66 и нулевые ложные восток/север. Такая .prj не
    содержит датумного сдвига, поэтому предлагается пресет ДГИ,
    который добавляет известный MGGT TOWGS84.

    Возвращает ключ пресета или None, если паттерн не распознан.
    """
    if not wkt:
        return None
    text = re.sub(r"\s+", "", wkt)
    name_m = re.search(r'PROJCS\["([^"]+)', text) or re.search(r'GEOGCS\["([^"]+)', text)
    name = name_m.group(1) if name_m else ""

    is_dgi = (
        "moscow_bessel" in name.lower()
        or (
            "bessel_moscow" in text.lower()
            and re.search(r'"Central_Meridian",37\.5', text)
            and re.search(r'"Latitude_Of_Origin",55\.66', text)
            and re.search(r'"False_Easting",0(?:[.,\]])', text)
            and re.search(r'"False_Northing",0(?:[.,\]])', text)
        )
    )
    if is_dgi:
        return CRS_DETECTED_DGI
    return None


def detect_crs_from_prj_file(prj_path: str) -> str | None:
    """Прочитать .prj-файл и определить ключ пресета СК (или None)."""
    try:
        with open(prj_path, "r", encoding="utf-8", errors="replace") as fh:
            return detect_crs_from_prj_text(fh.read())
    except OSError:
        return None
