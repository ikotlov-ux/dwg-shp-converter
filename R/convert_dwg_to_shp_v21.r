# Convert AutoCAD DWG to ESRI Shapefile from R and back
#
# Version: v21
#   - NEW: added "МСК-11 Печора DWG / поправка -2220 м по северу" CRS preset, a
#     northing-corrected variant of the Pechora DWG CRS. Converted DWG output was
#     ~2220 m too far north, so the false northing is increased by 2220 m
#     (y_0 = -13316.25396557 + 2220 = -11096.25396557), shifting results south.
#       * PROJ string:
#         +proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 +x_0=5400000
#         +y_0=-11096.25396557 +ellps=krass
#         +towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs
#       * The existing "full northing" DWG preset (y0=-13316.254) is kept.
#   - From v20: FIX: the generated QGIS .qgs project now always carries an explicit, valid
#     project CRS *and* per-layer CRS matching the selected output (target) CRS, so
#     converted vectors no longer shift when the output CRS is a custom MSK/PROJ
#     projection. Previously a custom CRS produced only <wkt>/<proj4> with no
#     <authid>/<srsid>/<geographicflag>, which QGIS 3 could not register as a CRS.
#       * <spatialrefsys> now includes wkt, proj4, srsid, srid, authid,
#         description, projectionacronym, ellipsoidacronym and geographicflag.
#       * Custom (non-EPSG) CRS get authid USER:100000 / srsid 100000 so QGIS
#         loads them as a user CRS; EPSG CRS keep their real authid/srid.
#       * WKT/proj4 obtained via gdalsrsinfo against the resolved target CRS;
#         fallback to the spec's own PROJ string, and to EPSG:4326 only when the
#         target CRS is null (never silently for a selected custom CRS).
#       * Each produced shapefile is ensured to have a matching .prj (backfilled
#         from the target WKT when ogr2ogr did not write one).
#       * Console prints the QGIS project CRS authid + label + path.
#   - From v19: added "МСК-11 Печора DWG / full northing" CRS preset, calibrated to the
#     Yandex control point for the uploaded DWG-derived shapefiles. Same as the
#     Pechora table variant but with y_0=-13316.25396557 (instead of -6211057.628).
#       * PROJ string:
#         +proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 +x_0=5400000
#         +y_0=-13316.25396557 +ellps=krass
#         +towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs
#       * Use this for DWG-derived SHP that otherwise lands at the wrong WGS84
#         extent; recovers control point 64.820299 N, 57.109080 E.
#       * All prior presets (standard zone 5, Pechora table variant, MGGT) kept.
#   - From v18: added "МСК-11 Печорский вариант" Pechora CRS preset (control-point based)
#     to the interactive CRS chooser, available as source and target in both
#     directions. It is NOT the standard TerraGIS zone 5: it uses the zone-6 central
#     meridian (lon_0=56.03333333333) with the zone-5 false easting (x_0=5400000).
#       * PROJ string (Krassovsky ellipsoid + GOST 51794-2008 datum transform):
#         +proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 +x_0=5400000
#         +y_0=-6211057.628 +ellps=krass
#         +towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs
#       * Standard "МСК-11 зона 5 / Республика Коми" preset is kept unchanged.
#   - From v17: added "МСК-11 зона 5 / Республика Коми" (MSK-11 zone 5) CRS preset to the
#     interactive CRS chooser, available as a source and target CRS in both directions.
#       * PROJ string (Krassovsky ellipsoid + GOST 51794-2008 datum transform):
#         +proj=tmerc +lat_0=0 +lon_0=53.03333333333 +k=1 +x_0=5400000
#         +y_0=-6211057.628 +ellps=krass
#         +towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs
#       * Existing MGGT Moscow preset is preserved unchanged.
#   - From v16: DWG -> SHP also writes KML files for Organic Maps into the same output
#     folder as the shapefiles / QGIS project.
#       * KML is always EPSG:4326 (WGS84 lon/lat), as Organic Maps requires, no
#         matter which output CRS was chosen for the shapefiles.
#       * One KML per produced geometry layer (<prefix>_points.kml,
#         <prefix>_lines.kml, <prefix>_polygons.kml); plus a combined
#         <prefix>_organic_maps.kml when the GDAL LIBKML driver is available.
#       * Placemark name = Text if present, else Layer, else feature id;
#         Layer/Text kept as attributes; simple colors carried via the OGR style
#         string when the KML driver supports it.
#       * Empty / missing geometry layers are skipped with a message.
#
# Inherited from v15:
#   - DWG -> SHP also writes a QGIS project (.qgs, uncompressed) into the
#     output folder, referencing the created points/lines/polygons shapefiles.
#       * Layers are kept GEOMETRY-based (points/lines/polygons) -- they are NOT
#         split by original CAD layers.
#       * WITHIN each geometry layer the features are categorized/styled by the
#         CAD "Layer" attribute and by colors resolved from the OGR style string
#         (exported as a "Style" DBF field): line color/width/dash, point marker
#         colors, polygon fill (with transparency) + outline; labels from "Text".
#       * Colors come from the resolved RGB in the OGR style; if unavailable a
#         deterministic per-layer palette is used (with an ACI 1-7 fallback).
#       * Sidecar .qml files are also written next to each shapefile.
#
# Inherited from v14:
#   - Interactive SOURCE and TARGET CRS selection in both directions.
#   - ogr2ogr reprojection using the selected -s_srs / -t_srs.
#   - MGGT Moscow uses towgs84 DISABLED by default.
#
# Inherited from v13:
#   - Robust auto-detection of ogr2ogr.exe on Windows (QGIS / OSGeo4W / PATH).
#   - Automatic GDAL_DATA and PROJ_LIB detection.
#   - Paths with spaces / Cyrillic handled via quoting + ASCII temp names.
#
# Workflows:
#   - DWG -> DXF via ODA File Converter -> SHP via GDAL/ogr2ogr -> QGIS .qgs + KML
#   - SHP -> DXF via GDAL/ogr2ogr -> DWG via ODA File Converter
#
# Load without starting the menu:
#   options(convert_dwg_to_shp.autorun = FALSE)
#   source("convert_dwg_to_shp_v16.r")

.CONVERT_DWG_VERSION <- "v21"

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (is.character(a) && !nzchar(a[1])) return(b)
  a
}

.convert_dwg_script_dir <- local({
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    script_file <- sub("^--file=", "", file_arg[1])
    if (!identical(script_file, "-") && file.exists(script_file)) {
      return(dirname(normalizePath(script_file, winslash = "/", mustWork = TRUE)))
    }
  }

  frame_files <- vapply(
    sys.frames(),
    function(x) {
      if (!is.null(x$ofile)) {
        x$ofile
      } else {
        NA_character_
      }
    },
    character(1)
  )
  frame_files <- frame_files[!is.na(frame_files)]
  if (length(frame_files) > 0) {
    return(dirname(normalizePath(frame_files[length(frame_files)], winslash = "/", mustWork = TRUE)))
  }

  normalizePath(getwd(), winslash = "/", mustWork = TRUE)
})

# ---------------------------------------------------------------------------
# ogr2ogr / GDAL environment auto-detection (from v13)
# ---------------------------------------------------------------------------

# Turn a path such as "C:/Program Files/QGIS 3.42.0/bin/ogr2ogr.exe" into a
# single sortable number based on its version (3.42.0 -> larger is newer).
.version_score <- function(path) {
  mm <- regmatches(path, regexpr("[0-9]+(\\.[0-9]+)+", path))
  if (length(mm) == 0) return(0)
  comps <- suppressWarnings(as.integer(strsplit(mm, ".", fixed = TRUE)[[1]]))
  comps <- comps[!is.na(comps)]
  comps <- c(comps, rep(0L, max(0, 4 - length(comps))))[1:4]
  sum(comps * c(1e9, 1e6, 1e3, 1))
}

# Find ogr2ogr executable. On Windows search common QGIS/OSGeo4W locations and
# PATH; prefer the highest version when several are present.
find_ogr2ogr <- function(verbose = TRUE) {
  candidates <- character(0)

  if (.Platform$OS.type == "windows") {
    globs <- c(
      "C:/Program Files/QGIS*/bin/ogr2ogr.exe",
      "C:/Program Files/QGIS*/apps/gdal/bin/ogr2ogr.exe",
      "C:/Program Files (x86)/QGIS*/bin/ogr2ogr.exe",
      "C:/Program Files (x86)/QGIS*/apps/gdal/bin/ogr2ogr.exe",
      "C:/OSGeo4W*/bin/ogr2ogr.exe",
      "C:/OSGeo4W*/apps/gdal*/bin/ogr2ogr.exe",
      "C:/Program Files/GDAL/ogr2ogr.exe",
      "C:/Program Files/QGIS*/apps/Python*/Scripts/ogr2ogr.exe"
    )
    for (g in globs) {
      hits <- suppressWarnings(Sys.glob(g))
      if (length(hits) > 0) candidates <- c(candidates, hits)
    }
    candidates <- candidates[file.exists(candidates)]
    candidates <- unique(normalizePath(candidates, winslash = "/", mustWork = FALSE))

    if (length(candidates) > 1) {
      scores <- vapply(candidates, .version_score, numeric(1))
      candidates <- candidates[order(scores, decreasing = TRUE)]
    }
  }

  if (length(candidates) > 0) {
    if (verbose) message("Auto-detected ogr2ogr: ", candidates[1])
    return(candidates[1])
  }

  on_path <- Sys.which("ogr2ogr")
  if (nzchar(on_path)) {
    if (verbose) message("Using ogr2ogr from PATH: ", on_path)
    return(normalizePath(on_path, winslash = "/", mustWork = FALSE))
  }

  "ogr2ogr"
}

# Resolve a user-supplied ogr2ogr path. If it does not exist, fall back to
# auto-detection. Stops with a helpful message only when nothing is found.
resolve_ogr2ogr <- function(ogr2ogr_exe) {
  if (!is.null(ogr2ogr_exe) && nzchar(ogr2ogr_exe) &&
      !identical(ogr2ogr_exe, "ogr2ogr") && file.exists(ogr2ogr_exe)) {
    return(normalizePath(ogr2ogr_exe, winslash = "/", mustWork = FALSE))
  }

  if (identical(ogr2ogr_exe, "ogr2ogr") && nzchar(Sys.which("ogr2ogr"))) {
    return(normalizePath(Sys.which("ogr2ogr"), winslash = "/", mustWork = FALSE))
  }

  if (!is.null(ogr2ogr_exe) && nzchar(ogr2ogr_exe) && !identical(ogr2ogr_exe, "ogr2ogr")) {
    message("Configured ogr2ogr not found: ", ogr2ogr_exe)
    message("Trying to auto-detect ogr2ogr instead ...")
  }

  found <- find_ogr2ogr(verbose = TRUE)

  if (identical(found, "ogr2ogr") && !nzchar(Sys.which("ogr2ogr"))) {
    stop(
      "ogr2ogr.exe was not found.\n",
      "Searched common QGIS / OSGeo4W locations and PATH.\n",
      "Install QGIS or OSGeo4W, or pass the full path explicitly, e.g.:\n",
      "  convert_dwg_from_menu(ogr2ogr_exe = 'C:/Program Files/QGIS 3.40.0/bin/ogr2ogr.exe')\n",
      "  convert_dwg_from_menu(ogr2ogr_exe = 'C:/OSGeo4W/bin/ogr2ogr.exe')"
    )
  }

  found
}

# Locate a sibling GDAL tool (e.g. ogrinfo) next to ogr2ogr, or on PATH.
.sibling_exe <- function(ogr2ogr_exe, name = "ogrinfo") {
  if (is.null(ogr2ogr_exe) || identical(ogr2ogr_exe, "ogr2ogr") || !nzchar(ogr2ogr_exe)) {
    w <- Sys.which(name)
    return(if (nzchar(w)) unname(w) else "")
  }
  d <- dirname(ogr2ogr_exe)
  ext <- if (.Platform$OS.type == "windows") ".exe" else ""
  exe <- file.path(d, paste0(name, ext))
  if (file.exists(exe)) return(normalizePath(exe, winslash = "/", mustWork = FALSE))
  w <- Sys.which(name)
  if (nzchar(w)) return(unname(w))
  ""
}

# Determine the install root for a given ogr2ogr executable.
.ogr_install_roots <- function(ogr2ogr_exe) {
  exe_path <- ogr2ogr_exe
  if (identical(exe_path, "ogr2ogr") || !nzchar(exe_path)) {
    exe_path <- Sys.which("ogr2ogr")
  }
  if (!nzchar(exe_path)) {
    return(character(0))
  }
  exe_path <- normalizePath(exe_path, winslash = "/", mustWork = FALSE)
  exe_dir <- dirname(exe_path)          # .../bin
  root1 <- dirname(exe_dir)             # .../<root> or .../apps/gdal
  root2 <- dirname(dirname(root1))      # for .../apps/gdal/bin -> .../<root>
  unique(c(root1, root2, exe_dir))
}

