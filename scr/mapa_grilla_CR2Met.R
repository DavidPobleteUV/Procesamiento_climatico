############################################################
# Mapa de la grilla CR2MET v2.5 sobre la cuenca de estudio
#
# Genera DOS mapas de la misma cuenca:
#   (a) coordenadas geograficas  -> WGS 84 lat/lon (EPSG:4326)
#   (b) coordenadas proyectadas  -> UTM (zona inferida del centroide)
#
# Ambos incluyen: celdas CR2MET, subcuencas, escala grafica en km,
# flecha de norte, leyenda y pie con metadatos.
#
# El color de cada celda es la FRACCION DE AREA de la celda cubierta
# por la cuenca, que es exactamente el peso que usa
# terra::extract(..., exact = TRUE) en el script de extraccion.
#
# Autores: Simon Caneo & David Poblete - EIC, Universidad de Valparaiso
# Licencia: GPL v3
#
# Uso:
#   - En RStudio: abrir y ejecutar (Source).
#   - Desde consola:  Rscript scr/mapa_grilla_CR2Met.R
############################################################

options(scipen = 999)

############################################################
# 1. Librerias
############################################################

.paquetes <- c("sf", "ggplot2", "dplyr")
.faltan   <- .paquetes[!vapply(.paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(.faltan)) {
  stop("Faltan paquetes: install.packages(c(\"",
       paste(.faltan, collapse = "\", \""), "\"))")
}

suppressPackageStartupMessages({
  library(sf)
  library(ggplot2)
  library(dplyr)
})

############################################################
# 2. PARAMETROS  <-- LO UNICO QUE HAY QUE EDITAR
############################################################

cuenca_nombre    <- "Aconcagua_catchments2026"        # carpeta dentro de Cuenca/
archivo_shp      <- "Aconcagua_catchments2026.shp"    # shapefile de subcuencas
nombre_subcuenca <- "Catchments"                      # columna con el nombre de cada subcuenca

# Si el .Rmd de extraccion ya genero el shapefile "<nombre>_mejorado.shp",
# usarlo (viene disuelto por subcuenca, con columna "Subcuenca").
usar_mejorado    <- TRUE

# NetCDF de referencia para tomar la geometria exacta de la grilla.
#   NULL = busca automaticamente el primero disponible en nc_cache/
#   Si no hay ninguno, se reconstruye la grilla CR2MET v2.5 analiticamente.
nc_referencia    <- NULL

# Celdas extra dibujadas alrededor del bounding box de la cuenca
buffer_celdas    <- 2

# EPSG proyectado. NULL = zona UTM inferida desde el centroide
epsg_utm         <- NULL

# Opciones de dibujo
mostrar_centroides   <- TRUE   # centroide de cada celda (regla "centroid-in")
centroides_solo_uso  <- TRUE   # TRUE = solo las celdas que tocan la cuenca
                               # FALSE = todas las celdas dibujadas
etiquetar_subcuencas <- TRUE   # nombre de cada subcuenca sobre el mapa
etiquetar_celdas     <- FALSE  # % de cobertura escrito dentro de cada celda
exportar_grilla      <- TRUE   # guardar la grilla recortada como GeoPackage

# Posicion de escala y norte, en fraccion del ancho/alto del panel
pos_escala <- c(0.03, 0.04)    # esquina inferior izquierda de la barra
pos_norte  <- c(0.94, 0.82)    # base de la flecha

# Salida
ancho_cm <- 20
dpi_out  <- 300

############################################################
# 3. Directorio del proyecto y helpers cartograficos
############################################################

# .buscar_raiz(), .dir_script(), raiz_proyecto(), .num_bonito(), .fmt(),
# capa_escala() y capa_norte() viven en scr/utils_mapa.R, compartido con
# los demas scripts de mapas.
.este_dir <- local({
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable() &&
      nzchar(rstudioapi::getActiveDocumentContext()$path)) {
    dirname(rstudioapi::getActiveDocumentContext()$path)
  } else {
    args <- commandArgs(trailingOnly = FALSE)
    f    <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
    if (length(f)) dirname(normalizePath(f)) else getwd()
  }
})
.utils <- file.path(.este_dir, "utils_mapa.R")
if (!file.exists(.utils)) {
  stop("No se encontro ", .utils, "\n",
       "Este script necesita utils_mapa.R en la misma carpeta.", call. = FALSE)
}
source(.utils)

