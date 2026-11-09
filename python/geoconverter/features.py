"""Оформление вектор -> DWG: маркеры, подписи, легенда, выгрузка XLSX.

Портировано из R-скрипта convert_dwg_to_shp_v21.r (упрощено):
- маркеры точек — залитые круги на слое point_markers, цвет по значению
  поля (категориальная палитра 20 цветов, true color);
- подписи точек — TEXT на слое labels;
- легенда — справа-снизу от объектов (отступ >= 20 м): маркеры тех же
  цветов/размеров + цифровые подписи 1, 2, 3… на слое point_legend;
- XLSX — лист points (атрибуты + пересчитанные координаты) и лист legend
  (legend_code, original_value, hex_color, aci_color).

ezdxf и openpyxl импортируются ЛЕНИВО внутри функций: без них модуль
импортируется и работает (кроме собственно оформления), а тесты crs.py
проходят без внешних зависимостей.
"""

from __future__ import annotations

import json
import os
from typing import Callable, Iterable

from .crs import hex_to_rgb, palette_color

# Имена слоёв в DXF/DWG.
LAYER_MARKERS = "point_markers"
LAYER_LABELS = "labels"
LAYER_LEGEND = "point_legend"

# Минимальный отступ легенды от объектов, м (>= 20 м по ТЗ).
LEGEND_OFFSET = 20.0
# Высота текста по умолчанию, м.
DEFAULT_TEXT_HEIGHT = 2.5
# Количество сегментов аппроксимации круга для штриховки.
CIRCLE_SEGMENTS = 32


# ---------------------------------------------------------------------------
# Чистые (тестируемые) функции
# ---------------------------------------------------------------------------

def options_need_features(opts: dict) -> bool:
    """True, если запрошено хотя бы одно оформление вектор -> DWG."""
    return bool(
        opts.get("markers")
        or opts.get("label_field")
        or opts.get("legend")
        or opts.get("xlsx")
    )


def legend_anchor(xs: Iterable[float], ys: Iterable[float],
                  offset: float = LEGEND_OFFSET) -> tuple[float, float]:
    """Якорь легенды: справа-снизу от объектов, отступ не менее offset м.

    Возвращает (x, y) — левый нижний угол легенды. Если координат нет,
    возвращается (0, 0).
    """
    xs = list(xs)
    ys = list(ys)
    if not xs or not ys:
        return (0.0, 0.0)
    return (max(xs) + max(offset, LEGEND_OFFSET), min(ys))


def category_colors(values: Iterable) -> dict:
    """Сопоставить уникальным значениям поля код легенды и цвет.

    Возвращает {значение: {"code": int, "hex": str}}. Значения
    упорядочиваются по первому появлению (как в R-скрипте для слоёв).
    """
    seen: dict = {}
    for v in values:
        key = v if v is not None else ""
        if key not in seen:
            seen[key] = {"code": len(seen) + 1, "hex": palette_color(len(seen))}
    return seen


def _aci_table() -> dict[int, tuple[int, int, int]]:
    """Таблица ACI -> RGB (1..255). Кэшируется при первом вызове.

    При наличии ezdxf используется настоящая таблица AutoCAD Color Index
    (ezdxf.colors.aci2rgb); иначе — приближение: базовые цвета 1-9 и 24
    оттенка x 10 уровней яркости (структура реальной таблицы ACI).
    """
    global _ACI_TABLE_CACHE
    if _ACI_TABLE_CACHE is not None:
        return _ACI_TABLE_CACHE
    table: dict[int, tuple[int, int, int]] = {}
    try:
        from ezdxf.colors import aci2rgb  # ленивый импорт

        for i in range(1, 256):
            rgb = aci2rgb(i)
            table[i] = (rgb[0], rgb[1], rgb[2])
    except Exception:
        table = {
            1: (255, 0, 0), 2: (255, 255, 0), 3: (0, 255, 0),
            4: (0, 255, 255), 5: (0, 0, 255), 6: (255, 0, 255),
            7: (255, 255, 255), 8: (128, 128, 128), 9: (192, 192, 192),
        }
        try:
            import colorsys

            for hue in range(24):
                for level in range(10):
                    r, g, b = colorsys.hsv_to_rgb(
                        hue / 24.0, 1.0, 1.0 - level * 0.1)
                    table[10 + hue * 10 + level] = (
                        round(r * 255), round(g * 255), round(b * 255))
        except Exception:
            pass
    _ACI_TABLE_CACHE = table
    return table


_ACI_TABLE_CACHE: dict[int, tuple[int, int, int]] | None = None


def rgb_to_aci(rgb: tuple[int, int, int]) -> int:
    """Ближайший цветовой индекс AutoCAD (ACI 1..255) для RGB.

    Поиск по евклидову расстоянию в RGB. При наличии ezdxf — по настоящей
    таблице ACI, иначе по приближённой (см. _aci_table).
    """
    best, best_d = 7, None
    for idx, c in _aci_table().items():
        d = sum((a - b) ** 2 for a, b in zip(rgb, c))
        if best_d is None or d < best_d:
            best, best_d = idx, d
    return best