# Set GDAL_DATA and PROJ_LIB if not already valid, based on the selected root.
ensure_gdal_env <- function(ogr2ogr_exe = "ogr2ogr") {
  roots <- .ogr_install_roots(ogr2ogr_exe)

  # --- GDAL_DATA ---
  current_gdal_data <- Sys.getenv("GDAL_DATA", unset = "")
  gdal_ok <- nzchar(current_gdal_data) && dir.exists(current_gdal_data) &&
    file.exists(file.path(current_gdal_data, "header.dxf"))

  if (!gdal_ok) {
    gdal_candidates <- character(0)
    for (r in roots) {
      gdal_candidates <- c(
        gdal_candidates,
        file.path(r, "share", "gdal"),
        file.path(r, "apps", "gdal", "share", "gdal"),
        file.path(dirname(r), "share", "gdal")
      )
    }
    gdal_candidates <- c(
      gdal_candidates,
      Sys.glob("C:/Program Files/QGIS*/share/gdal"),
      Sys.glob("C:/Program Files/QGIS*/apps/gdal/share/gdal"),
      Sys.glob("C:/OSGeo4W*/share/gdal"),
      Sys.glob("C:/OSGeo4W*/apps/gdal*/share/gdal")
    )
    gdal_candidates <- unique(normalizePath(gdal_candidates, winslash = "/", mustWork = FALSE))
    gdal_candidates <- gdal_candidates[dir.exists(gdal_candidates)]
    with_header <- gdal_candidates[file.exists(file.path(gdal_candidates, "header.dxf"))]
    chosen <- if (length(with_header) > 0) with_header[1] else if (length(gdal_candidates) > 0) gdal_candidates[1] else NA_character_

    if (!is.na(chosen)) {
      Sys.setenv(GDAL_DATA = chosen)
      message("GDAL_DATA set to: ", chosen)
    } else {
      warning(
        "GDAL_DATA was not found automatically. DXF export may fail with ",
        "'Cannot find header.dxf'. Set it manually, e.g.:\n",
        "  Sys.setenv(GDAL_DATA = 'C:/Program Files/QGIS 3.40.0/share/gdal')"
      )
    }
  }

  # --- PROJ_LIB (needed for proj.db / coordinate transforms) ---
  current_proj <- Sys.getenv("PROJ_LIB", unset = "")
  proj_ok <- nzchar(current_proj) && dir.exists(current_proj) &&
    file.exists(file.path(current_proj, "proj.db"))

  if (!proj_ok) {
    proj_candidates <- character(0)
    for (r in roots) {
      proj_candidates <- c(
        proj_candidates,
        file.path(r, "share", "proj"),
        file.path(r, "apps", "proj", "share", "proj"),
        file.path(r, "apps", "proj*", "share", "proj"),
        file.path(dirname(r), "share", "proj")
      )
    }
    proj_candidates <- c(
      proj_candidates,
      Sys.glob("C:/Program Files/QGIS*/share/proj"),
      Sys.glob("C:/Program Files/QGIS*/apps/proj*/share/proj"),
      Sys.glob("C:/OSGeo4W*/share/proj"),
      Sys.glob("C:/OSGeo4W*/apps/proj*/share/proj")
    )
    proj_candidates <- unlist(lapply(proj_candidates, function(p) {
      if (grepl("[*?]", p)) suppressWarnings(Sys.glob(p)) else p
    }))
    proj_candidates <- unique(normalizePath(proj_candidates, winslash = "/", mustWork = FALSE))
    proj_candidates <- proj_candidates[dir.exists(proj_candidates)]
    with_db <- proj_candidates[file.exists(file.path(proj_candidates, "proj.db"))]
    chosen <- if (length(with_db) > 0) with_db[1] else if (length(proj_candidates) > 0) proj_candidates[1] else NA_character_

    if (!is.na(chosen)) {
      Sys.setenv(PROJ_LIB = chosen)
      message("PROJ_LIB set to: ", chosen)
    } else {
      warning(
        "PROJ_LIB / proj.db was not found automatically. Coordinate ",
        "transformations may fail. Set it manually, e.g.:\n",
        "  Sys.setenv(PROJ_LIB = 'C:/Program Files/QGIS 3.40.0/share/proj')"
      )
    }
  }

  invisible(list(
    GDAL_DATA = Sys.getenv("GDAL_DATA", unset = ""),
    PROJ_LIB  = Sys.getenv("PROJ_LIB",  unset = "")
  ))
}

# Backwards-compatible alias used by older call sites.
ensure_gdal_data <- function(ogr2ogr_exe = "ogr2ogr") {
  ensure_gdal_env(ogr2ogr_exe)
}

# ---------------------------------------------------------------------------
# CRS specification + selection (from v14)
# ---------------------------------------------------------------------------
#
# A "crs spec" is a list(kind, value, label, [use_towgs84]) where kind is one of:
#   "epsg"    value = "EPSG:4326"            (or any GDAL authority string)
#   "proj"    value = "+proj=... " or raw    (passed verbatim to GDAL)
#   "prjfile" value = path to a .prj file    (WKT read by GDAL)
#   "wkt"     value = path to a .wkt file
#   "mggt"    value = "MGGT_Moscow_custom"   (materialized to a .prj at runtime)

crs_epsg <- function(code, label = NULL) {
  list(kind = "epsg", value = code, label = label %||% code)
}
crs_proj <- function(s, label = NULL) {
  list(kind = "proj", value = s, label = label %||% paste0("PROJ: ", s))
}
crs_file <- function(path, label = NULL) {
  list(kind = "prjfile", value = path, label = label %||% paste0("File: ", basename(path)))
}
crs_mggt <- function(use_towgs84 = FALSE) {
  list(kind = "mggt", value = "MGGT_Moscow_custom", use_towgs84 = isTRUE(use_towgs84),
       label = paste0("MGGT Moscow local (towgs84=", isTRUE(use_towgs84), ")"))
}

# MSK-11 zone 5 (Republic of Komi). Transverse Mercator on the Krassovsky
# ellipsoid with the GOST 51794-2008 datum transform to WGS84. Parameters from
# TerraGIS (terraingis.ru/msk-11.html): central meridian 53.03333333333,
# false easting 5400000, false northing -6211057.628.
.MSK11_ZONE5_PROJ <- paste0(
  "+proj=tmerc +lat_0=0 +lon_0=53.03333333333 +k=1 ",
  "+x_0=5400000 +y_0=-6211057.628 +ellps=krass ",
  "+towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs")
crs_msk11_zone5 <- function() {
  crs_proj(.MSK11_ZONE5_PROJ, "МСК-11 зона 5 / Республика Коми (PROJ)")
}

# MSK-11 "Pechora" control-point variant. Same datum/ellipsoid and false
# easting/northing as standard zone 5, but the central meridian is the zone-6
# value (56.03333333333). Derived from the Pechora-area control point; kept as a
# separate preset alongside the standard zone 5.
.MSK11_PECHORA_PROJ <- paste0(
  "+proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 ",
  "+x_0=5400000 +y_0=-6211057.628 +ellps=krass ",
  "+towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs")
crs_msk11_pechora <- function() {
  crs_proj(.MSK11_PECHORA_PROJ, "МСК-11 Печорский вариант (lon0=56.033, x0=5400000) (PROJ)")
}

# MSK-11 Pechora variant calibrated for the uploaded DWG-derived shapefiles.
# Identical to the Pechora table variant except for the false northing
# (y_0=-13316.25396557), tuned to the Yandex control point 64.820299 N,
# 57.109080 E so DWG-derived SHP lands at the correct WGS84 extent.
.MSK11_PECHORA_DWG_PROJ <- paste0(
  "+proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 ",
  "+x_0=5400000 +y_0=-13316.25396557 +ellps=krass ",
  "+towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs")
crs_msk11_pechora_dwg <- function() {
  crs_proj(.MSK11_PECHORA_DWG_PROJ, "МСК-11 Печора DWG / full northing (y0=-13316.254) (PROJ)")
}

# Northing-corrected DWG variant: converted output was ~2220 m too far north, so
# the false northing is increased by 2220 m (y_0 = -13316.25396557 + 2220) to
# shift results south. Kept separate from the uncorrected "full northing" preset.
.MSK11_PECHORA_DWG_N2220_PROJ <- paste0(
  "+proj=tmerc +lat_0=0 +lon_0=56.03333333333 +k=1 ",
  "+x_0=5400000 +y_0=-11096.25396557 +ellps=krass ",
  "+towgs84=23.57,-140.95,-79.8,0,-0.35,-0.79,-0.22 +units=m +no_defs")
crs_msk11_pechora_dwg_n2220 <- function() {
  crs_proj(.MSK11_PECHORA_DWG_N2220_PROJ,
           "МСК-11 Печора DWG / поправка -2220 м по северу (y0=-11096.254) (PROJ)")
}

# Customer "Moscow_bessel" CRS from the DGI (ДГИ) deliverable
# (Zony_OOZT_DGI-E-114072-26.prj): Transverse Mercator on a Bessel_Moscow
# spheroid (a=6377397.0, rf=299.15), central meridian 37.5,
# lat_0=55.66666666666666, false easting/northing 0. The customer .prj carries
# NO datum shift, so this preset ADDS the known MGGT TOWGS84 transform so the
# data aligns correctly with WGS84. Kept separate from the MGGT Moscow preset
# (which uses x_0=16.098 / y_0=14.512), whose parameters stay unchanged.
.MOSCOW_BESSEL_DGI_PROJ <- paste0(
  "+proj=tmerc +lat_0=55.66666666666666 +lon_0=37.5 +k=1 ",
  "+x_0=0 +y_0=0 +a=6377397.0 +rf=299.15 ",
  "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507 +units=m +no_defs")
crs_moscow_bessel_dgi <- function() {
  crs_proj(.MOSCOW_BESSEL_DGI_PROJ, "Moscow_bessel ДГИ (x0=0, y0=0, +towgs84)")
}

# Manual-correction variant of the Moscow_bessel ДГИ CRS. A control point came
# out shifted when using the plain DGI CRS:
#   observed (DGI):  lon 37.731285, lat 55.632847
#   desired       :  lon 37.731170, lat 55.632696
# i.e. the result lands ~7.2 m east and ~16.8 m north of the true position
# (Δlon 0.000115° * cos(lat) ≈ 7.2 m, Δlat 0.000151° ≈ 16.8 m). Increasing the
# false easting/northing makes the inverse transform subtract these offsets, so
# the output is pulled south-west onto the control point. All other parameters
# match the DGI preset; only x_0/y_0 differ (0 -> 7.2 / 16.8). This is a manual
# selectable correction only and is NOT auto-detected from the customer .prj.
.MOSCOW_BESSEL_DGI_SHIFT_X <- 7.2
.MOSCOW_BESSEL_DGI_SHIFT_Y <- 16.8
.MOSCOW_BESSEL_DGI_SHIFT_PROJ <- paste0(
  "+proj=tmerc +lat_0=55.66666666666666 +lon_0=37.5 +k=1 ",
  "+x_0=", .MOSCOW_BESSEL_DGI_SHIFT_X, " +y_0=", .MOSCOW_BESSEL_DGI_SHIFT_Y, " ",
  "+a=6377397.0 +rf=299.15 ",
  "+towgs84=316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507 +units=m +no_defs")
crs_moscow_bessel_dgi_shift <- function() {
  crs_proj(
    .MOSCOW_BESSEL_DGI_SHIFT_PROJ,
    sprintf("Moscow_bessel ДГИ (смещение x=%s, y=%s)",
            .MOSCOW_BESSEL_DGI_SHIFT_X, .MOSCOW_BESSEL_DGI_SHIFT_Y))
}

crs_describe <- function(spec) {
  if (is.null(spec)) return("<none>")
  spec$label %||% spec$value %||% spec$kind
}

# Classify a free-form custom CRS string entered by the user.
classify_custom_crs <- function(input) {
  input <- trimws(input)
  if (!nzchar(input)) stop("Empty CRS value.")
  if (file.exists(input)) {
    ext <- tolower(tools::file_ext(input))
    if (ext == "wkt") {
      return(list(kind = "wkt", value = input, label = paste0("WKT file: ", basename(input))))
    }
    return(crs_file(input))
  }
  if (grepl("^[0-9]+$", input)) {
    return(crs_epsg(paste0("EPSG:", input)))
  }
  if (grepl("^EPSG:", input, ignore.case = TRUE)) {
    return(crs_epsg(toupper(input)))
  }
  if (grepl("^(ESRI|IAU|OGC):", input, ignore.case = TRUE)) {
    return(crs_epsg(toupper(input)))
  }
  if (grepl("\\+proj", input)) {
    return(crs_proj(input))
  }
  # Fallback: pass the string verbatim to GDAL (covers PROJ/WKT inline forms).
  list(kind = "proj", value = input, label = paste0("Custom: ", input))
}

