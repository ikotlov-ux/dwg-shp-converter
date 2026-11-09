"""Ядро конвертации: ogr2ogr и ODA File Converter через subprocess.

Правила портирования из R-скрипта:
- ogr2ogr вызывается списком аргументов (каждый аргумент — отдельный
  элемент списка), поэтому пути с пробелами и кириллицей безопасны;
- DWG на входе: сначала ODA File Converter (DWG -> DXF), затем ogr2ogr;
- DWG на выходе: ogr2ogr (DXF) -> ODA File Converter (DXF -> DWG, ACAD2018);
- ODA вызывается с каталогами: <вход> <выход> ACAD2018 <формат> 0 1 <маска>,
  как в R-скрипте (recurse=0, audit=1);
- перед вызовом ODA входной файл копируется во временный каталог под
  ASCII-именем (ODA ненадёжен с кириллицей в именах).
"""

from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys

# Версия DWG, в которую ODA конвертирует DXF (как в R-скрипте).
ODA_VERSION = "ACAD2018"

# Таймаут ODA в секундах (как в R-скрипте).
ODA_TIMEOUT = 300

# Типичные места установки ODA File Converter.
ODA_DEFAULT_PATH = "C:/Program Files/ODA/ODAFileConverter/ODAFileConverter.exe"
ODA_GLOBS = (
    "C:/Program Files/ODA/ODAFileConverter*/ODAFileConverter.exe",
    "C:/Program Files/ODA/ODAFileConverter*/*.exe",
)

# Формат -> (ключ драйвера GDAL, расширение выходного файла).
OUTPUT_DRIVERS = {
    "SHP": ("ESRI Shapefile", ".shp"),
    "GeoJSON": ("GeoJSON", ".geojson"),
    "GPKG": ("GPKG", ".gpkg"),
    "DXF": ("DXF", ".dxf"),
    "DWG": ("DXF", ".dxf"),  # DWG получается из DXF через ODA
}


def is_windows() -> bool:
    """True, если работаем под Windows."""
    return sys.platform.startswith("win")


def _version_score(path: str) -> int:
    """Числовая оценка версии из пути ('3.42.0' -> чем больше, тем новее)."""
    m = re.search(r"(\d+(?:\.\d+)+)", path)
    if not m:
        return 0
    comps = [int(p) for p in m.group(1).split(".") if p.isdigit()][:4]
    comps += [0] * (4 - len(comps))
    return sum(c * f for c, f in zip(comps, (10 ** 9, 10 ** 6, 10 ** 3, 1)))


def find_ogr2ogr() -> str | None:
    """Найти ogr2ogr: типичные пути QGIS/OSGeo4W, затем PATH.

    Возвращается полный путь либо None. Несколько найденных версий
    сортируются по убыванию номера версии (как в R-скрипте).
    """
    candidates: list[str] = []
    if is_windows():
        patterns = (
            "C:/Program Files/QGIS*/bin/ogr2ogr.exe",
            "C:/Program Files/QGIS*/apps/gdal/bin/ogr2ogr.exe",
            "C:/Program Files (x86)/QGIS*/bin/ogr2ogr.exe",
            "C:/Program Files (x86)/QGIS*/apps/gdal/bin/ogr2ogr.exe",
            "C:/OSGeo4W*/bin/ogr2ogr.exe",
            "C:/OSGeo4W*/apps/gdal*/bin/ogr2ogr.exe",
            "C:/Program Files/GDAL/ogr2ogr.exe",
            "C:/Program Files/QGIS*/apps/Python*/Scripts/ogr2ogr.exe",
        )
        for pattern in patterns:
            candidates.extend(p for p in glob.glob(pattern) if os.path.isfile(p))
        candidates = list(dict.fromkeys(candidates))
        candidates.sort(key=_version_score, reverse=True)
    if candidates:
        return candidates[0]
    which = shutil.which("ogr2ogr")
    return which or None


def resolve_ogr2ogr(configured: str = "") -> str | None:
    """Разрешить путь к ogr2ogr: настроенный пользователем или авто-поиск.

    Возвращает путь к исполняемому файлу либо None, если не найден.
    """
    if configured and configured != "ogr2ogr" and os.path.isfile(configured):
        return configured
    return find_ogr2ogr()


def find_oda(configured: str = "") -> str | None:
    """Найти ODA File Converter: настроенный путь, типичные пути, PATH."""
    if configured and os.path.isfile(configured):
        return configured
    if os.path.isfile(ODA_DEFAULT_PATH):
        return ODA_DEFAULT_PATH
    for pattern in ODA_GLOBS:
        hits = [p for p in glob.glob(pattern) if os.path.isfile(p)]
        if hits:
            hits.sort(key=_version_score, reverse=True)
            return hits[0]
    return shutil.which("ODAFileConverter")