dir_proyecto <- raiz_proyecto()
cat("Directorio del proyecto:", dir_proyecto, "\n")

dir_salida <- file.path(dir_proyecto, "Results", cuenca_nombre, "mapas")
dir.create(dir_salida, recursive = TRUE, showWarnings = FALSE)

############################################################
# 4. Shapefile de la cuenca
############################################################

ruta_shp <- file.path(dir_proyecto, "Cuenca", cuenca_nombre, archivo_shp)
if (usar_mejorado) {
  ruta_mej <- file.path(dirname(ruta_shp),
                        paste0(tools::file_path_sans_ext(basename(ruta_shp)),
                               "_mejorado.shp"))
  if (file.exists(ruta_mej)) {
    ruta_shp <- ruta_mej
    nombre_subcuenca <- "Subcuenca"   # el .Rmd renombra la columna asi
    cat("Usando shapefile reparado:", basename(ruta_shp), "\n")
  }
}
if (!file.exists(ruta_shp)) {
  stop(
    "No se encontro el shapefile:\n  ", ruta_shp, "\n\n",
    "Antes de correr este script deja tu shapefile de subcuencas en:\n",
    "  ", file.path(dir_proyecto, "Cuenca", cuenca_nombre), "\n",
    "y ajusta 'cuenca_nombre', 'archivo_shp' y 'nombre_subcuenca' en el\n",
    "bloque PARAMETROS de este script.\n\n",
    "La carpeta Cuenca/ no viene con el repositorio (esta en .gitignore):\n",
    "cada usuario aporta su propia cuenca. Ver readme_install.md.",
    call. = FALSE)
}

old_s2 <- sf::sf_use_s2()
sf::sf_use_s2(FALSE)   # operaciones topologicas planares; se restaura al final

shp <- sf::read_sf(ruta_shp)
shp <- sf::st_zm(shp, drop = TRUE, what = "ZM")
shp <- shp[!sf::st_is_empty(shp), ]

if (is.na(sf::st_crs(shp))) {
  bb <- sf::st_bbox(shp)
  if (max(abs(c(bb["xmin"], bb["xmax"]))) <= 180 &&
      max(abs(c(bb["ymin"], bb["ymax"]))) <=  90) {
    sf::st_crs(shp) <- 4326
    cat("CRS ausente: se asigno EPSG:4326\n")
  } else {
    sf::st_crs(shp) <- 32719
    cat("CRS ausente y coords proyectadas: se asigno EPSG:32719 (UTM 19S).\n")
  }
}

shp <- sf::st_make_valid(shp)

if (!nombre_subcuenca %in% names(shp)) {
  cat("Columna '", nombre_subcuenca, "' no encontrada: se crean nombres genericos.\n", sep = "")
  shp$Subcuenca <- paste0("SubC_", seq_len(nrow(shp)))
  nombre_subcuenca <- "Subcuenca"
}
shp$.nombre <- as.character(shp[[nombre_subcuenca]])

shp    <- sf::st_transform(shp, 4326)
cuenca <- sf::st_union(sf::st_geometry(shp))

# Zona UTM
cc <- sf::st_coordinates(sf::st_centroid(cuenca))
if (is.null(epsg_utm)) {
  zona     <- floor((cc[1, 1] + 180) / 6) + 1
  epsg_utm <- if (cc[1, 2] < 0) 32700 + zona else 32600 + zona
}
etq_utm <- paste0("UTM zona ", epsg_utm %% 100,
                  if (epsg_utm >= 32700) "S" else "N",
                  " - WGS 84 (EPSG:", epsg_utm, ")")

cat("Subcuencas:", nrow(shp), "|", etq_utm, "\n")

############################################################
# 5. Grilla CR2MET
############################################################

# Geometria nominal de CR2MET v2.5 (0.05 deg), usada si no hay NetCDF local
grid_res  <- 0.05
grid_xmin <- -77; grid_xmax <- -66
grid_ymin <- -57; grid_ymax <- -17
fuente_grilla <- "geometria nominal CR2MET v2.5"