# Try to detect the CRS of a shapefile from its sibling .prj, optionally
# enriched with an EPSG code via ogrinfo. Returns a crs spec, or NULL.
detect_shp_crs <- function(shp_file, ogr2ogr_exe = "ogr2ogr") {
  prj <- paste0(tools::file_path_sans_ext(shp_file), ".prj")
  if (!file.exists(prj)) {
    return(NULL)
  }

  txt <- tryCatch(paste(readLines(prj, warn = FALSE), collapse = " "),
                  error = function(e) "")
  name <- ""
  m <- regmatches(txt, regexpr('(?<=PROJCS\\[")[^"]+', txt, perl = TRUE))
  if (length(m) > 0) name <- m[1]
  if (!nzchar(name)) {
    m <- regmatches(txt, regexpr('(?<=GEOGCS\\[")[^"]+', txt, perl = TRUE))
    if (length(m) > 0) name <- m[1]
  }

  # Customer DGI "Moscow_bessel" pattern: Bessel_Moscow spheroid, central
  # meridian 37.5, latitude of origin ~55.6666, false easting/northing 0. The
  # customer .prj has NO datum shift, so map it to the Moscow_bessel ДГИ preset,
  # which adds the known TOWGS84 transform for correct WGS84 alignment.
  is_dgi <- grepl("Moscow_bessel", name, ignore.case = TRUE) ||
    (grepl("Bessel_Moscow", txt, ignore.case = TRUE) &&
       grepl('"Central_Meridian",37\\.5', txt) &&
       grepl('"Latitude_Of_Origin",55\\.66', txt) &&
       grepl('"False_Easting",0', txt) &&
       grepl('"False_Northing",0', txt))
  if (is_dgi) {
    return(crs_moscow_bessel_dgi())
  }

  # Best-effort EPSG enrichment via ogrinfo.
  epsg <- ""
  ogrinfo <- .sibling_exe(ogr2ogr_exe, "ogrinfo")
  if (nzchar(ogrinfo)) {
    out <- tryCatch(
      suppressWarnings(system2(ogrinfo, c("-al", "-so", path_arg(shp_file)),
                               stdout = TRUE, stderr = TRUE)),
      error = function(e) character(0)
    )
    if (length(out) > 0) {
      joined <- paste(out, collapse = " ")
      ids <- regmatches(joined, gregexpr('ID\\["EPSG",[0-9]+\\]', joined))[[1]]
      if (length(ids) == 0) {
        ids <- regmatches(joined, gregexpr('AUTHORITY\\["EPSG","[0-9]+"\\]', joined))[[1]]
      }
      if (length(ids) > 0) {
        code <- regmatches(ids[length(ids)], regexpr("[0-9]+", ids[length(ids)]))
        if (length(code) > 0) epsg <- code[1]
      }
    }
  }

  if (nzchar(epsg)) {
    lbl <- if (nzchar(name)) sprintf("%s (EPSG:%s)", name, epsg) else paste0("EPSG:", epsg)
    return(crs_epsg(paste0("EPSG:", epsg), lbl))
  }

  lbl <- if (nzchar(name)) sprintf("%s [%s]", name, basename(prj)) else paste0("from ", basename(prj))
  crs_file(prj, lbl)
}

# Materialize a crs spec into an argument usable by ogr2ogr -s_srs / -t_srs.
resolve_crs_arg <- function(spec, work_dir, role) {
  if (is.null(spec)) return(NULL)
  switch(spec$kind,
    epsg = spec$value,
    proj = spec$value,
    prjfile = normalizePath(spec$value, winslash = "/", mustWork = TRUE),
    wkt = normalizePath(spec$value, winslash = "/", mustWork = TRUE),
    mggt = {
      prj <- file.path(work_dir, paste0("MGGT_Moscow_", role, ".prj"))
      write_mggt_moscow_prj_file(prj, use_towgs84 = isTRUE(spec$use_towgs84))
      normalizePath(prj, winslash = "/", mustWork = TRUE)
    },
    stop("Unknown CRS kind: ", spec$kind)
  )
}

# Interactive CRS chooser with presets, optional detected default, and custom.
choose_crs <- function(title, default_key = "wgs84", detected = NULL) {
  presets <- list(
    wgs84   = crs_epsg("EPSG:4326",  "WGS84 geographic (EPSG:4326)"),
    webmerc = crs_epsg("EPSG:3857",  "Web Mercator (EPSG:3857)"),
    utm37   = crs_epsg("EPSG:32637", "UTM zone 37N / WGS84 (EPSG:32637)"),
    mggt    = crs_mggt(use_towgs84 = FALSE),
    msk11z5 = crs_msk11_zone5(),
    msk11pech = crs_msk11_pechora(),
    msk11pechdwg = crs_msk11_pechora_dwg(),
    msk11pechdwgn = crs_msk11_pechora_dwg_n2220(),
    mbdgi   = crs_moscow_bessel_dgi(),
    mbdgishift = crs_moscow_bessel_dgi_shift()
  )

  has_det <- !is.null(detected)
  cat("\n", title, "\n", sep = "")
  if (has_det) cat("[D] Detected: ", crs_describe(detected), "\n", sep = "")
  cat("[1] WGS84 geographic (EPSG:4326)\n")
  cat("[2] Web Mercator (EPSG:3857)\n")
  cat("[3] UTM zone 37N / WGS84 (EPSG:32637)\n")
  cat("[4] MGGT Moscow local (custom PRJ, towgs84 disabled)\n")
  cat("[5] МСК-11 зона 5 / Республика Коми (MSK-11 zone 5, PROJ)\n")
  cat("[6] МСК-11 Печорский вариант (lon0=56.033, x0=5400000, PROJ)\n")
  cat("[7] МСК-11 Печора DWG / full northing (y0=-13316.254, PROJ)\n")
  cat("[8] МСК-11 Печора DWG / поправка -2220 м по северу (y0=-11096.254, PROJ)\n")
  cat("[9] Moscow_bessel ДГИ (customer Bessel_Moscow, x0=0/y0=0, +towgs84)\n")
  cat(sprintf("[10] Moscow_bessel ДГИ (смещение x=%s, y=%s) (manual control-point correction)\n",
              .MOSCOW_BESSEL_DGI_SHIFT_X, .MOSCOW_BESSEL_DGI_SHIFT_Y))
  cat("[11] Custom (EPSG code / PROJ string / WKT or .prj file path)\n")

  default_label <- switch(default_key,
    detected = if (has_det) crs_describe(detected) else presets$wgs84$label,
    wgs84   = presets$wgs84$label,
    webmerc = presets$webmerc$label,
    utm37   = presets$utm37$label,
    mggt    = presets$mggt$label,
    msk11z5 = presets$msk11z5$label,
    msk11pech = presets$msk11pech$label,
    msk11pechdwg = presets$msk11pechdwg$label,
    msk11pechdwgn = presets$msk11pechdwgn$label,
    mbdgi   = presets$mbdgi$label,
    mbdgishift = presets$mbdgishift$label,
    presets$wgs84$label
  )

  ans <- trimws(readline(sprintf("Choose CRS, Enter for default (%s): ", default_label)))
  if (ans == "") {
    ans <- switch(default_key,
      detected = if (has_det) "D" else "1",
      wgs84 = "1", webmerc = "2", utm37 = "3", mggt = "4", msk11z5 = "5",
      msk11pech = "6", msk11pechdwg = "7", msk11pechdwgn = "8", mbdgi = "9",
      mbdgishift = "10", "1")
  }
  al <- tolower(ans)

  if (al == "d") {
    if (has_det) return(detected)
    message("No detected CRS available; using WGS84.")
    return(presets$wgs84)
  }
  if (ans == "1") return(presets$wgs84)
  if (ans == "2") return(presets$webmerc)
  if (ans == "3") return(presets$utm37)
  if (ans == "4") return(presets$mggt)
  if (ans == "5") return(presets$msk11z5)
  if (ans == "6") return(presets$msk11pech)
  if (ans == "7") return(presets$msk11pechdwg)
  if (ans == "8") return(presets$msk11pechdwgn)
  if (ans == "9") return(presets$mbdgi)
  if (ans == "10") return(presets$mbdgishift)
  if (ans == "11") {
    val <- trimws(readline(
      "Enter EPSG (e.g. 32638 or EPSG:32638), PROJ string, or path to .prj/.wkt file: "))
    return(classify_custom_crs(val))
  }
  stop("Invalid CRS choice: ", ans)
}

# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------

convert_dwg_from_menu <- function(
    scan_dir = .convert_dwg_script_dir,
    recursive = FALSE,
    out_dir = NULL,
    oda_exe = "C:/Program Files/ODA/ODAFileConverter 27.1.0/ODAFileConverter.exe",
    ogr2ogr_exe = find_ogr2ogr(),
    source_crs = NULL,
    target_crs = NULL,
    dxf_encoding = "UTF-8",
    output_prefix = NULL,
    overwrite = TRUE,
    oda_timeout = 300
) {
  direction <- choose_conversion_direction()
  if (is.null(direction)) {
    return(invisible(NULL))
  }
  scan_dir <- choose_source_dir(scan_dir)

  if (direction == "shp_to_dwg") {
    return(convert_shp_from_menu(
      scan_dir = scan_dir,
      recursive = recursive,
      out_dir = out_dir,
      oda_exe = oda_exe,
      ogr2ogr_exe = ogr2ogr_exe,
      source_crs = source_crs,
      target_crs = target_crs,
      output_prefix = output_prefix,
      overwrite = overwrite,
      oda_timeout = oda_timeout
    ))
  }

  if (direction == "shp_to_shp") {
    return(convert_shp_to_shp_from_menu(
      scan_dir = scan_dir,
      recursive = recursive,
      out_dir = out_dir,
      ogr2ogr_exe = ogr2ogr_exe,
      source_crs = source_crs,
      target_crs = target_crs,
      overwrite = overwrite
    ))
  }

  scan_dir <- normalizePath(scan_dir, winslash = "/", mustWork = TRUE)

  dwg_files <- list.files(
    scan_dir,
    pattern = "\\.dwg$",
    full.names = TRUE,
    recursive = recursive,
    ignore.case = TRUE
  )

  if (length(dwg_files) == 0) {
    stop(
      "No DWG files found in: ", scan_dir, "\n",
      "Put this R script into the folder with DWG files, or pass scan_dir explicitly."
    )
  }

  cat("\nDWG files found in:\n", scan_dir, "\n\n", sep = "")
  for (i in seq_along(dwg_files)) {
    rel_path <- sub(paste0("^", normalizePath(scan_dir, winslash = "/", mustWork = TRUE), "/?"), "", dwg_files[i])
    cat(sprintf("[%d] %s\n", i, rel_path))
  }
  cat("[A] Convert all files\n")
  cat("[Q] Quit\n\n")

  choice <- trimws(readline("Choose DWG file number, A for all, or Q to quit: "))

  if (tolower(choice) == "q") {
    message("Cancelled.")
    return(invisible(NULL))
  }

  if (tolower(choice) == "a") {
    selected_files <- dwg_files
  } else {
    idx <- suppressWarnings(as.integer(choice))
    if (is.na(idx) || idx < 1 || idx > length(dwg_files)) {
      stop("Invalid choice: ", choice)
    }
    selected_files <- dwg_files[idx]
  }

  # --- CRS selection (applies to all selected DWG files) ---
  if (is.null(source_crs)) {
    cat("\n--- SOURCE CRS of the DWG/CAD coordinates ---\n")
    cat("Note: DWG/DXF files usually carry NO reliable embedded CRS in this\n")
    cat("workflow, so please confirm the coordinate system the drawing is in.\n")
    source_crs <- choose_crs("Select SOURCE CRS for the DWG/CAD data:", default_key = "mggt")
  }
  if (is.null(target_crs)) {
    target_crs <- choose_crs("Select TARGET (output) CRS for the shapefiles:", default_key = "wgs84")
  }
  cat("\nSOURCE CRS: ", crs_describe(source_crs), "\n", sep = "")
  cat("TARGET CRS: ", crs_describe(target_crs), "\n", sep = "")

  if (is.null(out_dir)) {
    if (length(selected_files) == 1) {
      out_dir <- file.path(dirname(selected_files[1]), "shp_out")
    } else {
      out_dir <- file.path(scan_dir, "shp_out")
    }
  }

  results <- vector("list", length(selected_files))

  for (i in seq_along(selected_files)) {
    current_dwg <- selected_files[i]
    current_base <- safe_ascii_name(tools::file_path_sans_ext(basename(current_dwg)))

    if (length(selected_files) > 1) {
      current_out_dir <- file.path(out_dir, current_base)
    } else {
      current_out_dir <- out_dir
    }

    current_prefix <- output_prefix
    if (is.null(current_prefix)) {
      current_prefix <- current_base
    }

    cat("\n========================================\n")
    cat("Converting file ", i, " of ", length(selected_files), ":\n", sep = "")
    cat(current_dwg, "\n")
    cat("Output folder:\n", current_out_dir, "\n", sep = "")
    cat("========================================\n\n")

    results[[i]] <- convert_dwg_to_shp(
      dwg_file = current_dwg,
      out_dir = current_out_dir,
      oda_exe = oda_exe,
      ogr2ogr_exe = ogr2ogr_exe,
      dxf_encoding = dxf_encoding,
      source_crs = source_crs,
      target_crs = target_crs,
      output_prefix = current_prefix,
      overwrite = overwrite,
      oda_timeout = oda_timeout
    )
  }

  invisible(results)
}

choose_conversion_direction <- function() {
  cat("\nConversion direction:\n")
  cat("[1] DWG -> SHP\n")
  cat("[2] SHP -> DWG\n")
  cat("[3] SHP -> SHP (change projection / смена проекции)\n")
  cat("[Q] Quit\n\n")

  choice <- trimws(readline("Choose direction [1/2/3/Q]: "))
  choice_l <- tolower(choice)

  if (choice_l == "q") {
    message("Cancelled.")
    return(invisible(NULL))
  }
  if (choice %in% c("", "1")) {
    return("dwg_to_shp")
  }
  if (choice == "2") {
    return("shp_to_dwg")
  }
  if (choice == "3") {
    return("shp_to_shp")
  }
  stop("Invalid conversion direction: ", choice)
}