# ---------------------------------------------------------------------------
# Разбор GeoJSON (stdlib json)
# ---------------------------------------------------------------------------

def read_geojson_features(geojson_path: str) -> list[dict]:
    """Прочитать GeoJSON, вернуть список фич с geometry/properties."""
    with open(geojson_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    if isinstance(data, dict) and data.get("type") == "FeatureCollection":
        return list(data.get("features") or [])
    if isinstance(data, dict) and data.get("type") == "Feature":
        return [data]
    return []


def iter_points(features: list[dict]):
    """Выдать точки (x, y, properties) из фич GeoJSON.

    Учитываются геометрии Point и MultiPoint.
    """
    for feat in features:
        geom = feat.get("geometry") or {}
        props = feat.get("properties") or {}
        gtype = (geom.get("type") or "").lower()
        coords = geom.get("coordinates")
        if gtype == "point" and isinstance(coords, (list, tuple)) and len(coords) >= 2:
            yield (float(coords[0]), float(coords[1]), props)
        elif gtype == "multipoint" and isinstance(coords, list):
            for c in coords:
                if isinstance(c, (list, tuple)) and len(c) >= 2:
                    yield (float(c[0]), float(c[1]), props)


def iter_all_coords(features: list[dict]):
    """Все координаты всех геометрий (для расчёта якоря легенды)."""
    def walk(coords):
        if isinstance(coords, (list, tuple)) and coords:
            if isinstance(coords[0], (int, float)):
                if len(coords) >= 2:
                    yield (float(coords[0]), float(coords[1]))
            else:
                for sub in coords:
                    yield from walk(sub)

    for feat in features:
        geom = feat.get("geometry") or {}
        yield from walk(geom.get("coordinates"))


def split_geojson_by_field(geojson_path: str, work_dir: str,
                           field: str) -> list[tuple[str, str]]:
    """Разбить GeoJSON на части по уникальным значениям поля.

    Возвращает [(значение, путь к geojson части)] либо [], если поле
    не задано/не найдено или значений меньше двух.
    """
    field = (field or "").strip()
    if not field:
        return []
    features = read_geojson_features(geojson_path)
    if not features:
        return []
    groups: dict = {}
    for feat in features:
        key = (feat.get("properties") or {}).get(field)
        key = "" if key is None else str(key)
        groups.setdefault(key, []).append(feat)
    if len(groups) < 2:
        return []
    parts = []
    for value, feats in groups.items():
        part_path = os.path.join(work_dir, f"part_{len(parts)}.geojson")
        with open(part_path, "w", encoding="utf-8") as fh:
            json.dump({"type": "FeatureCollection", "features": feats},
                      fh, ensure_ascii=False)
        parts.append((value, part_path))
    return parts


# ---------------------------------------------------------------------------
# Применение оформления к DXF (ezdxf) и выгрузка XLSX (openpyxl)
# ---------------------------------------------------------------------------

def _true_color_int(rgb: tuple[int, int, int]) -> int:
    """True color DXF как целое 0x00RRGGBB (формат ezdxf)."""
    return (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]


def _solid_hatch(msp, center: tuple[float, float], radius: float,
                 layer: str, rgb: tuple[int, int, int]) -> None:
    """Залитый круг: HATCH со штриховкой SOLID по контуру круга."""
    import math

    hatch = msp.add_hatch(dxfattribs={
        "layer": layer,
        "true_color": _true_color_int(rgb),
    })
    hatch.set_pattern_fill("SOLID", scale=1.0)
    pts = []
    for i in range(CIRCLE_SEGMENTS):
        a = 2 * math.pi * i / CIRCLE_SEGMENTS
        pts.append((center[0] + radius * math.cos(a),
                    center[1] + radius * math.sin(a)))
    hatch.paths.add_polyline_path(pts, is_closed=True)


def apply_dwg_features(dxf_path: str, opts: dict, out_dir: str,
                       log: Callable = print) -> list[str]:
    """Добавить оформление в DXF и/или выгрузить XLSX с точками.

    opts:
        geojson_source   — GeoJSON в целевой СК (обязателен для оформления);
        markers          — рисовать маркеры (залитые круги);
        marker_diameter  — диаметр маркера, м;
        color_field      — поле для цвета маркеров (категориальная палитра);
        label_field      — поле подписи точки;
        label_height     — высота текста подписи, м;
        legend           — рисовать легенду с цифровыми кодами;
        xlsx             — выгрузить таблицу точек в XLSX.

    Возвращает список созданных файлов (XLSX).
    """
    created: list[str] = []
    if not options_need_features(opts):
        return created

    geojson = opts.get("geojson_source")
    if not geojson or not os.path.isfile(geojson):
        log("ВНИМАНИЕ: промежуточный GeoJSON не найден — оформление пропущено.")
        return created
    features = read_geojson_features(geojson)
    points = list(iter_points(features))

    markers_on = bool(opts.get("markers"))
    legend_on = bool(opts.get("legend"))
    xlsx_on = bool(opts.get("xlsx"))
    label_field = (opts.get("label_field") or "").strip()
    color_field = (opts.get("color_field") or "").strip()
    diameter = float(opts.get("marker_diameter") or 1.0)
    radius = max(diameter, 0.01) / 2.0
    height = float(opts.get("label_height") or DEFAULT_TEXT_HEIGHT)

    # Категории цветов: по полю, иначе одна категория "".
    if color_field:
        cats = category_colors(p[2].get(color_field) for p in points)
    else:
        cats = {"": {"code": 1, "hex": palette_color(0)}}

    # --- DXF: маркеры, подписи, легенда (ezdxf). ---
    if markers_on or legend_on or label_field:
        import ezdxf  # ленивый импорт

        doc = ezdxf.readfile(dxf_path)
        msp = doc.modelspace()
        for name in (LAYER_MARKERS, LAYER_LABELS, LAYER_LEGEND):
            if name not in doc.layers:
                doc.layers.add(name)

        # Маркеры + подписи точек.
        for x, y, props in points:
            key = "" if not color_field else props.get(color_field)
            key = "" if key is None else str(key)
            hexc = cats.get(key, {"hex": palette_color(0)})["hex"]
            rgb = hex_to_rgb(hexc)
            if markers_on:
                circle = msp.add_circle(
                    (x, y), radius,
                    dxfattribs={
                        "layer": LAYER_MARKERS,
                        "true_color": _true_color_int(rgb),
                    })
                _solid_hatch(msp, (x, y), radius, LAYER_MARKERS, rgb)
            if label_field:
                text = str(props.get(label_field) or "")
                if text:
                    t = msp.add_text(
                        text,
                        dxfattribs={
                            "layer": LAYER_LABELS,
                            "height": height,
                        },
                    )
                    # Подпись справа от маркера.
                    t.set_placement((x + radius * 1.5, y + height / 2))

        # Легенда: справа-снизу, маркеры тех же цветов + коды 1,2,3…
        if legend_on and cats:
            coords = list(iter_all_coords(features))
            anchor = legend_anchor((c[0] for c in coords),
                                   (c[1] for c in coords))
            ordered = sorted(cats.items(), key=lambda kv: kv[1]["code"])
            row_h = max(radius * 2.0, height, 1.0) * 1.6
            for i, (value, info) in enumerate(ordered):
                cy = anchor[1] + i * row_h + row_h / 2
                cx = anchor[0] + radius
                rgb = hex_to_rgb(info["hex"])
                circle = msp.add_circle(
                    (cx, cy), radius,
                    dxfattribs={
                        "layer": LAYER_LEGEND,
                        "true_color": _true_color_int(rgb),
                    })
                _solid_hatch(msp, (cx, cy), radius, LAYER_LEGEND, rgb)
                t = msp.add_text(
                    str(info["code"]),
                    dxfattribs={"layer": LAYER_LEGEND, "height": height},
                )
                t.set_placement((anchor[0] + radius * 2.0 + height * 0.5, cy))

        doc.saveas(dxf_path)
        log(f"Оформление добавлено в DXF: {dxf_path}")

    # --- XLSX: листы points и legend (openpyxl). ---
    if xlsx_on:
        created.append(write_xlsx(points, cats, dxf_path, out_dir, log=log))

    return created


def write_xlsx(points: list[tuple[float, float, dict]],
               cats: dict, dxf_path: str, out_dir: str,
               log: Callable = print) -> str:
    """Выгрузить таблицу точек и легенду в XLSX (openpyxl).

    Лист points: все атрибуты точек + пересчитанные координаты X, Y.
    Лист legend: legend_code, original_value, hex_color, aci_color.
    Возвращает путь к созданному файлу.
    """
    from openpyxl import Workbook  # ленивый импорт

    wb = Workbook()
    ws = wb.active
    ws.title = "points"

    columns: list[str] = []
    for _, _, props in points:
        for k in props:
            if k not in columns:
                columns.append(k)
    header = columns + ["X", "Y"]
    ws.append(header)
    for x, y, props in points:
        ws.append([props.get(c) for c in columns] + [x, y])

    ws2 = wb.create_sheet("legend")
    ws2.append(["legend_code", "original_value", "hex_color", "aci_color"])
    for value, info in sorted(cats.items(), key=lambda kv: kv[1]["code"]):
        ws2.append([
            info["code"], value, info["hex"].upper(),
            rgb_to_aci(hex_to_rgb(info["hex"])),
        ])

    base = os.path.splitext(os.path.basename(dxf_path))[0]
    xlsx_path = os.path.join(out_dir, base + ".xlsx")
    wb.save(xlsx_path)
    log(f"XLSX выгружен: {xlsx_path}")
    return xlsx_path
