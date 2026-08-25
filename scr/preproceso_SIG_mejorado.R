# ============================================================
# Preproceso SIG: genera <archivo>_mejorado.shp/.dbf
# ------------------------------------------------------------
# Extrae solo la parte GIS del Rmd principal: lee el shapefile
# de subcuencas, repara geometrías, hace dissolve por
# 'Subcuenca', y guarda una versión "_mejorado" con:
#   - ID            (entero correlativo)
#   - Subcuenca     (nombre)
#   - area_ha       (hectáreas, 2 decimales)
#   - lat_deg       (lat del centroide en grados WGS84, 2 dec)
#
# No descarga ni procesa NetCDF — útil cuando solo se necesita
# regenerar el shapefile mejorado (p.ej. para alimentar el script
# Python que crea las bandas en WEAP).
#
# Uso:
#   1) Ajustar la sección CONFIG abajo.
#   2) Correr este archivo (Source) en RStudio o:
#         Rscript scr/preproceso_SIG_mejorado.R
# ============================================================

options(scipen = 999)

# ------------------------------------------------------------
# CONFIG  -- editar aquí
# ------------------------------------------------------------
cuenca_nombre    <- "LiguaPetorca"
archivo_shp      <- "Subcuencas_RDM_LP_mejorado.shp"
nombre_subcuenca <- "Subcuenca"

# Raíz del proyecto (carpeta que contiene Cuenca/, Results/, scr/).
# Por defecto: el padre de la carpeta de este script.
if (requireNamespace("rstudioapi", quietly = TRUE) &&
    rstudioapi::isAvailable() &&
    nzchar(rstudioapi::getActiveDocumentContext()$path)) {
  this_dir <- dirname(rstudioapi::getActiveDocumentContext()$path)
} else {
  # Fallback para Rscript
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
  this_dir <- if (length(file_arg)) dirname(normalizePath(file_arg)) else getwd()
}
proj_root <- normalizePath(file.path(this_dir, ".."), mustWork = FALSE)

cuenca_shp <- file.path(proj_root, "Cuenca", cuenca_nombre, archivo_shp)

# ------------------------------------------------------------
# Librerías
# ------------------------------------------------------------
suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
})

# ------------------------------------------------------------
# Helpers de geometría (idénticos al Rmd, sin lwgeom)
# ------------------------------------------------------------
.make_valid2 <- function(x) sf::st_make_valid(x)

.clean_sf_basic <- function(sfobj) {
  sfobj <- st_zm(sfobj, drop = TRUE, what = "ZM")
  sfobj <- sfobj[!st_is_empty(sfobj), ]
  sfobj <- sfobj[!is.na(st_geometry(sfobj)), ]
  sfobj
}

.safe_to_multipoly <- function(g) {
  gtypes <- unique(sf::st_geometry_type(g))
  needs_extract <- any(gtypes %in% c("GEOMETRYCOLLECTION", "LINESTRING",
                                     "MULTILINESTRING", "POINT", "MULTIPOINT"))
  needs_cast    <- any(gtypes == "POLYGON")
  if (needs_extract) g <- sf::st_collection_extract(g, "POLYGON")
  if (needs_cast)    g <- sf::st_cast(g, "MULTIPOLYGON", warn = FALSE)
  g
}

.clean_geom <- function(g, crs) {
  gg <- st_sfc(g, crs = crs)
  gg <- gg[!st_is_empty(gg)]
  gg <- gg[!is.na(gg)]
  if (length(gg) == 0) return(st_sfc(st_geometrycollection(), crs = crs))
  gg <- sf::st_make_valid(gg)
  gg <- .safe_to_multipoly(gg)
  gg <- gg[!st_is_empty(gg)]
  gg
}

.repair_and_union <- function(sf_group, name = "NA") {
  crs0 <- st_crs(sf_group)
  g <- st_geometry(sf_group)
  g <- st_zm(g, drop = TRUE, what = "ZM")
  g <- g[!st_is_empty(g)]
  g <- g[!is.na(g)]
  if (length(g) == 0) stop(paste0("Subcuenca '", name, "' sin geometría (vacía/nula)."))

  simp_tol <- if (sf::st_is_longlat(st_sfc(g[1], crs = crs0))) 5e-10 else 0.05

  g1 <- .clean_geom(g, crs0)
  out <- try(suppressWarnings(st_union(g1)), silent = TRUE)
  if (!inherits(out, "try-error")) return(.clean_geom(out, crs0))

  g2 <- try(suppressWarnings(st_buffer(g1, 0)), silent = TRUE)
  if (!inherits(g2, "try-error")) {
    out <- try(suppressWarnings(st_union(g2)), silent = TRUE)
    if (!inherits(out, "try-error")) return(.clean_geom(out, crs0))
  }

  g3 <- try(suppressWarnings(
    st_simplify(g1, dTolerance = simp_tol, preserveTopology = TRUE)
  ), silent = TRUE)
  if (!inherits(g3, "try-error")) {
    g3 <- sf::st_make_valid(g3)
    g3 <- .safe_to_multipoly(g3)
    out <- try(suppressWarnings(st_union(g3)), silent = TRUE)
    if (!inherits(out, "try-error")) return(.clean_geom(out, crs0))
  }

  stop(paste0("No se pudo reparar/disolver la subcuenca: '", name,
              "'. Revisar geometría original en QGIS."))
}