choose_source_dir <- function(default_dir = .convert_dwg_script_dir) {
  default_dir <- normalizePath(default_dir, winslash = "/", mustWork = TRUE)
  cat("\nSource folder default:\n", default_dir, "\n", sep = "")
  answer <- trimws(readline("Enter source folder path, or press Enter to use default: "))
  if (answer == "") {
    answer <- default_dir
  }
  normalizePath(answer, winslash = "/", mustWork = TRUE)
}

convert_shp_from_menu <- function(
    scan_dir = .convert_dwg_script_dir,
    recursive = FALSE,
    out_dir = NULL,
    oda_exe = "C:/Program Files/ODA/ODAFileConverter 27.1.0/ODAFileConverter.exe",
    ogr2ogr_exe = find_ogr2ogr(),
    source_crs = NULL,
    target_crs = NULL,
    output_prefix = NULL,
    overwrite = TRUE,
    oda_timeout = 300
) {
  scan_dir <- normalizePath(scan_dir, winslash = "/", mustWork = TRUE)

  shp_files <- list.files(
    scan_dir,
    pattern = "\\.shp$",
    full.names = TRUE,
    recursive = recursive,
    ignore.case = TRUE
  )

  if (length(shp_files) == 0) {
    stop(
      "No SHP files found in: ", scan_dir, "\n",
      "Put this R script into the folder with SHP files, or pass scan_dir explicitly."
    )
  }

  cat("\nSHP files found in:\n", scan_dir, "\n\n", sep = "")
  for (i in seq_along(shp_files)) {
    rel_path <- sub(paste0("^", normalizePath(scan_dir, winslash = "/", mustWork = TRUE), "/?"), "", shp_files[i])
    cat(sprintf("[%d] %s\n", i, rel_path))
  }
  cat("[A] Convert all files\n")
  cat("[Q] Quit\n\n")

  choice <- trimws(readline("Choose SHP file number, A for all, or Q to quit: "))

  if (tolower(choice) == "q") {
    message("Cancelled.")
    return(invisible(NULL))
  }

  if (tolower(choice) == "a") {
    selected_files <- shp_files
  } else {
    idx <- suppressWarnings(as.integer(choice))
    if (is.na(idx) || idx < 1 || idx > length(shp_files)) {
      stop("Invalid choice: ", choice)
    }
    selected_files <- shp_files[idx]
  }

  # --- CRS selection (applies to all selected SHP files) ---
  if (is.null(source_crs)) {
    ogr2ogr_resolved <- tryCatch(resolve_ogr2ogr(ogr2ogr_exe), error = function(e) ogr2ogr_exe)
    detected <- tryCatch(detect_shp_crs(selected_files[1], ogr2ogr_resolved),
                         error = function(e) NULL)
    if (!is.null(detected)) {
      cat("\nDetected source CRS of first shapefile:\n  ", crs_describe(detected), "\n", sep = "")
    } else {
      cat("\nNo .prj found next to the first shapefile; source CRS unknown.\n")
    }
    source_crs <- choose_crs(
      "Select SOURCE CRS of the shapefile(s):",
      default_key = if (!is.null(detected)) "detected" else "wgs84",
      detected = detected
    )
  }
  if (is.null(target_crs)) {
    target_crs <- choose_crs("Select TARGET (output) CRS for the DWG/CAD data:", default_key = "mggt")
  }
  cat("\nSOURCE CRS: ", crs_describe(source_crs), "\n", sep = "")
  cat("TARGET CRS: ", crs_describe(target_crs), "\n", sep = "")

  if (is.null(out_dir)) {
    if (length(selected_files) == 1) {
      out_dir <- file.path(dirname(selected_files[1]), "dwg_out")
    } else {
      out_dir <- file.path(scan_dir, "dwg_out")
    }
  }

  results <- vector("list", length(selected_files))

  for (i in seq_along(selected_files)) {
    current_shp <- selected_files[i]
    current_base <- safe_ascii_name(tools::file_path_sans_ext(basename(current_shp)))

    if (length(selected_files) > 1) {
      current_out_dir <- file.path(out_dir, current_base)
    } else {
      current_out_dir <- out_dir
    }

    current_prefix <- output_prefix
    if (is.null(current_prefix)) {
      current_prefix <- current_base
    }

    cat("\n========================================\n")
    cat("Converting file ", i, " of ", length(selected_files), ":\n", sep = "")
    cat(current_shp, "\n")
    cat("Output folder:\n", current_out_dir, "\n", sep = "")
    cat("========================================\n\n")

    results[[i]] <- convert_shp_to_dwg(
      shp_file = current_shp,
      out_dir = current_out_dir,
      oda_exe = oda_exe,
      ogr2ogr_exe = ogr2ogr_exe,
      source_crs = source_crs,
      target_crs = target_crs,
      output_prefix = current_prefix,
      overwrite = overwrite,
      oda_timeout = oda_timeout
    )
  }

  invisible(results)
}

# SHP -> SHP reprojection menu: pick source folder shapefiles, choose SOURCE and
# TARGET CRS via the shared chooser, and reproject each into a "shp_reprojected"
# subfolder. Reuses the same CRS presets / TOWGS84 parameters as the other modes.
convert_shp_to_shp_from_menu <- function(
    scan_dir = .convert_dwg_script_dir,
    recursive = FALSE,
    out_dir = NULL,
    ogr2ogr_exe = find_ogr2ogr(),
    source_crs = NULL,
    target_crs = NULL,
    overwrite = TRUE
) {
  scan_dir <- normalizePath(scan_dir, winslash = "/", mustWork = TRUE)

  shp_files <- list.files(
    scan_dir,
    pattern = "\\.shp$",
    full.names = TRUE,
    recursive = recursive,
    ignore.case = TRUE
  )

  if (length(shp_files) == 0) {
    stop(
      "No SHP files found in: ", scan_dir, "\n",
      "Put this R script into the folder with SHP files, or pass scan_dir explicitly."
    )
  }

  cat("\nSHP files found in:\n", scan_dir, "\n\n", sep = "")
  for (i in seq_along(shp_files)) {
    rel_path <- sub(paste0("^", normalizePath(scan_dir, winslash = "/", mustWork = TRUE), "/?"), "", shp_files[i])
    cat(sprintf("[%d] %s\n", i, rel_path))
  }
  cat("[A] Convert all files\n")
  cat("[Q] Quit\n\n")

  choice <- trimws(readline("Choose SHP file number, A for all, or Q to quit: "))

  if (tolower(choice) == "q") {
    message("Cancelled.")
    return(invisible(NULL))
  }

  if (tolower(choice) == "a") {
    selected_files <- shp_files
  } else {
    idx <- suppressWarnings(as.integer(choice))
    if (is.na(idx) || idx < 1 || idx > length(shp_files)) {
      stop("Invalid choice: ", choice)
    }
    selected_files <- shp_files[idx]
  }

  # --- CRS selection (applies to all selected SHP files) ---
  if (is.null(source_crs)) {
    ogr2ogr_resolved <- tryCatch(resolve_ogr2ogr(ogr2ogr_exe), error = function(e) ogr2ogr_exe)
    detected <- tryCatch(detect_shp_crs(selected_files[1], ogr2ogr_resolved),
                         error = function(e) NULL)
    if (!is.null(detected)) {
      cat("\nDetected source CRS of first shapefile:\n  ", crs_describe(detected), "\n", sep = "")
    } else {
      cat("\nNo .prj found next to the first shapefile; source CRS unknown.\n")
    }
    source_crs <- choose_crs(
      "Select SOURCE CRS of the shapefile(s):",
      default_key = if (!is.null(detected)) "detected" else "mggt",
      detected = detected
    )
  }
  if (is.null(target_crs)) {
    target_crs <- choose_crs(
      "Select TARGET (output) CRS for the reprojected shapefile(s):",
      default_key = "wgs84"
    )
  }
  cat("\nSOURCE CRS: ", crs_describe(source_crs), "\n", sep = "")
  cat("TARGET CRS: ", crs_describe(target_crs), "\n", sep = "")

  if (is.null(out_dir)) {
    out_dir <- file.path(scan_dir, "shp_reprojected")
  }

  results <- vector("list", length(selected_files))

  for (i in seq_along(selected_files)) {
    current_shp <- selected_files[i]

    cat("\n========================================\n")
    cat("Reprojecting file ", i, " of ", length(selected_files), ":\n", sep = "")
    cat(current_shp, "\n")
    cat("Output folder:\n", out_dir, "\n", sep = "")
    cat("========================================\n\n")

    results[[i]] <- reproject_shp_to_shp(
      shp_file = current_shp,
      out_dir = out_dir,
      ogr2ogr_exe = ogr2ogr_exe,
      source_crs = source_crs,
      target_crs = target_crs,
      overwrite = overwrite
    )
  }

  invisible(results)
}