if (is.null(nc_referencia)) {
  cand <- list.files(file.path(dir_proyecto, "nc_cache"), pattern = "\\.nc$",
                     recursive = TRUE, full.names = TRUE)
  nc_referencia <- if (length(cand)) cand[1] else NULL
}

if (!is.null(nc_referencia) && file.exists(nc_referencia) &&
    requireNamespace("terra", quietly = TRUE)) {
  r  <- terra::rast(nc_referencia)
  e  <- as.vector(terra::ext(r))
  rr <- terra::res(r)
  grid_res  <- rr[1]
  grid_xmin <- e[1]; grid_xmax <- e[2]
  grid_ymin <- e[3]; grid_ymax <- e[4]
  fuente_grilla <- basename(nc_referencia)
  rm(r)
}
cat("Grilla tomada de:", fuente_grilla, "| resolucion:", grid_res, "grados\n")

bb <- sf::st_bbox(shp)
i0 <- max(0, floor((bb[["xmin"]] - grid_xmin) / grid_res) - buffer_celdas)
i1 <- min((grid_xmax - grid_xmin) / grid_res - 1,
          floor((bb[["xmax"]] - grid_xmin) / grid_res) + buffer_celdas)
j0 <- max(0, floor((bb[["ymin"]] - grid_ymin) / grid_res) - buffer_celdas)
j1 <- min((grid_ymax - grid_ymin) / grid_res - 1,
          floor((bb[["ymax"]] - grid_ymin) / grid_res) + buffer_celdas)

celdas <- sf::st_make_grid(
  cuenca,
  cellsize = c(grid_res, grid_res),
  offset   = c(grid_xmin + i0 * grid_res, grid_ymin + j0 * grid_res),
  n        = c(i1 - i0 + 1, j1 - j0 + 1)
)
grilla <- sf::st_sf(celda = seq_along(celdas), geometry = celdas, crs = 4326)

# ---- Fraccion de area cubierta (peso de exact = TRUE), calculada en UTM ----
grilla_utm <- sf::st_transform(grilla, epsg_utm)
cuenca_utm <- sf::st_transform(cuenca, epsg_utm)

area_celda <- as.numeric(sf::st_area(grilla_utm))
inter      <- suppressWarnings(sf::st_intersection(grilla_utm, cuenca_utm))

frac <- rep(0, nrow(grilla))
if (nrow(inter) > 0) {
  a_int <- tapply(as.numeric(sf::st_area(inter)), inter$celda, sum)
  idx   <- as.integer(names(a_int))
  frac[idx] <- pmin(1, as.numeric(a_int) / area_celda[idx])
}
grilla$frac_pct <- 100 * frac

# ---- Centroides (regla "centroid-in") ----
centro <- suppressWarnings(sf::st_centroid(grilla))
centro$dentro <- lengths(sf::st_intersects(centro, cuenca)) > 0
centro$dentro <- factor(ifelse(centro$dentro, "dentro", "fuera"),
                        levels = c("dentro", "fuera"))

# ---- Resumen ----
n_inter  <- sum(frac > 0)
n_centro <- sum(centro$dentro == "dentro")
area_km2 <- as.numeric(sum(sf::st_area(cuenca_utm))) / 1e6
res_km   <- grid_res * 111.32

cat("\n--- Resumen grilla ---\n")
cat("Area de la cuenca             :", round(area_km2, 1), "km2\n")
cat("Celdas que intersectan        :", n_inter, "\n")
cat("Celdas con centroide dentro   :", n_centro, "\n")
cat("Diferencia (sesgo centroid-in):", n_inter - n_centro, "celdas\n")
cat("Suma de fracciones de area    :", round(sum(frac), 2),
    "celdas equivalentes\n\n")

if (exportar_grilla) {
  gpkg <- file.path(dir_salida, paste0("grilla_CR2Met_", cuenca_nombre, ".gpkg"))
  suppressWarnings(sf::st_write(grilla, gpkg, delete_dsn = TRUE, quiet = TRUE))
  cat("Grilla exportada:", gpkg, "\n")
}

############################################################
# 6. Constructor del mapa
############################################################