# ------------------------------------------------------------
# 3.0 Leer shapefile
# ------------------------------------------------------------
cat("Leyendo:", cuenca_shp, "\n")
shp <- read_sf(cuenca_shp)
shp <- .clean_sf_basic(shp)

# ------------------------------------------------------------
# 3.1 CRS (si viene vacío, asignar con heurística)
# ------------------------------------------------------------
if (is.na(st_crs(shp))) {
  bb <- st_bbox(shp)
  looks_lonlat <- max(abs(c(bb["xmin"], bb["xmax"]))) <= 180 &&
                  max(abs(c(bb["ymin"], bb["ymax"]))) <= 90
  if (looks_lonlat) {
    st_crs(shp) <- 4326
    cat("CRS ausente: se asigno EPSG:4326\n")
  } else {
    st_crs(shp) <- 32719
    cat("CRS ausente y coords no parecen lon/lat: se asigno EPSG:32719 (UTM 19S).\n",
        "Si tu cuenca no esta en zona 19S, edita este bloque.\n", sep = "")
  }
}

shp <- .make_valid2(shp)
shp <- .safe_to_multipoly(shp)
shp <- .clean_sf_basic(shp)

# ------------------------------------------------------------
# 3.2 Dissolve robusto por subcuenca (S2 off)
# ------------------------------------------------------------
old_s2 <- sf::sf_use_s2()
sf::sf_use_s2(FALSE)

if (nombre_subcuenca %in% names(shp)) {
  lst <- split(shp, shp[[nombre_subcuenca]])
  out_list <- lapply(names(lst), function(nm) {
    geom_u <- .repair_and_union(lst[[nm]], name = nm)
    st_sf(Subcuenca = nm, geometry = geom_u)
  })
  shp <- do.call(rbind, out_list)
} else {
  cat("Columna '", nombre_subcuenca, "' no encontrada. Subcuencas genericas.\n")
  shp <- shp %>% mutate(Subcuenca = paste0("SubC_", row_number()))
}

shp <- .make_valid2(shp)
shp <- .safe_to_multipoly(shp)
shp <- .clean_sf_basic(shp)

# ------------------------------------------------------------
# 3.3 ID
# ------------------------------------------------------------
shp <- shp %>% ungroup() %>% mutate(ID = row_number())

# ------------------------------------------------------------
# 3.4 area_ha (2 decimales)
# ------------------------------------------------------------
if (st_is_longlat(shp)) {
  cc       <- st_coordinates(st_centroid(st_union(st_geometry(shp))))
  zone     <- floor((cc[1] + 180) / 6) + 1
  epsg_utm <- 32700 + zone   # hemisferio sur
  shp_area <- st_transform(shp, epsg_utm)
  shp$area_ha <- round(as.numeric(st_area(shp_area)) / 10000, 2)
} else {
  shp$area_ha <- round(as.numeric(st_area(shp)) / 10000, 2)
}

# ------------------------------------------------------------
# 3.5 WGS84 + latitud del centroide
# ------------------------------------------------------------
shp <- st_transform(shp, 4326)
suppressWarnings({
  shp$lat_deg <- round(sf::st_coordinates(sf::st_centroid(shp))[, "Y"], 2)
})

cat("Shapefile listo:", nrow(shp), "subcuencas.\n")
print(shp %>% st_drop_geometry() %>% select(ID, Subcuenca, area_ha, lat_deg))

# ------------------------------------------------------------
# 3.6 Guardar _mejorado
# ------------------------------------------------------------
# Forzar 2 decimales en el DBF: el driver shapefile escribe los
# numeric con ancho/precision por defecto (N(24,15)) ignorando round().
# Convertir a character formateado garantiza columnas DBF cortas y limpias;
# downstream se reparsean con float() / as.numeric().
shp$area_ha <- formatC(shp$area_ha, format = "f", digits = 2)
shp$lat_deg <- formatC(shp$lat_deg, format = "f", digits = 2)

shp_mejorado_path <- file.path(
  dirname(cuenca_shp),
  paste0(tools::file_path_sans_ext(basename(cuenca_shp)), "_mejorado.shp")
)
sf::st_write(shp, shp_mejorado_path, delete_layer = TRUE, quiet = TRUE)
cat("OK Shapefile mejorado guardado en:", shp_mejorado_path, "\n")

sf::sf_use_s2(old_s2)