# Reproject a single shapefile to a new CRS, writing an ESRI Shapefile (with a
# matching .prj) into out_dir. Geometry and attributes are preserved by ogr2ogr.
reproject_shp_to_shp <- function(
    shp_file,
    out_dir,
    ogr2ogr_exe = find_ogr2ogr(),
    source_crs = NULL,
    target_crs = NULL,
    output_name = NULL,
    overwrite = TRUE
) {
  if (is.null(source_crs) || is.null(target_crs)) {
    stop("Both SOURCE and TARGET CRS are required for SHP -> SHP reprojection.")
  }

  ogr2ogr_exe <- resolve_ogr2ogr(ogr2ogr_exe)
  ensure_gdal_env(ogr2ogr_exe)

  shp_file <- normalizePath(shp_file, winslash = "/", mustWork = TRUE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  if (is.null(output_name) || !nzchar(output_name)) {
    output_name <- tools::file_path_sans_ext(basename(shp_file))
  }
  out_shp <- file.path(out_dir, paste0(output_name, ".shp"))

  # Never write over the input shapefile itself.
  if (identical(normalizePath(out_shp, winslash = "/", mustWork = FALSE), shp_file)) {
    out_shp <- file.path(out_dir, paste0(output_name, "_reproj.shp"))
  }

  if (file.exists(out_shp)) {
    if (isTRUE(overwrite)) {
      remove_shapefile(out_shp)
    } else {
      base <- tools::file_path_sans_ext(out_shp)
      k <- 1
      repeat {
        cand <- paste0(base, "_", k, ".shp")
        if (!file.exists(cand)) { out_shp <- cand; break }
        k <- k + 1
      }
    }
  }

  work_dir <- out_dir
  s_srs <- resolve_crs_arg(source_crs, work_dir, "source")
  t_srs <- resolve_crs_arg(target_crs, work_dir, "target")

  args <- c(
    "-s_srs", srs_arg(s_srs),
    "-t_srs", srs_arg(t_srs),
    "-f", quote_arg("ESRI Shapefile"),
    path_arg(out_shp),
    path_arg(shp_file),
    "-lco", "ENCODING=UTF-8",
    "-skipfailures"
  )

  message("Reprojecting SHP -> SHP: ", basename(shp_file), " -> ", basename(out_shp))
  status <- system2(ogr2ogr_exe, args = args, stdout = TRUE, stderr = TRUE)
  cat(paste(status, collapse = "\n"), "\n")

  if (!file.exists(out_shp)) {
    stop("Reprojected shapefile was not created: ", out_shp)
  }

  # ogr2ogr normally writes the .prj from -t_srs; backfill the custom MGGT WKT
  # if it did not (e.g. when the target is the MGGT preset given as a .prj file).
  prj_file <- paste0(tools::file_path_sans_ext(out_shp), ".prj")
  if (!file.exists(prj_file) && identical(target_crs$kind, "mggt")) {
    write_mggt_moscow_prj_file(prj_file, use_towgs84 = isTRUE(target_crs$use_towgs84))
  }

  invisible(out_shp)
}

safe_ascii_name <- function(x) {
  x <- iconv(x, from = "", to = "ASCII//TRANSLIT", sub = "_")
  x <- gsub("[^A-Za-z0-9_]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  if (is.na(x) || x == "") {
    x <- "dwg_export"
  }
  if (!grepl("^[A-Za-z]", x)) {
    x <- paste0("dwg_", x)
  }
  x
}

# ---------------------------------------------------------------------------
# DWG -> SHP
# ---------------------------------------------------------------------------

convert_dwg_to_shp <- function(
    dwg_file,
    out_dir = file.path(dirname(dwg_file), "shp_out"),
    oda_exe = "C:/Program Files/ODA/ODAFileConverter/ODAFileConverter.exe",
    ogr2ogr_exe = find_ogr2ogr(),
    dxf_encoding = "UTF-8",
    source_crs = NULL,
    target_crs = NULL,
    transform_to_wgs84 = TRUE,
    use_towgs84 = FALSE,
    output_prefix = NULL,
    overwrite = TRUE,
    oda_timeout = 300,
    write_qgis_project = TRUE,
    write_kml = TRUE
) {
  dwg_file <- normalizePath(dwg_file, winslash = "/", mustWork = TRUE)

  if (!file.exists(oda_exe)) {
    stop(
      "ODA File Converter not found: ", oda_exe, "\n",
      "Install ODA File Converter or pass the correct oda_exe path."
    )
  }

  ogr2ogr_exe <- resolve_ogr2ogr(ogr2ogr_exe)
  ensure_gdal_env(ogr2ogr_exe)

  # Backward-compatible CRS defaults when specs are not supplied.
  if (is.null(source_crs)) source_crs <- crs_mggt(use_towgs84 = use_towgs84)
  if (is.null(target_crs) && isTRUE(transform_to_wgs84)) {
    target_crs <- crs_epsg("EPSG:4326", "WGS84 geographic (EPSG:4326)")
  }

  if (!file.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
  }
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  if (is.null(output_prefix)) {
    output_prefix <- "dwg_export"
  }

  work_dir <- file.path(out_dir, "_work")
  dxf_dir <- file.path(work_dir, "dxf")
  dwg_dir <- file.path(work_dir, "dwg")
  dir.create(dxf_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dwg_dir, recursive = TRUE, showWarnings = FALSE)

  # ASCII temporary filename: ODA File Converter can be unreliable with
  # Cyrillic filenames when called from R.
  dwg_copy <- file.path(dwg_dir, "input.dwg")
  file.copy(dwg_file, dwg_copy, overwrite = TRUE)

  message("Step 1: DWG -> DXF using ODA File Converter")
  message("Temporary DWG copy: ", dwg_copy)

  oda_args <- c(
    path_arg(dwg_dir),
    path_arg(dxf_dir),
    "ACAD2018",
    "DXF",
    "0",
    "1",
    "*.dwg"
  )

  oda_log <- file.path(work_dir, "oda_converter.log")
  message("ODA log: ", oda_log)
  message("Waiting for ODA File Converter, timeout ", oda_timeout, " seconds ...")

  oda_exit <- tryCatch(
    system2(
      oda_exe,
      args = oda_args,
      stdout = oda_log,
      stderr = oda_log,
      timeout = oda_timeout
    ),
    warning = function(w) {
      message("ODA warning: ", conditionMessage(w))
      return(124L)
    },
    error = function(e) {
      stop("ODA File Converter failed to start: ", conditionMessage(e))
    }
  )

  if (file.exists(oda_log)) {
    log_text <- readLines(oda_log, warn = FALSE, encoding = "UTF-8")
    if (length(log_text) > 0) {
      cat(paste(utils::tail(log_text, 40), collapse = "\n"), "\n")
    }
  }

  if (!identical(as.integer(oda_exit), 0L)) {
    stop(
      "ODA File Converter did not finish successfully. Exit code: ", oda_exit, "\n",
      "If ODA opened a graphical window, close it and check whether the command-line converter path is correct.\n",
      "Try passing the full path to ODAFileConverter.exe, for example:\n",
      "convert_dwg_from_menu(oda_exe = 'C:/Program Files/ODA/ODAFileConverter/ODAFileConverter.exe')"
    )
  }

  dxf_file <- file.path(dxf_dir, "input.dxf")
  if (!file.exists(dxf_file)) {
    dxf_candidates <- list.files(dxf_dir, pattern = "\\.dxf$", full.names = TRUE, ignore.case = TRUE)
    if (length(dxf_candidates) == 0) {
      stop("DXF was not created. Check ODA File Converter output above.")
    }
    dxf_file <- dxf_candidates[1]
  }

  message("DXF created: ", dxf_file)

  # Decide reproject vs assign vs none based on the CRS specs.
  s_srs <- t_srs <- a_srs <- NULL
  if (!is.null(target_crs)) {
    s_srs <- resolve_crs_arg(source_crs, work_dir, "source")
    t_srs <- resolve_crs_arg(target_crs, work_dir, "target")
    message("Step 2: reproject ", crs_describe(source_crs), " -> ", crs_describe(target_crs))
  } else if (!is.null(source_crs)) {
    a_srs <- resolve_crs_arg(source_crs, work_dir, "source")
    message("Step 2: assign CRS without reprojection: ", crs_describe(source_crs))
  } else {
    message("Step 2: DXF -> SHP, no CRS handling")
  }

  shp_points <- file.path(out_dir, paste0(output_prefix, "_points.shp"))
  shp_lines <- file.path(out_dir, paste0(output_prefix, "_lines.shp"))
  shp_polygons <- file.path(out_dir, paste0(output_prefix, "_polygons.shp"))

  if (overwrite) {
    remove_shapefile(shp_points)
    remove_shapefile(shp_lines)
    remove_shapefile(shp_polygons)
  }

  # OGR_STYLE AS Style captures the resolved CAD color / pen width / dash / label
  # info into a "Style" DBF field that the QGIS styling step below parses.
  export_geom_type(
    ogr2ogr_exe = ogr2ogr_exe,
    dxf_file = dxf_file,
    shp_file = shp_points,
    layer_name = paste0(output_prefix, "_points"),
    sql = "SELECT Geometry, Layer, PaperSpace, SubClasses, Linetype, EntityHandle, Text, OGR_STYLE AS Style FROM entities WHERE ST_GeometryType(geometry) IN ('POINT','POINT Z')",
    dxf_encoding = dxf_encoding,
    s_srs = s_srs, t_srs = t_srs, a_srs = a_srs
  )

  export_geom_type(
    ogr2ogr_exe = ogr2ogr_exe,
    dxf_file = dxf_file,
    shp_file = shp_lines,
    layer_name = paste0(output_prefix, "_lines"),
    sql = "SELECT Geometry, Layer, PaperSpace, SubClasses, Linetype, EntityHandle, Text, OGR_STYLE AS Style FROM entities WHERE ST_GeometryType(geometry) IN ('LINESTRING','MULTILINESTRING','MULTILINESTRING Z')",
    dxf_encoding = dxf_encoding,
    s_srs = s_srs, t_srs = t_srs, a_srs = a_srs
  )

  export_geom_type(
    ogr2ogr_exe = ogr2ogr_exe,
    dxf_file = dxf_file,
    shp_file = shp_polygons,
    layer_name = paste0(output_prefix, "_polygons"),
    sql = "SELECT Geometry, Layer, PaperSpace, SubClasses, Linetype, EntityHandle, Text, OGR_STYLE AS Style FROM entities WHERE ST_GeometryType(geometry) IN ('POLYGON','POLYGON Z','MULTIPOLYGON','MULTIPOLYGON Z')",
    dxf_encoding = dxf_encoding,
    s_srs = s_srs, t_srs = t_srs, a_srs = a_srs
  )

  out_crs <- if (!is.null(target_crs)) crs_describe(target_crs)
             else if (!is.null(source_crs)) crs_describe(source_crs)
             else NA_character_
  message("Step 3: Output CRS is ", out_crs)

  # --- Step 4: QGIS project + per-layer styling (new in v15) ---
  qgis_project <- NULL
  if (isTRUE(write_qgis_project)) {
    out_crs_spec <- target_crs %||% source_crs
    qgis_project <- tryCatch(
      generate_qgis_project(
        out_dir = out_dir,
        output_prefix = output_prefix,
        shp_points = shp_points,
        shp_lines = shp_lines,
        shp_polygons = shp_polygons,
        crs_spec = out_crs_spec,
        work_dir = work_dir,
        ogr2ogr_exe = ogr2ogr_exe
      ),
      error = function(e) {
        message("QGIS project generation failed (shapefiles are still valid): ",
                conditionMessage(e))
        NULL
      }
    )
  }

  # --- Step 5: KML export for Organic Maps (always WGS84 / EPSG:4326) ---
  kml_files <- NULL
  if (isTRUE(write_kml)) {
    out_crs_spec <- target_crs %||% source_crs
    kml_files <- tryCatch(
      generate_organic_maps_kml(
        out_dir = out_dir,
        output_prefix = output_prefix,
        shp_points = shp_points,
        shp_lines = shp_lines,
        shp_polygons = shp_polygons,
        shp_crs_spec = out_crs_spec,
        work_dir = work_dir,
        ogr2ogr_exe = ogr2ogr_exe
      ),
      error = function(e) {
        message("KML export failed (shapefiles are still valid): ",
                conditionMessage(e))
        NULL
      }
    )
  }

  result <- list(
    dxf = dxf_file,
    points = shp_points,
    lines = shp_lines,
    polygons = shp_polygons,
    out_dir = out_dir,
    qgis_project = qgis_project,
    kml = kml_files,
    source_crs = crs_describe(source_crs),
    target_crs = out_crs
  )

  message("Done. Output folder: ", out_dir)
  return(invisible(result))
}

# ---------------------------------------------------------------------------
# QGIS project (.qgs) + styling transfer  (new in v15)
# ---------------------------------------------------------------------------

# Escape text for inclusion in XML element content / attribute values.
.xml_escape <- function(x) {
  if (length(x) == 0) return("")
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;",  x, fixed = TRUE)
  x <- gsub(">", "&gt;",  x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  x
}

# Minimal, dependency-free dBASE III (.dbf) reader returning field names and
# records as character columns. Encoding of text fields is assumed UTF-8 (the
# shapefiles are written with ENCODING=UTF-8).
.read_dbf <- function(path, max_records = 50000L) {
  if (!file.exists(path)) return(NULL)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)

  header <- readBin(con, "raw", 32L)
  if (length(header) < 32L) return(NULL)
  ai <- function(r) as.integer(r)
  n_records  <- sum(ai(header[5:8])  * c(1, 256, 65536, 16777216))
  header_size <- ai(header[9]) + ai(header[10]) * 256L
  record_size <- ai(header[11]) + ai(header[12]) * 256L
  if (record_size <= 0L) return(NULL)

  fields <- character(0)
  lengths <- integer(0)
  types <- character(0)
  repeat {
    b <- readBin(con, "raw", 1L)
    if (length(b) == 0L) break
    if (ai(b[1]) == 0x0D) break
    rest <- readBin(con, "raw", 31L)
    if (length(rest) < 31L) break
    desc <- c(b, rest)
    name_raw <- desc[1:11]
    name_raw <- name_raw[ai(name_raw) != 0L]
    nm <- if (length(name_raw)) rawToChar(name_raw) else ""
    typ <- rawToChar(desc[12])
    len <- ai(desc[17])
    fields  <- c(fields, nm)
    types   <- c(types, typ)
    lengths <- c(lengths, len)
  }
  if (length(fields) == 0L) {
    return(list(fields = character(0), types = character(0),
                data = list(), n = 0L))
  }

  seek(con, where = header_size, origin = "start")
  nrec <- as.integer(min(n_records, max_records))
  out <- vector("list", length(fields))
  names(out) <- fields
  for (j in seq_along(fields)) out[[j]] <- character(nrec)

  filled <- 0L
  for (i in seq_len(nrec)) {
    rec <- readBin(con, "raw", record_size)
    if (length(rec) < record_size) break
    p <- 2L  # byte 1 is the deletion flag
    for (j in seq_along(fields)) {
      len <- lengths[j]
      if (len > 0L) {
        raw_field <- rec[p:(p + len - 1L)]
        raw_field <- raw_field[ai(raw_field) != 0L]
        val <- if (length(raw_field)) rawToChar(raw_field) else ""
        Encoding(val) <- "UTF-8"
        out[[j]][i] <- trimws(val)
        p <- p + len
      }
    }
    filled <- i
  }
  if (filled < nrec) {
    for (j in seq_along(fields)) out[[j]] <- out[[j]][seq_len(filled)]
  }
  list(fields = fields, types = types, data = out, n = filled)
}

# Match a logical field name against the (possibly 10-char-truncated) DBF names.
.find_field <- function(fields, name) {
  if (length(fields) == 0L) return(NA_character_)
  lf <- tolower(fields)
  ln <- tolower(name)
  hit <- fields[lf == ln]
  if (length(hit)) return(hit[1])
  for (k in seq_along(fields)) {
    n <- min(nchar(fields[k]), nchar(name))
    if (n >= 3L && substr(lf[k], 1, n) == substr(ln, 1, n)) return(fields[k])
  }
  NA_character_
}

# AutoCAD Color Index (ACI) 1-7 to RGB hex.
.aci_hex <- function(i) {
  tab <- c("1" = "#FF0000", "2" = "#FFFF00", "3" = "#00FF00",
           "4" = "#00FFFF", "5" = "#0000FF", "6" = "#FF00FF",
           "7" = "#FFFFFF")
  key <- as.character(suppressWarnings(as.integer(i)))
  if (!is.na(key) && key %in% names(tab)) return(unname(tab[key]))
  NA_character_
}

# Deterministic per-layer-name color so the same CAD layer always maps to the
# same hue across runs.
.deterministic_hex <- function(name) {
  palette <- c("#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
               "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf",
               "#aec7e8", "#ffbb78", "#98df8a", "#ff9896", "#c5b0d5")
  if (is.na(name) || !nzchar(name)) return(palette[8])
  codes <- utf8ToInt(name)
  h <- sum(codes * seq_along(codes)) + sum(codes)
  palette[(abs(h) %% length(palette)) + 1L]
}

# Convert "#RRGGBB" to a QGIS "r,g,b,a" string.
.hex_to_rgba <- function(hex, alpha = 255L) {
  hex <- sub("^#", "", hex)
  if (is.na(hex) || nchar(hex) < 6L) return(sprintf("0,0,0,%d", alpha))
  r <- strtoi(substr(hex, 1, 2), 16L)
  g <- strtoi(substr(hex, 3, 4), 16L)
  b <- strtoi(substr(hex, 5, 6), 16L)
  sprintf("%d,%d,%d,%d", r, g, b, alpha)
}

# Parse a single OGR style string into color / pen-width / dash.
.parse_ogr_style <- function(style) {
  out <- list(color = NA_character_, width = NA_real_, dash = FALSE)
  if (is.null(style) || is.na(style) || !nzchar(style)) return(out)

  cm <- regmatches(style, regexpr("(?<=c:#)[0-9A-Fa-f]{6}", style, perl = TRUE))
  if (length(cm)) {
    out$color <- paste0("#", toupper(cm[1]))
  } else {
    fm <- regmatches(style, regexpr("(?<=fc:#)[0-9A-Fa-f]{6}", style, perl = TRUE))
    if (length(fm)) out$color <- paste0("#", toupper(fm[1]))
  }

  wm <- regmatches(style, regexpr("(?<=w:)[0-9]+(\\.[0-9]+)?", style, perl = TRUE))
  if (length(wm)) {
    wv <- suppressWarnings(as.numeric(wm[1]))
    if (!is.na(wv) && wv > 0) out$width <- wv
  }

  if (grepl("dash|dot", style, ignore.case = TRUE)) out$dash <- TRUE
  out
}

# Build per-category styling from a DBF, keyed by the CAD "Layer" attribute.
.summarize_categories <- function(dbf) {
  if (is.null(dbf) || length(dbf$fields) == 0L || dbf$n == 0L) return(NULL)
  f_layer <- .find_field(dbf$fields, "Layer")
  if (is.na(f_layer)) return(NULL)
  f_style <- .find_field(dbf$fields, "Style")
  f_lt    <- .find_field(dbf$fields, "Linetype")
  f_color <- .find_field(dbf$fields, "Color")

  layvals <- dbf$data[[f_layer]]
  styvals <- if (!is.na(f_style)) dbf$data[[f_style]] else rep(NA_character_, length(layvals))
  ltvals  <- if (!is.na(f_lt))    dbf$data[[f_lt]]    else rep(NA_character_, length(layvals))
  colvals <- if (!is.na(f_color)) dbf$data[[f_color]] else rep(NA_character_, length(layvals))

  uniq <- unique(layvals)
  cats <- list()
  for (lv in uniq) {
    idx <- which(layvals == lv)
    col <- NA_character_; width <- NA_real_; dash <- FALSE
    for (k in idx) {
      ps <- .parse_ogr_style(styvals[k])
      if (is.na(col) && !is.na(ps$color)) col <- ps$color
      if (is.na(width) && !is.na(ps$width)) width <- ps$width
      if (isTRUE(ps$dash)) dash <- TRUE
      if (!is.na(col) && !is.na(width)) break
    }
    # Fallback to a numeric ACI Color field if present and no style color found.
    if (is.na(col) && !is.na(f_color)) {
      for (k in idx) {
        aci <- .aci_hex(colvals[k])
        if (!is.na(aci)) { col <- aci; break }
      }
    }
    lt_join <- paste(ltvals[idx], collapse = " ")
    if (grepl("DASH|DOT|CENTER|HIDDEN", lt_join, ignore.case = TRUE)) dash <- TRUE
    if (is.na(col)) col <- .deterministic_hex(lv)
    cats[[length(cats) + 1L]] <- list(value = lv, color = col, width = width, dash = dash)
  }
  list(attr = f_layer, cats = cats)
}

# Determine whether a label field ("Text") is present and has any content.
.label_field <- function(dbf) {
  if (is.null(dbf) || length(dbf$fields) == 0L) return(NA_character_)
  f_text <- .find_field(dbf$fields, "Text")
  if (is.na(f_text)) return(NA_character_)
  if (dbf$n > 0L && any(nzchar(dbf$data[[f_text]]))) return(f_text)
  NA_character_
}

# --- Symbol builders (legacy <prop> form, widely read by QGIS 3.x) ---

.sym_line <- function(name, rgba, width_mm, dash) {
  style <- if (isTRUE(dash)) "dash" else "solid"
  if (is.na(width_mm) || width_mm <= 0) width_mm <- 0.26
  width_mm <- max(0.05, min(width_mm, 5))
  paste0(
    '<symbol alpha="1" clip_to_extent="1" force_rhr="0" type="line" name="', name, '">',
    '<layer class="SimpleLine" enabled="1" locked="0" pass="0">',
    '<prop k="line_color" v="', rgba, '"/>',
    '<prop k="line_width" v="', format(width_mm, trim = TRUE), '"/>',
    '<prop k="line_width_unit" v="MM"/>',
    '<prop k="line_style" v="', style, '"/>',
    '<prop k="capstyle" v="square"/>',
    '<prop k="joinstyle" v="bevel"/>',
    '<prop k="use_custom_dash" v="0"/>',
    '</layer></symbol>'
  )
}

.sym_marker <- function(name, rgba) {
  paste0(
    '<symbol alpha="1" clip_to_extent="1" force_rhr="0" type="marker" name="', name, '">',
    '<layer class="SimpleMarker" enabled="1" locked="0" pass="0">',
    '<prop k="color" v="', rgba, '"/>',
    '<prop k="outline_color" v="35,35,35,255"/>',
    '<prop k="outline_width" v="0"/>',
    '<prop k="outline_width_unit" v="MM"/>',
    '<prop k="name" v="circle"/>',
    '<prop k="size" v="2"/>',
    '<prop k="size_unit" v="MM"/>',
    '<prop k="angle" v="0"/>',
    '<prop k="offset" v="0,0"/>',
    '<prop k="horizontal_anchor_point" v="1"/>',
    '<prop k="vertical_anchor_point" v="1"/>',
    '</layer></symbol>'
  )
}

.sym_fill <- function(name, rgba_fill, rgba_outline) {
  paste0(
    '<symbol alpha="1" clip_to_extent="1" force_rhr="0" type="fill" name="', name, '">',
    '<layer class="SimpleFill" enabled="1" locked="0" pass="0">',
    '<prop k="color" v="', rgba_fill, '"/>',
    '<prop k="style" v="solid"/>',
    '<prop k="outline_color" v="', rgba_outline, '"/>',
    '<prop k="outline_width" v="0.26"/>',
    '<prop k="outline_width_unit" v="MM"/>',
    '<prop k="outline_style" v="solid"/>',
    '<prop k="joinstyle" v="bevel"/>',
    '</layer></symbol>'
  )
}

# Build a symbol of the right geometry kind for one category.
.sym_for <- function(geom, name, cat) {
  if (geom == "line") {
    return(.sym_line(name, .hex_to_rgba(cat$color, 255L), cat$width, cat$dash))
  }
  if (geom == "point") {
    return(.sym_marker(name, .hex_to_rgba(cat$color, 255L)))
  }
  # polygon: semi-transparent fill (alpha 127) + solid outline
  .sym_fill(name, .hex_to_rgba(cat$color, 127L), .hex_to_rgba(cat$color, 255L))
}

# Build a categorized (or single-symbol) renderer-v2 block for one layer.
.build_renderer <- function(geom, summary) {
  if (is.null(summary) || length(summary$cats) == 0L) {
    # single symbol fallback
    default_cat <- list(value = "", color = .deterministic_hex("default"),
                        width = NA_real_, dash = FALSE)
    sym <- .sym_for(geom, "0", default_cat)
    return(paste0(
      '<renderer-v2 type="singleSymbol" forceraster="0" symbollevels="0" enableorderby="0">',
      '<symbols>', sym, '</symbols>',
      '</renderer-v2>'
    ))
  }

  cats <- summary$cats
  cat_xml <- character(length(cats))
  sym_xml <- character(length(cats))
  for (i in seq_along(cats)) {
    nm <- as.character(i - 1L)
    cat_xml[i] <- sprintf(
      '<category render="true" symbol="%s" value="%s" label="%s"/>',
      nm, .xml_escape(cats[[i]]$value), .xml_escape(cats[[i]]$value))
    sym_xml[i] <- .sym_for(geom, nm, cats[[i]])
  }
  paste0(
    '<renderer-v2 type="categorizedSymbol" attr="', .xml_escape(summary$attr),
    '" forceraster="0" symbollevels="0" enableorderby="0">',
    '<categories>', paste(cat_xml, collapse = ""), '</categories>',
    '<symbols>', paste(sym_xml, collapse = ""), '</symbols>',
    '</renderer-v2>'
  )
}

# Build a simple labeling block referencing the given field.
.build_labeling <- function(geom, field) {
  # QGIS placement enum: 0 = OverPoint, 1 = AroundPoint, 2 = Line,
  # 3 = Curved (line), 4 = Horizontal, ...
  placement <- switch(geom, point = "1", line = "2", polygon = "4", "1")
  paste0(
    '<labeling type="simple">',
    '<settings calloutType="simple">',
    '<text-style fieldName="', .xml_escape(field), '" isExpression="0" ',
    'fontFamily="Arial" fontSize="9" fontSizeUnit="Point" namedStyle="Regular" ',
    'textColor="0,0,0,255" textOpacity="1">',
    '<text-buffer bufferDraw="1" bufferSize="1" bufferSizeUnits="MM" ',
    'bufferColor="255,255,255,255" bufferOpacity="1"/>',
    '</text-style>',
    '<text-format/>',
    '<placement placement="', placement, '"/>',
    '<rendering/>',
    '</settings>',
    '</labeling>'
  )
}

# Build a complete QGIS 3 <spatialrefsys> block from a crs spec, using
# gdalsrsinfo when available to obtain WKT / proj4 / authority code. The returned
# string carries "authid", "label" and "wkt" attributes for logging and for
# backfilling shapefile .prj files.
#
# Custom (non-EPSG) CRS are emitted under the USER namespace (authid USER:100000,
# srsid 100000) so QGIS 3 registers them as a valid user CRS instead of leaving
# the project CRS unset (which made converted vectors shift). The block always
# includes wkt, proj4, srsid, srid, authid, description, projectionacronym,
# ellipsoidacronym and geographicflag.
#
# Fallback policy: WKT/proj4 come from gdalsrsinfo against the resolved CRS; if
# gdalsrsinfo is unavailable, a "proj" spec's own string is used as proj4. Only a
# NULL spec falls back to EPSG:4326 -- a selected custom CRS never silently does.
.crs_qgis_block <- function(spec, work_dir, ogr2ogr_exe) {
  if (is.null(spec)) spec <- crs_epsg("EPSG:4326", "WGS84 geographic (EPSG:4326)")

  authid <- ""; wkt <- ""; proj4 <- ""; desc <- ""
  if (identical(spec$kind, "epsg")) authid <- toupper(spec$value)
  if (identical(spec$kind, "proj")) proj4 <- spec$value  # fallback proj4

  arg <- tryCatch(resolve_crs_arg(spec, work_dir, "qgis"), error = function(e) NULL)
  srsinfo <- .sibling_exe(ogr2ogr_exe, "gdalsrsinfo")

  run <- function(fmt) {
    tryCatch(
      suppressWarnings(system2(srsinfo, c("-o", fmt, srs_arg(arg)),
                               stdout = TRUE, stderr = FALSE)),
      error = function(e) character(0)
    )
  }

  if (nzchar(srsinfo) && !is.null(arg)) {
    w <- run("wkt1")
    w <- trimws(w[nzchar(trimws(w))])
    if (length(w)) wkt <- paste(w, collapse = "")

    p <- run("proj4")
    p <- trimws(p[nzchar(trimws(p))])
    if (length(p)) proj4 <- gsub("^['\"]|['\"]$", "", p[1])
  }

  # NOTE: deliberately do NOT use gdalsrsinfo's fuzzy "-o epsg" matching to
  # invent an authid for a custom CRS. For a calibrated MSK/PROJ definition it
  # returns a "close" standard EPSG (e.g. EPSG:2594) whose false northing differs
  # from the user's, which would make QGIS reproject with the wrong definition
  # and shift the vectors again. Only an explicitly-chosen EPSG spec keeps its
  # authid; every other (custom) CRS is emitted under the USER namespace with its
  # exact wkt/proj4 so the geometry matches the selected CRS bit-for-bit.

  # Projection / ellipsoid acronyms and geographic flag, derived from proj4.
  projacr <- ""; ellpsacr <- ""; geoflag <- "false"
  if (nzchar(proj4)) {
    mp <- regmatches(proj4, regexpr("\\+proj=[A-Za-z0-9_]+", proj4))
    if (length(mp)) projacr <- sub("\\+proj=", "", mp[1])
    me <- regmatches(proj4, regexpr("\\+ellps=[A-Za-z0-9_]+", proj4))
    if (length(me)) ellpsacr <- sub("\\+ellps=", "", me[1])
    if (identical(projacr, "longlat")) geoflag <- "true"
  }

  # authid / srid / srsid / description.
  if (nzchar(authid) && grepl("^EPSG:", authid)) {
    srid <- sub("^EPSG:", "", authid)
    srsid <- srid
    desc <- spec$label %||% authid
  } else {
    authid <- "USER:100000"   # QGIS user-CRS namespace
    srsid <- "100000"
    srid <- "100000"
    desc <- spec$label %||% "Custom CRS"
  }

  native <- if (nzchar(wkt)) ' nativeFormat="Wkt"' else ""
  parts <- c(
    paste0("<spatialrefsys", native, ">"),
    paste0("<wkt>", .xml_escape(wkt), "</wkt>"),
    paste0("<proj4>", .xml_escape(proj4), "</proj4>"),
    paste0("<srsid>", srsid, "</srsid>"),
    paste0("<srid>", srid, "</srid>"),
    paste0("<authid>", .xml_escape(authid), "</authid>"),
    paste0("<description>", .xml_escape(desc), "</description>"),
    paste0("<projectionacronym>", .xml_escape(projacr), "</projectionacronym>"),
    paste0("<ellipsoidacronym>", .xml_escape(ellpsacr), "</ellipsoidacronym>"),
    paste0("<geographicflag>", geoflag, "</geographicflag>"),
    "</spatialrefsys>"
  )
  block <- paste(parts, collapse = "")
  attr(block, "authid") <- authid
  attr(block, "label") <- desc
  attr(block, "wkt") <- wkt
  block
}

# Write a sidecar .qml next to a shapefile (manual re-add fallback).
.write_qml <- function(shp_file, renderer_xml, labeling_xml, label_enabled) {
  qml <- paste0(tools::file_path_sans_ext(shp_file), ".qml")
  body <- paste0(
    '<!DOCTYPE qgis PUBLIC \'http://mrcc.com/qgis.dtd\' \'SYSTEM\'>\n',
    '<qgis version="3.34.0" styleCategories="Symbology|Labeling">\n',
    renderer_xml, "\n",
    if (label_enabled) paste0("<labelsEnabled>1</labelsEnabled>\n", labeling_xml, "\n")
    else "<labelsEnabled>0</labelsEnabled>\n",
    "</qgis>\n"
  )
  writeLines(body, qml, useBytes = TRUE)
  invisible(qml)
}

# Main entry: build a .qgs project referencing whichever shapefiles exist,
# styled by CAD layer/color, with labels from the Text field.
generate_qgis_project <- function(
    out_dir,
    output_prefix,
    shp_points,
    shp_lines,
    shp_polygons,
    crs_spec,
    work_dir,
    ogr2ogr_exe
) {
  message("Step 4: building QGIS project (.qgs) with CAD styling ...")

  specs <- list(
    list(path = shp_points,   geom = "point"),
    list(path = shp_lines,    geom = "line"),
    list(path = shp_polygons, geom = "polygon")
  )
  specs <- Filter(function(s) file.exists(s$path), specs)
  if (length(specs) == 0L) {
    message("  No shapefiles were produced; skipping QGIS project.")
    return(invisible(NULL))
  }

  srs_block <- tryCatch(.crs_qgis_block(crs_spec, work_dir, ogr2ogr_exe),
                        error = function(e) "<spatialrefsys></spatialrefsys>")
  srs_authid <- attr(srs_block, "authid") %||% ""
  srs_label  <- attr(srs_block, "label") %||% crs_describe(crs_spec)
  srs_wkt    <- attr(srs_block, "wkt") %||% ""

  # Backfill a .prj for each produced shapefile when ogr2ogr did not write one,
  # so the layer's on-disk CRS matches the project/layer CRS for custom projections.
  if (nzchar(srs_wkt)) {
    for (s in specs) {
      prj <- paste0(tools::file_path_sans_ext(s$path), ".prj")
      if (!file.exists(prj)) {
        tryCatch(writeLines(srs_wkt, prj, useBytes = TRUE), error = function(e) NULL)
      }
    }
  }

  tree_entries <- character(0)
  maplayers <- character(0)
  used_styles <- 0L; used_labels <- 0L

  for (s in specs) {
    shp <- s$path
    geom <- s$geom
    layername <- tools::file_path_sans_ext(basename(shp))
    lid <- paste0(gsub("[^A-Za-z0-9_]", "_", layername), "_v15")
    datasource <- paste0("./", basename(shp))   # relative to the .qgs in out_dir

    dbf <- tryCatch(.read_dbf(paste0(tools::file_path_sans_ext(shp), ".dbf")),
                    error = function(e) NULL)
    summary <- tryCatch(.summarize_categories(dbf), error = function(e) NULL)
    if (!is.null(summary)) used_styles <- used_styles + 1L

    label_field <- tryCatch(.label_field(dbf), error = function(e) NA_character_)
    label_enabled <- !is.na(label_field)
    labeling_xml <- if (label_enabled) .build_labeling(geom, label_field) else ""
    if (label_enabled) used_labels <- used_labels + 1L

    renderer_xml <- .build_renderer(geom, summary)

    # sidecar .qml (best-effort)
    tryCatch(.write_qml(shp, renderer_xml, labeling_xml, label_enabled),
             error = function(e) NULL)

    geomname <- switch(geom, point = "Point", line = "Line", polygon = "Polygon")
    tree_entries <- c(tree_entries, sprintf(
      '<layer-tree-layer id="%s" name="%s" checked="Qt::Checked" expanded="1" providerKey="ogr" source="%s"/>',
      lid, .xml_escape(layername), .xml_escape(datasource)))

    maplayers <- c(maplayers, paste0(
      '<maplayer geometry="', geomname, '" type="vector">',
      '<id>', lid, '</id>',
      '<datasource>', .xml_escape(datasource), '</datasource>',
      '<layername>', .xml_escape(layername), '</layername>',
      '<provider encoding="UTF-8">ogr</provider>',
      '<srs>', srs_block, '</srs>',
      renderer_xml,
      if (label_enabled) '<labelsEnabled>1</labelsEnabled>' else '<labelsEnabled>0</labelsEnabled>',
      if (label_enabled) labeling_xml else '',
      '</maplayer>'
    ))
  }

  xml <- paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<qgis projectname="', .xml_escape(output_prefix), '" version="3.34.0-Prizren">\n',
    '<projectCrs>', srs_block, '</projectCrs>\n',
    '<layer-tree-group>',
    paste(tree_entries, collapse = ""),
    '<custom-order enabled="0"/>',
    '</layer-tree-group>\n',
    '<projectlayers>',
    paste(maplayers, collapse = ""),
    '</projectlayers>\n',
    '</qgis>\n'
  )

  qgs_path <- file.path(out_dir, paste0(output_prefix, "_qgis_project.qgs"))
  writeLines(xml, qgs_path, useBytes = TRUE)

  message("  QGIS project written: ", qgs_path)
  message("  Project CRS: ", srs_label, " [authid ", srs_authid, "]")
  message("  Layers: ", length(specs),
          " (geometry-based; categorized within each by CAD 'Layer'); ",
          "each layer CRS set to the same authid.")
  message("  Styled layers: ", used_styles, "; labeled layers: ", used_labels,
          " (sidecar .qml files also written).")
  message("  Limitations: styling is derived from CAD layer names + resolved OGR ",
          "style colors/width/dash and the Text field; exact CAD lineweights, ",
          "text height/rotation and block/hatch styles are approximated, not ",
          "reproduced 1:1.")

  invisible(qgs_path)
}