pie_mapa <- paste0(
  "CR2MET v2.5 - celda ", .fmt(grid_res), " grados (~", .fmt(round(res_km, 1)),
  " km) | ", n_inter, " celdas intersectan la cuenca (",
  n_centro, " con centroide dentro) | area ", .fmt(round(area_km2, 1)), " km2\n",
  "Relleno = fraccion de celda cubierta por la cuenca, el mismo peso que usa ",
  "terra::extract(..., exact = TRUE)")

construir_mapa <- function(crs_destino, subtitulo, unidad_por_km,
                           eje_x, eje_y, fmt_eje = NULL) {

  g_grilla <- sf::st_transform(grilla, crs_destino)
  g_shp    <- sf::st_transform(shp,    crs_destino)
  g_cuenca <- sf::st_transform(cuenca, crs_destino)
  g_centro <- sf::st_transform(centro, crs_destino)

  bbg  <- sf::st_bbox(g_grilla)
  rx   <- bbg[["xmax"]] - bbg[["xmin"]]
  ry   <- bbg[["ymax"]] - bbg[["ymin"]]
  xlim <- c(bbg[["xmin"]] - 0.02 * rx, bbg[["xmax"]] + 0.02 * rx)
  ylim <- c(bbg[["ymin"]] - 0.02 * ry, bbg[["ymax"]] + 0.10 * ry)

  cubiertas <- g_grilla[g_grilla$frac_pct > 0, ]
  vacias    <- g_grilla[g_grilla$frac_pct == 0, ]

  p <- ggplot() +
    geom_sf(data = vacias, fill = "grey97", colour = "grey70", linewidth = 0.15) +
    geom_sf(data = cubiertas, aes(fill = frac_pct),
            colour = "grey45", linewidth = 0.2)

  if (mostrar_centroides) {
    pts <- if (centroides_solo_uso) g_centro[g_centro$frac_pct > 0, ] else g_centro
    p <- p + geom_sf(data = pts, aes(shape = dentro),
                     colour = "grey20", size = 1.2, stroke = 0.45)
  }

  p <- p +
    geom_sf(data = g_shp, aes(colour = "Subcuencas"),
            fill = NA, linewidth = 0.35, show.legend = "line") +
    geom_sf(data = sf::st_sf(geometry = g_cuenca), aes(colour = "Cuenca"),
            fill = NA, linewidth = 0.8, show.legend = "line")

  if (etiquetar_celdas) {
    p <- p + geom_sf_text(data = cubiertas, aes(label = round(frac_pct)),
                          size = 1.8, colour = "grey20")
  }

  if (etiquetar_subcuencas) {
    ctr <- suppressWarnings(sf::st_point_on_surface(g_shp))
    if (requireNamespace("ggrepel", quietly = TRUE)) {
      p <- p + ggrepel::geom_text_repel(
        data = ctr, aes(label = .nombre, geometry = geometry),
        stat = "sf_coordinates", size = 2.4, colour = "grey10",
        bg.color = "white", bg.r = 0.12, min.segment.length = 0.2,
        segment.size = 0.2, max.overlaps = 30)
    } else {
      p <- p + geom_sf_text(data = ctr, aes(label = .nombre),
                            size = 2.4, colour = "grey10", check_overlap = TRUE)
    }
  }

  p <- p +
    capa_escala(xlim, ylim, unidad_por_km, pos = pos_escala) +
    capa_norte(xlim, ylim, pos = pos_norte) +
    scale_fill_viridis_c(
      name = "Fraccion de celda\ncubierta (%)",
      option = "D", direction = -1, limits = c(0, 100),
      breaks = seq(0, 100, 25)) +
    scale_colour_manual(
      name = NULL,
      values = c("Cuenca" = "black", "Subcuencas" = "grey30")) +
    scale_shape_manual(
      name = "Centroide de celda",
      values = c("dentro" = 3, "fuera" = 4),
      labels = c("dentro" = "dentro de la cuenca",
                 "fuera"  = "fuera de la cuenca")) +
    coord_sf(crs = crs_destino, datum = crs_destino,
             xlim = xlim, ylim = ylim, expand = FALSE) +
    labs(title    = paste0("Grilla CR2MET v2.5 sobre ", cuenca_nombre),
         subtitle = subtitulo,
         x = eje_x, y = eje_y,
         caption  = pie_mapa) +
    guides(
      colour = guide_legend(order = 1,
                            override.aes = list(linewidth = c(0.9, 0.4))),
      shape  = guide_legend(order = 2),
      fill   = guide_colourbar(order = 3, barheight = grid::unit(28, "mm"))) +
    theme_bw(base_size = 10) +
    theme(
      panel.grid        = element_line(colour = "grey88", linewidth = 0.2),
      panel.border      = element_rect(colour = "grey20", linewidth = 0.5, fill = NA),
      plot.title        = element_text(face = "bold", size = 12),
      plot.subtitle     = element_text(colour = "grey30", size = 9),
      plot.caption      = element_text(colour = "grey35", size = 7, hjust = 0),
      legend.key        = element_rect(fill = "white", colour = NA),
      legend.background = element_blank(),
      axis.text         = element_text(size = 7.5))

  if (!is.null(fmt_eje)) {
    p <- p + scale_x_continuous(labels = fmt_eje$x) +
             scale_y_continuous(labels = fmt_eje$y)
  }

  list(plot = p, xlim = xlim, ylim = ylim)
}