def run_command(cmd: list[str], log=print, timeout: int | None = None,
                cwd: str | None = None) -> int:
    """Выполнить команду списком аргументов, вернуть код возврата.

    Каждый аргумент передаётся отдельным элементом списка — это ключевое
    требование (никаких склеенных строк с кавычками).
    """
    log("$ " + subprocess.list2cmdline(cmd))
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            cwd=cwd,
        )
    except FileNotFoundError:
        log(f"ОШИБКА: исполняемый файл не найден: {cmd[0]}")
        return 127
    except subprocess.TimeoutExpired:
        log(f"ОШИБКА: превышено время ожидания ({timeout} с): {cmd[0]}")
        return 124
    if proc.stdout:
        log(proc.stdout.rstrip())
    return proc.returncode


def ensure_gdal_env(ogr2ogr_exe: str | None, env: dict | None = None) -> dict:
    """Собрать переменные окружения с GDAL_DATA/PROJ_LIB для ogr2ogr.

    Ищет share/gdal и share/proj рядом с ogr2ogr (как ensure_gdal_env
    в R-скрипте). Возвращает словарь окружения для subprocess.
    """
    env = dict(env if env is not None else os.environ)
    if not ogr2ogr_exe or not os.path.isfile(ogr2ogr_exe):
        return env

    root = os.path.dirname(os.path.dirname(os.path.abspath(ogr2ogr_exe)))
    roots = [root]
    if os.path.basename(root).lower() == "gdal":
        roots.append(os.path.dirname(root))

    if not env.get("GDAL_DATA") or not os.path.isfile(
        os.path.join(env["GDAL_DATA"], "header.dxf")
    ):
        for r in roots + [os.path.dirname(r) for r in roots]:
            cand = os.path.join(r, "share", "gdal")
            if os.path.isdir(cand) and os.path.isfile(os.path.join(cand, "header.dxf")):
                env["GDAL_DATA"] = cand
                break

    if not env.get("PROJ_LIB") or not os.path.isfile(
        os.path.join(env["PROJ_LIB"], "proj.db")
    ):
        for r in roots + [os.path.dirname(r) for r in roots]:
            cand = os.path.join(r, "share", "proj")
            if os.path.isdir(cand) and os.path.isfile(os.path.join(cand, "proj.db")):
                env["PROJ_LIB"] = cand
                break
    return env


def run_ogr2ogr(ogr2ogr_exe: str | None, args: list[str], log=print) -> int:
    """Вызвать ogr2ogr со списком аргументов и готовым окружением GDAL."""
    if not ogr2ogr_exe:
        log("ОШИБКА: ogr2ogr не найден. Установите QGIS/OSGeo4W или укажите путь в настройках.")
        return 127
    env = ensure_gdal_env(ogr2ogr_exe)
    log("$ " + subprocess.list2cmdline([ogr2ogr_exe] + args))
    try:
        proc = subprocess.run(
            [ogr2ogr_exe] + args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
        )
    except FileNotFoundError:
        log(f"ОШИБКА: ogr2ogr не найден по пути: {ogr2ogr_exe}")
        return 127
    if proc.stdout:
        log(proc.stdout.rstrip())
    return proc.returncode


# ---------------------------------------------------------------------------
# ODA File Converter
# ---------------------------------------------------------------------------

def _ascii_copy(src: str, work_dir: str, suffix: str) -> str:
    """Скопировать файл во временный каталог под ASCII-именем.

    ODA File Converter ненадёжен с кириллицей в путях (см. R-скрипт).
    """
    os.makedirs(work_dir, exist_ok=True)
    dst = os.path.join(work_dir, f"input_{os.getpid()}{suffix}")
    shutil.copy2(src, dst)
    return dst


def oda_convert(oda_exe: str | None, src_dir: str, dst_dir: str,
                out_format: str, mask: str, log=print,
                timeout: int = ODA_TIMEOUT) -> tuple[int, list[str]]:
    """Вызвать ODA File Converter: конвертация всех файлов по маске.

    Аргументы ODA (как в R-скрипте):
        <входной каталог> <выходной каталог> ACAD2018 <DXF|DWG> 0 1 <маска>
    Возвращает (код возврата, список созданных файлов).
    """
    if not oda_exe or not os.path.isfile(oda_exe):
        log(f"ОШИБКА: ODA File Converter не найден: {oda_exe}")
        return 127, []
    os.makedirs(dst_dir, exist_ok=True)
    args = [oda_exe, src_dir, dst_dir, ODA_VERSION, out_format, "0", "1", mask]
    code = run_command(args, log=log, timeout=timeout)
    ext = ".dxf" if out_format == "DXF" else ".dwg"
    created = sorted(
        f for f in os.listdir(dst_dir)
        if f.lower().endswith(ext)
    )
    return code, [os.path.join(dst_dir, f) for f in created]