# ---------------------------------------------------------------------------
# KML export for Organic Maps  (new in v16)
# ---------------------------------------------------------------------------
#
# Organic Maps consumes standard KML 2.2 in WGS84 (EPSG:4326). We therefore
# always reproject to EPSG:4326 here, regardless of the chosen shapefile output
# CRS. One KML is written per geometry layer; if the LIBKML driver is present a
# combined <prefix>_organic_maps.kml is also produced.

# Pick the most capable available KML driver: LIBKML (multi-layer, richer style)
# if compiled in, otherwise the always-present basic "KML" driver.
.pick_kml_driver <- function(ogr2ogr_exe) {
  fmts <- tryCatch(
    suppressWarnings(system2(ogr2ogr_exe, "--formats", stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0)
  )
  j <- paste(fmts, collapse = "\n")
  if (grepl("LIBKML", j, ignore.case = FALSE)) return("LIBKML")
  "KML"
}

# Build the SQLite-dialect SELECT for a layer, exposing a "Name" column (Text
# then Layer fallback), keeping Layer/Text as attributes, and aliasing the
# stored OGR style back to OGR_STYLE so the KML driver can render simple colors.
.kml_select_sql <- function(dbf, layername) {
  cols <- c("Geometry")
  f_text  <- if (!is.null(dbf)) .find_field(dbf$fields, "Text")  else NA_character_
  f_layer <- if (!is.null(dbf)) .find_field(dbf$fields, "Layer") else NA_character_
  f_style <- if (!is.null(dbf)) .find_field(dbf$fields, "Style") else NA_character_

  name_expr <- NULL
  if (!is.na(f_text) && !is.na(f_layer)) {
    name_expr <- sprintf('COALESCE(NULLIF("%s", \'\'), "%s")', f_text, f_layer)
  } else if (!is.na(f_text)) {
    name_expr <- sprintf('NULLIF("%s", \'\')', f_text)
  } else if (!is.na(f_layer)) {
    name_expr <- sprintf('"%s"', f_layer)
  }
  if (!is.null(name_expr)) cols <- c(cols, paste0(name_expr, ' AS "Name"'))
  if (!is.na(f_layer)) cols <- c(cols, sprintf('"%s" AS "Layer"', f_layer))
  if (!is.na(f_text))  cols <- c(cols, sprintf('"%s" AS "Text"', f_text))
  if (!is.na(f_style)) cols <- c(cols, sprintf('"%s" AS OGR_STYLE', f_style))

  sprintf('SELECT %s FROM "%s"', paste(cols, collapse = ", "), layername)
}

# Run ogr2ogr to write/append one shapefile layer into a KML in EPSG:4326.
.export_layer_to_kml <- function(ogr2ogr_exe, driver, shp, kml, layername, sql,
                                  s_srs = NULL, append = FALSE) {
  sql_file <- paste0(tools::file_path_sans_ext(shp), ".kmlsql")
  writeLines(sql, sql_file, useBytes = TRUE)
  on.exit(unlink(sql_file), add = TRUE)

  args <- character(0)
  if (!is.null(s_srs)) {
    args <- c(args, "-s_srs", srs_arg(s_srs))
  }
  args <- c(args, "-t_srs", "EPSG:4326")

  if (append) {
    args <- c(args, "-update", "-append")
  }

  args <- c(
    args,
    "-f", quote_arg(driver),
    path_arg(kml),
    path_arg(shp),
    "-dialect", "SQLite",
    "-sql", sql_file_arg(sql_file),
    "-nln", layername,
    "-dim", "XY",
    "-skipfailures"
  )
  if (identical(driver, "LIBKML")) {
    args <- c(args, "-lco", "NameField=Name")
  }

  status <- system2(ogr2ogr_exe, args = args, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(status, "status")) && !identical(as.integer(attr(status, "status")), 0L)) {
    message("    ogr2ogr KML output:\n      ",
            paste(utils::tail(status, 10), collapse = "\n      "))
  }
  invisible(status)
}