############################################################
# 7. Mapa (a): lat/lon WGS 84
############################################################

# Grados de longitud equivalentes a 1 km, medidos en la latitud central
lat_c <- mean(sf::st_bbox(grilla)[c("ymin", "ymax")])
lon_c <- mean(sf::st_bbox(grilla)[c("xmin", "xmax")])
km_por_grado <- as.numeric(sf::st_distance(
  sf::st_sfc(sf::st_point(c(lon_c,     lat_c)), crs = 4326),
  sf::st_sfc(sf::st_point(c(lon_c + 1, lat_c)), crs = 4326))) / 1000
grados_por_km <- 1 / km_por_grado

fmt_lon <- function(x) paste0(.fmt(round(abs(x), 2)), "°", ifelse(x < 0, "O", "E"))
fmt_lat <- function(y) paste0(.fmt(round(abs(y), 2)), "°", ifelse(y < 0, "S", "N"))

m_geo <- construir_mapa(
  crs_destino   = 4326,
  subtitulo     = "Coordenadas geograficas - WGS 84 (EPSG:4326)",
  unidad_por_km = grados_por_km,
  eje_x = "Longitud", eje_y = "Latitud",
  fmt_eje = list(x = fmt_lon, y = fmt_lat))

asp_geo  <- diff(m_geo$ylim) / (diff(m_geo$xlim) * cos(lat_c * pi / 180))
alto_geo <- min(30, max(10, ancho_cm * asp_geo * 0.80 + 3))

f_geo <- file.path(dir_salida, paste0("grilla_CR2Met_", cuenca_nombre, "_latlon.png"))
ggsave(f_geo, m_geo$plot, width = ancho_cm, height = alto_geo,
       units = "cm", dpi = dpi_out, bg = "white")
cat("Mapa lat/lon:", f_geo, "\n")

############################################################
# 8. Mapa (b): UTM
############################################################

fmt_km <- function(v) .fmt(round(v / 1000))

m_utm <- construir_mapa(
  crs_destino   = epsg_utm,
  subtitulo     = paste0("Coordenadas proyectadas - ", etq_utm),
  unidad_por_km = 1000,
  eje_x = "Este UTM (km)", eje_y = "Norte UTM (km)",
  fmt_eje = list(x = fmt_km, y = fmt_km))

asp_utm  <- diff(m_utm$ylim) / diff(m_utm$xlim)
alto_utm <- min(30, max(10, ancho_cm * asp_utm * 0.80 + 3))

f_utm <- file.path(dir_salida, paste0("grilla_CR2Met_", cuenca_nombre, "_UTM.png"))
ggsave(f_utm, m_utm$plot, width = ancho_cm, height = alto_utm,
       units = "cm", dpi = dpi_out, bg = "white")
cat("Mapa UTM    :", f_utm, "\n")

############################################################
# 9. Cierre
############################################################

sf::sf_use_s2(old_s2)
cat("\nListo. Salidas en:", dir_salida, "\n")