def dwg_to_dxf(oda_exe: str | None, dwg_file: str, work_dir: str,
               log=print) -> str | None:
    """DWG -> DXF через ODA File Converter.

    Возвращает путь к DXF либо None при ошибке. Вход копируется под
    ASCII-именем в подкаталог dwg/, результат ждём в подкаталоге dxf/.
    """
    if not oda_exe or not os.path.isfile(oda_exe):
        log(
            "ОШИБКА: ODA File Converter не найден.\n"
            "Для чтения .dwg установите ODA File Converter и укажите путь "
            "в настройках (по умолчанию " + ODA_DEFAULT_PATH + ")."
        )
        return None
    dwg_dir = os.path.join(work_dir, "dwg")
    dxf_dir = os.path.join(work_dir, "dxf")
    os.makedirs(dxf_dir, exist_ok=True)
    dwg_copy = _ascii_copy(dwg_file, dwg_dir, ".dwg")
    log(f"Шаг 1: DWG -> DXF (ODA), временная копия: {dwg_copy}")
    code, created = oda_convert(oda_exe, dwg_dir, dxf_dir, "DXF", "*.dwg", log=log)
    if code != 0 or not created:
        log("ОШИБКА: ODA File Converter не создал DXF (см. вывод выше).")
        return None
    dxf = created[0]
    log(f"DXF создан: {dxf}")
    return dxf


def dxf_to_dwg(oda_exe: str | None, dxf_file: str, work_dir: str,
               log=print) -> str | None:
    """DXF -> DWG (ACAD2018) через ODA File Converter.

    Возвращает путь к созданному DWG (совпадающему по имени с dxf_file)
    либо None при ошибке.
    """
    dwg_dir = os.path.join(work_dir, "dwg")
    dxf_dir = os.path.join(work_dir, "dxf")
    os.makedirs(dwg_dir, exist_ok=True)
    code, created = oda_convert(oda_exe, dxf_dir, dwg_dir, "DWG", "*.dxf", log=log)
    if code != 0 or not created:
        log("ОШИБКА: ODA File Converter не создал DWG (см. вывод выше).")
        return None
    want = os.path.splitext(os.path.basename(dxf_file))[0].lower()
    dwg = next(
        (f for f in created if os.path.splitext(os.path.basename(f))[0].lower() == want),
        created[0],
    )
    log(f"DWG создан: {dwg}")
    return dwg


# ---------------------------------------------------------------------------
# Основная конвертация
# ---------------------------------------------------------------------------

def _srs_args(s_srs: str | None, t_srs: str | None) -> list[str]:
    """Аргументы -s_srs/-t_srs; каждый аргумент — отдельный элемент списка."""
    args: list[str] = []
    if s_srs and t_srs:
        args += ["-s_srs", s_srs, "-t_srs", t_srs]
    elif t_srs:
        # Без исходной СК — только назначаем целевую (без перепроецирования).
        args += ["-a_srs", t_srs]
    return args


def ogr_convert(ogr2ogr_exe: str | None, src: str, dst: str, out_format: str,
                s_srs: str | None = None, t_srs: str | None = None,
                log=print, extra_args: list[str] | None = None) -> int:
    """Конвертация векторного файла через ogr2ogr.

    out_format — один из ключей OUTPUT_DRIVERS (SHP/GeoJSON/GPKG/DXF).
    """
    driver, _ = OUTPUT_DRIVERS[out_format]
    args = ["-f", driver]
    args += _srs_args(s_srs, t_srs)
    if extra_args:
        args += extra_args
    if out_format == "DXF":
        args += ["-dim", "XY"]
    args += ["-skipfailures", dst, src]
    code = run_ogr2ogr(ogr2ogr_exe, args, log=log)
    if code != 0:
        log(f"ОШИБКА: ogr2ogr завершился с кодом {code}.")
    elif not os.path.isfile(dst):
        log(f"ОШИБКА: выходной файл не создан: {dst}")
        code = 1
    return code