# Main entry: write per-layer KMLs (and a combined LIBKML file when possible)
# for Organic Maps. Returns a character vector of created KML paths (or NULL).
generate_organic_maps_kml <- function(
    out_dir,
    output_prefix,
    shp_points,
    shp_lines,
    shp_polygons,
    shp_crs_spec,
    work_dir,
    ogr2ogr_exe
) {
  message("Step 5: exporting KML for Organic Maps (WGS84 / EPSG:4326) ...")

  ogr2ogr_exe <- resolve_ogr2ogr(ogr2ogr_exe)
  ensure_gdal_env(ogr2ogr_exe)

  specs <- list(
    list(path = shp_points,   kind = "points"),
    list(path = shp_lines,    kind = "lines"),
    list(path = shp_polygons, kind = "polygons")
  )

  # Source CRS for reprojection = the shapefile output CRS. ogr2ogr can also read
  # it from the sibling .prj, but forcing -s_srs is robust when no .prj exists.
  s_srs <- tryCatch(resolve_crs_arg(shp_crs_spec, work_dir, "kmlsrc"),
                    error = function(e) NULL)

  driver <- .pick_kml_driver(ogr2ogr_exe)
  message("  KML driver: ", driver)

  combined <- file.path(out_dir, paste0(output_prefix, "_organic_maps.kml"))
  combine <- identical(driver, "LIBKML")
  if (combine) unlink(combined)
  combined_started <- FALSE

  created <- character(0)
  for (s in specs) {
    shp <- s$path
    if (!file.exists(shp)) {
      message("  skip ", s$kind, ": no shapefile produced")
      next
    }
    dbf <- tryCatch(.read_dbf(paste0(tools::file_path_sans_ext(shp), ".dbf")),
                    error = function(e) NULL)
    n_feat <- if (!is.null(dbf)) dbf$n else 0L
    if (is.null(n_feat) || n_feat == 0L) {
      message("  skip ", s$kind, ": no features")
      next
    }

    layername <- tools::file_path_sans_ext(basename(shp))
    kml <- file.path(out_dir, paste0(output_prefix, "_", s$kind, ".kml"))
    unlink(kml)
    sql <- .kml_select_sql(dbf, layername)

    .export_layer_to_kml(ogr2ogr_exe, driver, shp, kml, layername, sql, s_srs = s_srs)
    if (file.exists(kml)) {
      created <- c(created, kml)
      message("  KML written: ", kml, " (", n_feat, " features)")
    } else {
      message("  KML NOT created for ", s$kind, " (see ogr2ogr output above)")
    }

    if (combine) {
      tryCatch(
        .export_layer_to_kml(ogr2ogr_exe, driver, shp, combined, layername, sql,
                             s_srs = s_srs, append = combined_started),
        error = function(e) message("  combined KML append failed: ", conditionMessage(e))
      )
      if (file.exists(combined)) combined_started <- TRUE
    }
  }

  if (combine && combined_started && file.exists(combined)) {
    created <- c(created, combined)
    message("  Combined KML written: ", combined)
  } else if (!combine) {
    message("  Combined KML skipped (basic 'KML' driver; per-layer files only).")
  }

  if (length(created) == 0L) {
    message("  No KML files were created (no non-empty geometry layers).")
    return(invisible(NULL))
  }

  message("  Organic Maps note: import these KML files via Organic Maps > ",
          "Bookmarks/Tracks. Coordinates are WGS84 (EPSG:4326). Layer/Text are ",
          "kept as attributes; placemark names use Text, else Layer.")
  invisible(created)
}

# ---------------------------------------------------------------------------
# SHP -> DWG
# ---------------------------------------------------------------------------

convert_shp_to_dwg <- function(
    shp_file,
    out_dir = file.path(dirname(shp_file), "dwg_out"),
    oda_exe = "C:/Program Files/ODA/ODAFileConverter/ODAFileConverter.exe",
    ogr2ogr_exe = find_ogr2ogr(),
    source_crs = NULL,
    target_crs = NULL,
    transform_from_wgs84 = TRUE,
    use_towgs84 = FALSE,
    output_prefix = NULL,
    overwrite = TRUE,
    oda_timeout = 300
) {
  shp_file <- normalizePath(shp_file, winslash = "/", mustWork = TRUE)

  if (!file.exists(oda_exe)) {
    stop(
      "ODA File Converter not found: ", oda_exe, "\n",
      "Install ODA File Converter or pass the correct oda_exe path."
    )
  }

  ogr2ogr_exe <- resolve_ogr2ogr(ogr2ogr_exe)
  ensure_gdal_env(ogr2ogr_exe)

  # Backward-compatible CRS defaults when specs are not supplied.
  if (is.null(source_crs)) {
    detected <- tryCatch(detect_shp_crs(shp_file, ogr2ogr_exe), error = function(e) NULL)
    source_crs <- detected %||% crs_epsg("EPSG:4326", "WGS84 geographic (EPSG:4326)")
  }
  if (is.null(target_crs) && isTRUE(transform_from_wgs84)) {
    target_crs <- crs_mggt(use_towgs84 = use_towgs84)
  }

  if (!file.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
  }
  out_dir <- normalizePath(out_dir, winslash = "/", mustWork = TRUE)

  if (is.null(output_prefix)) {
    output_prefix <- safe_ascii_name(tools::file_path_sans_ext(basename(shp_file)))
  } else {
    output_prefix <- safe_ascii_name(output_prefix)
  }

  work_dir <- file.path(out_dir, "_work")
  dxf_dir <- file.path(work_dir, "dxf")
  dwg_dir <- file.path(work_dir, "dwg")
  dir.create(dxf_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dwg_dir, recursive = TRUE, showWarnings = FALSE)

  dxf_file <- file.path(dxf_dir, paste0(output_prefix, ".dxf"))
  dwg_file <- file.path(dwg_dir, paste0(output_prefix, ".dwg"))
  final_dwg <- file.path(out_dir, paste0(output_prefix, ".dwg"))

  if (overwrite) {
    unlink(c(dxf_file, dwg_file, final_dwg)[file.exists(c(dxf_file, dwg_file, final_dwg))])
  }

  message("Step 1: SHP -> DXF using GDAL/ogr2ogr")

  s_srs <- t_srs <- NULL
  if (!is.null(target_crs)) {
    s_srs <- resolve_crs_arg(source_crs, work_dir, "source")
    t_srs <- resolve_crs_arg(target_crs, work_dir, "target")
    message("Reproject ", crs_describe(source_crs), " -> ", crs_describe(target_crs))
  } else {
    message("No coordinate transformation requested; coordinates written to DXF as-is.")
  }

  export_shp_to_dxf(
    ogr2ogr_exe = ogr2ogr_exe,
    shp_file = shp_file,
    dxf_file = dxf_file,
    s_srs = s_srs,
    t_srs = t_srs
  )

  if (!file.exists(dxf_file)) {
    stop("DXF was not created: ", dxf_file)
  }

  message("DXF created: ", dxf_file)
  message("Step 2: DXF -> DWG using ODA File Converter")

  oda_args <- c(
    path_arg(dxf_dir),
    path_arg(dwg_dir),
    "ACAD2018",
    "DWG",
    "0",
    "1",
    "*.dxf"
  )

  oda_log <- file.path(work_dir, "oda_converter_shp_to_dwg.log")
  message("ODA log: ", oda_log)
  message("Waiting for ODA File Converter, timeout ", oda_timeout, " seconds ...")

  oda_exit <- tryCatch(
    system2(
      oda_exe,
      args = oda_args,
      stdout = oda_log,
      stderr = oda_log,
      timeout = oda_timeout
    ),
    warning = function(w) {
      message("ODA warning: ", conditionMessage(w))
      return(124L)
    },
    error = function(e) {
      stop("ODA File Converter failed to start: ", conditionMessage(e))
    }
  )

  if (file.exists(oda_log)) {
    log_text <- readLines(oda_log, warn = FALSE, encoding = "UTF-8")
    if (length(log_text) > 0) {
      cat(paste(utils::tail(log_text, 40), collapse = "\n"), "\n")
    }
  }

  if (!identical(as.integer(oda_exit), 0L)) {
    stop(
      "ODA File Converter did not finish successfully. Exit code: ", oda_exit, "\n",
      "If ODA opened a graphical window, close it and check whether the command-line converter path is correct.\n",
      "Try passing the full path to ODAFileConverter.exe."
    )
  }

  if (!file.exists(dwg_file)) {
    dwg_candidates <- list.files(dwg_dir, pattern = "\\.dwg$", full.names = TRUE, ignore.case = TRUE)
    if (length(dwg_candidates) == 0) {
      stop("DWG was not created. Check ODA File Converter output above.")
    }
    dwg_file <- dwg_candidates[1]
  }

  file.copy(dwg_file, final_dwg, overwrite = TRUE)

  result <- list(
    dxf = dxf_file,
    dwg = final_dwg,
    out_dir = out_dir,
    source_crs = crs_describe(source_crs),
    target_crs = if (!is.null(target_crs)) crs_describe(target_crs) else NA_character_
  )

  message("Done. Output DWG: ", final_dwg)
  return(invisible(result))
}

# Quote a CRS argument (file path or PROJ string) if it contains spaces.
srs_arg <- function(x) {
  if (grepl("[[:space:]]", x)) {
    # system2 routes through cmd.exe on Windows and through sh elsewhere, so a
    # PROJ string with spaces (e.g. custom MSK CRS) must be quoted for the right
    # shell or it gets word-split into invalid arguments.
    if (.Platform$OS.type == "windows") return(shQuote(x, type = "cmd"))
    return(shQuote(x))
  }
  x
}

export_shp_to_dxf <- function(
    ogr2ogr_exe,
    shp_file,
    dxf_file,
    s_srs = NULL,
    t_srs = NULL
) {
  ensure_gdal_env(ogr2ogr_exe)

  args <- character(0)

  if (!is.null(s_srs) && !is.null(t_srs)) {
    args <- c(
      args,
      "-s_srs", srs_arg(s_srs),
      "-t_srs", srs_arg(t_srs)
    )
  }

  args <- c(
    args,
    "-f", quote_arg("DXF"),
    path_arg(dxf_file),
    path_arg(shp_file),
    "-dim", "XY",
    "-skipfailures"
  )

  message("Exporting DXF: ", basename(dxf_file))
  status <- system2(ogr2ogr_exe, args = args, stdout = TRUE, stderr = TRUE)
  cat(paste(status, collapse = "\n"), "\n")

  if (!file.exists(dxf_file)) {
    stop("DXF was not created: ", dxf_file)
  }
}

path_arg <- function(x) {
  x <- normalizePath(x, winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type == "windows" && grepl("[[:space:]]", x)) {
    return(shQuote(x, type = "cmd"))
  }
  x
}

sql_file_arg <- function(x) {
  x <- paste0("@", normalizePath(x, winslash = "/", mustWork = FALSE))
  if (.Platform$OS.type == "windows" && grepl("[[:space:]]", x)) {
    return(shQuote(x, type = "cmd"))
  }
  x
}

export_geom_type <- function(
    ogr2ogr_exe,
    dxf_file,
    shp_file,
    layer_name,
    sql,
    dxf_encoding = "UTF-8",
    s_srs = NULL,
    t_srs = NULL,
    a_srs = NULL
) {
  ensure_gdal_env(ogr2ogr_exe)

  sql_file <- paste0(tools::file_path_sans_ext(shp_file), ".sql")
  writeLines(sql, sql_file, useBytes = TRUE)

  args <- c(
    "--config", "DXF_ENCODING", dxf_encoding
  )

  if (!is.null(s_srs) && !is.null(t_srs)) {
    args <- c(
      args,
      "-s_srs", srs_arg(s_srs),
      "-t_srs", srs_arg(t_srs)
    )
  } else if (!is.null(a_srs)) {
    args <- c(args, "-a_srs", srs_arg(a_srs))
  }

  args <- c(
    args,
    "-f", quote_arg("ESRI Shapefile"),
    path_arg(shp_file),
    path_arg(dxf_file),
    "-dialect", "SQLite",
    "-sql", sql_file_arg(sql_file),
    "-nln", layer_name,
    "-dim", "XY",
    "-lco", "ENCODING=UTF-8",
    "-skipfailures"
  )

  message("Exporting: ", basename(shp_file))
  status <- system2(ogr2ogr_exe, args = args, stdout = TRUE, stderr = TRUE)
  cat(paste(status, collapse = "\n"), "\n")

  if (!file.exists(shp_file)) {
    stop("Shapefile was not created: ", shp_file)
  }
}

quote_arg <- function(x) {
  if (.Platform$OS.type == "windows") {
    return(shQuote(x, type = "cmd"))
  }
  x
}

remove_shapefile <- function(shp_file) {
  base <- tools::file_path_sans_ext(shp_file)
  sidecars <- paste0(
    base,
    c(".shp", ".shx", ".dbf", ".prj", ".cpg", ".qpj", ".sbn", ".sbx", ".fix",
      ".qml", ".sql", ".kmlsql")
  )
  unlink(sidecars[file.exists(sidecars)])
}

write_mggt_moscow_prj <- function(shp_file, use_towgs84 = FALSE) {
  prj_file <- paste0(tools::file_path_sans_ext(shp_file), ".prj")
  write_mggt_moscow_prj_file(prj_file, use_towgs84 = use_towgs84)
}

write_mggt_moscow_prj_file <- function(prj_file, use_towgs84 = FALSE) {
  # ESRI WKT for a custom Moscow local coordinate system (MGGT).
  # +proj=tmerc +lat_0=55.66666666667 +lon_0=37.5 +k=1
  # +x_0=16.098 +y_0=14.512 +ellps=bessel
  # towgs84 is OFF by default; enable only if the user explicitly requests it.
  datum <- if (use_towgs84) {
    paste0(
      'DATUM["D_Bessel_1841_Moscow",',
      'SPHEROID["Bessel_1841",6377397.155,299.1528128],',
      'TOWGS84[316.151,78.924,589.650,-1.57273,2.69209,2.34693,8.4507]]'
    )
  } else {
    paste0(
      'DATUM["D_Bessel_1841_Moscow",',
      'SPHEROID["Bessel_1841",6377397.155,299.1528128]]'
    )
  }

  wkt <- paste0(
    'PROJCS["MGGT_Moscow_custom",',
    'GEOGCS["GCS_Bessel_1841_Moscow",',
    datum, ',',
    'PRIMEM["Greenwich",0.0],',
    'UNIT["Degree",0.0174532925199433]],',
    'PROJECTION["Transverse_Mercator"],',
    'PARAMETER["False_Easting",16.098],',
    'PARAMETER["False_Northing",14.512],',
    'PARAMETER["Central_Meridian",37.5],',
    'PARAMETER["Scale_Factor",1.0],',
    'PARAMETER["Latitude_Of_Origin",55.66666666667],',
    'UNIT["Meter",1.0]]'
  )

  writeLines(wkt, prj_file, useBytes = TRUE)
}

# Optional helper: create a ZIP archive with all shapefile components.
zip_shapefiles <- function(out_dir, zip_file = file.path(out_dir, "dwg_export_shp.zip")) {
  files <- list.files(
    out_dir,
    pattern = "\\.(shp|shx|dbf|prj|cpg|qpj|sbn|sbx|fix|qml|qgs|kml)$",
    full.names = TRUE,
    ignore.case = TRUE
  )

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(out_dir)

  utils::zip(zipfile = zip_file, files = basename(files))
  invisible(zip_file)
}

# Startup banner so the user can confirm the patched version is loaded.
message("convert_dwg_to_shp ", .CONVERT_DWG_VERSION,
        " loaded (added [8] МСК-11 Печора DWG / поправка -2220 м по северу ",
        "(y0=-11096.254) CRS preset to fix DWG output being ~2220 m too far north; ",
        "[7] full-northing DWG preset and all other presets kept; QGIS .qgs project ",
        "+ each layer still get an explicit valid CRS (custom => USER:100000 with ",
        "exact wkt/proj4); DWG->SHP writes KML + QGIS styling; auto-detect ogr2ogr).")

# Auto-run menu when the script is sourced in an interactive R/RStudio session.
if (isTRUE(getOption("convert_dwg_to_shp.autorun", TRUE)) && interactive()) {
  convert_dwg_from_menu()
}