def convert_one_file(
    src: str,
    out_format: str,
    out_dir: str,
    s_srs: str | None = None,
    t_srs: str | None = None,
    ogr2ogr_exe: str | None = None,
    oda_exe: str | None = None,
    log=print,
    feature_options: dict | None = None,
) -> list[str]:
    """Конвертировать один файл в выбранный формат.

    Возвращает список созданных файлов. Логика:
      - .dwg на входе -> сначала DWG->DXF (ODA), затем DXF как вектор;
      - вектор -> SHP/GeoJSON/GPKG/DXF: ogr2ogr с -s_srs/-t_srs;
      - вектор -> DWG: ogr2ogr (DXF) -> ODA (DXF->DWG); при отсутствии ODA
        сохраняется DXF с понятным сообщением.

    feature_options — настройки «вектор -> DWG» (см. features.apply_dwg_features):
      split_field, label_field, label_height, marker_diameter,
      color_field, legend, xlsx.
    """
    from . import features  # ленивый импорт (ezdxf/openpyxl внутри)

    results: list[str] = []
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(src))[0]
    ext_in = os.path.splitext(src)[1].lower()
    work_dir = os.path.join(out_dir, "_work", base)
    os.makedirs(work_dir, exist_ok=True)

    # DWG на входе: сначала в DXF через ODA.
    vector_src = src
    if ext_in == ".dwg":
        dxf = dwg_to_dxf(oda_exe, src, work_dir, log=log)
        if not dxf:
            log("Пропуск файла: не удалось получить DXF из DWG.")
            return results
        vector_src = dxf

    driver, out_ext = OUTPUT_DRIVERS[out_format]

    if out_format in ("SHP", "GeoJSON", "GPKG", "DXF"):
        dst = os.path.join(out_dir, base + out_ext)
        # ESRI Shapefile не допускает точку в имени слоя.
        layer_name = base.replace(".", "_")
        extra = ["-nln", layer_name] if out_format == "SHP" else None
        code = ogr_convert(ogr2ogr_exe, vector_src, dst, out_format,
                           s_srs, t_srs, log=log, extra_args=extra)
        if code == 0:
            results.append(dst)
            # Для DXF можно добавить маркеры/подписи/легенду.
            if out_format == "DXF" and feature_options:
                enriched = features.apply_dwg_features(
                    dst, feature_options, out_dir, log=log)
                results.extend(enriched)
        return results

    # --- Выходной формат DWG: сначала DXF, затем ODA (DXF -> DWG). ---
    dxf_dir = os.path.join(work_dir, "dxf")
    os.makedirs(dxf_dir, exist_ok=True)

    # Подготовка промежуточных GeoJSON в целевой СК (для маркеров/подписей/
    # легенды/XLSX и разбивки по полю).
    opts = dict(feature_options or {})
    need_features = bool(opts.get("split_field")) or features.options_need_features(opts)

    subsets: list[tuple[str, str]] = []  # (имя части, geojson или исходник)
    if need_features:
        # Перепроецированный GeoJSON со всеми атрибутами.
        gj = os.path.join(work_dir, "reprojected.geojson")
        code = ogr_convert(ogr2ogr_exe, vector_src, gj, "GeoJSON",
                           s_srs, t_srs, log=log)
        if code != 0:
            log("ОШИБКА: не удалось подготовить промежуточный GeoJSON.")
            return results
        subsets = features.split_geojson_by_field(
            gj, work_dir, opts.get("split_field") or "")
        if not subsets:
            subsets = [("", gj)]
    else:
        subsets = [("", vector_src)]

    oda_available = bool(oda_exe and os.path.isfile(oda_exe))
    if not oda_available:
        log(
            "ВНИМАНИЕ: ODA File Converter не найден — DWG создать нельзя.\n"
            "Файлы будут сохранены в DXF (открывается в AutoCAD и его "
            "клонах). Установите ODA и укажите путь в настройках."
        )

    for part_name, part_src in subsets:
        suffix = f"_{part_name}" if part_name else ""
        part_base = (base + suffix).replace(".", "_") or "layer"
        dxf_file = os.path.join(dxf_dir, part_base + ".dxf")
        # Если part_src — уже перепроецированный GeoJSON, СК не нужны;
        # иначе (исходный файл) передаём -s_srs/-t_srs.
        part_s, part_t = (None, None) if need_features else (s_srs, t_srs)
        code = ogr_convert(ogr2ogr_exe, part_src, dxf_file, "DXF",
                           s_srs=part_s, t_srs=part_t, log=log)
        if code != 0:
            continue
        if need_features:
            part_opts = dict(opts)
            part_opts["geojson_source"] = part_src
            try:
                features.apply_dwg_features(dxf_file, part_opts, out_dir, log=log)
            except Exception as exc:  # оформление не должно ломать конвертацию
                log(f"ВНИМАНИЕ: оформление DWG не применено: {exc}")

        if oda_available:
            dwg = dxf_to_dwg(oda_exe, dxf_file, work_dir, log=log)
            if dwg:
                final = os.path.join(out_dir, part_base + ".dwg")
                shutil.copy2(dwg, final)
                log(f"Готово: {final}")
                results.append(final)
            else:
                results.append(dxf_file)
                log(f"Сохранён DXF (ODA не смог создать DWG): {dxf_file}")
        else:
            final_dxf = os.path.join(out_dir, part_base + ".dxf")
            shutil.copy2(dxf_file, final_dxf)
            results.append(final_dxf)
            log(f"Сохранён DXF вместо DWG: {part_base}.dxf")

    return results
