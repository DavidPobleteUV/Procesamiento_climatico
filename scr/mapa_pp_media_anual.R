############################################################
# Precipitacion media anual por celda CR2MET sobre la cuenca
#
# Calcula, celda a celda, la precipitacion media anual del periodo y la
# dibuja sobre la cuenca en dos mapas:
#   (a) coordenadas geograficas  -> WGS 84 lat/lon (EPSG:4326)
#   (b) coordenadas proyectadas  -> UTM (zona inferida del centroide)
#
# Ambos con escala grafica en km, flecha de norte y leyenda por clases
# (tipo mapa de isoyetas) en mm/ano.
#
# A diferencia de series_anuales_decadales.R, que promedia sobre la cuenca
# y muestra la evolucion en el tiempo, este script no promedia en el
# espacio: muestra el gradiente orografico dentro de la cuenca.
#
# Fuente: los NetCDF diarios cacheados en nc_cache/pr/ por el .Rmd de
# extraccion. Solo se usan los anos con los 12 meses disponibles.
#
# Autores: Simon Caneo & David Poblete - EIC, Universidad de Valparaiso
# Licencia: GPL v3
#
# Uso:
#   - En RStudio: abrir y ejecutar (Source).
#   - Desde consola:  Rscript scr/mapa_pp_media_anual.R
############################################################

options(scipen = 999)

############################################################
# 1. Librerias
############################################################

.paquetes <- c("sf", "terra", "ggplot2", "dplyr")
.faltan   <- .paquetes[!vapply(.paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(.faltan)) {
  stop("Faltan paquetes: install.packages(c(\"",
       paste(.faltan, collapse = "\", \""), "\"))")
}

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(ggplot2)
  library(dplyr)
})

############################################################
# 2. PARAMETROS  <-- LO UNICO QUE HAY QUE EDITAR
############################################################

cuenca_nombre    <- "Aconcagua_catchments2026"        # carpeta dentro de Cuenca/
archivo_shp      <- "Aconcagua_catchments2026.shp"    # shapefile de subcuencas
nombre_subcuenca <- "Catchments"                      # columna con el nombre de cada subcuenca
usar_mejorado    <- TRUE

# Periodo. NULL = todos los anos completos disponibles en nc_cache/pr/
anios <- NULL

# Ano hidrologico (Chile: abril a marzo). El ano se etiqueta por el de inicio.
anio_hidrologico <- TRUE
mes_inicio       <- 4

# Celdas extra dibujadas alrededor del bounding box de la cuenca
buffer_celdas <- 2

# EPSG proyectado. NULL = zona UTM inferida desde el centroide
epsg_utm <- NULL

# Opciones de dibujo
n_clases             <- 8      # numero de clases de la leyenda
etiquetar_celdas     <- FALSE  # escribir el valor dentro de cada celda
etiquetar_subcuencas <- TRUE
atenuar_fuera        <- TRUE   # bajar la opacidad de las celdas fuera de la cuenca
exportar_gpkg        <- TRUE

# Posicion de escala y norte, en fraccion del ancho/alto del panel
pos_escala <- c(0.03, 0.04)
pos_norte  <- c(0.94, 0.82)

# Salida
ancho_cm <- 20
dpi_out  <- 300

############################################################
# 3. Directorio del proyecto y helpers cartograficos
############################################################

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
    nombre_subcuenca <- "Subcuenca"
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
sf::sf_use_s2(FALSE)

shp <- sf::read_sf(ruta_shp)
shp <- sf::st_zm(shp, drop = TRUE, what = "ZM")
shp <- shp[!sf::st_is_empty(shp), ]

if (is.na(sf::st_crs(shp))) {
  bb <- sf::st_bbox(shp)
  if (max(abs(c(bb["xmin"], bb["xmax"]))) <= 180 &&
      max(abs(c(bb["ymin"], bb["ymax"]))) <=  90) {
    sf::st_crs(shp) <- 4326
  } else {
    sf::st_crs(shp) <- 32719
  }
}

shp <- sf::st_make_valid(shp)
if (!nombre_subcuenca %in% names(shp)) {
  shp$Subcuenca <- paste0("SubC_", seq_len(nrow(shp)))
  nombre_subcuenca <- "Subcuenca"
}
shp$.nombre <- as.character(shp[[nombre_subcuenca]])

shp    <- sf::st_transform(shp, 4326)
cuenca <- sf::st_union(sf::st_geometry(shp))

cc <- sf::st_coordinates(sf::st_centroid(cuenca))
if (is.null(epsg_utm)) {
  zona     <- floor((cc[1, 1] + 180) / 6) + 1
  epsg_utm <- if (cc[1, 2] < 0) 32700 + zona else 32600 + zona
}
etq_utm <- paste0("UTM zona ", epsg_utm %% 100,
                  if (epsg_utm >= 32700) "S" else "N",
                  " - WGS 84 (EPSG:", epsg_utm, ")")

############################################################
# 5. Inventario de NetCDF de precipitacion
############################################################

dir_pr <- file.path(dir_proyecto, "nc_cache", "pr")
fs <- list.files(dir_pr, pattern = "\\.nc$", full.names = TRUE)
if (!length(fs)) {
  stop(
    "No hay NetCDF de precipitacion en:\n  ", dir_pr, "\n\n",
    "Este script se alimenta del cache que deja el .Rmd de extraccion.\n",
    "Corre primero CR2Met_bestday_extraccion_...Rmd.\n",
    "Ver el orden de ejecucion en README.md.",
    call. = FALSE)
}

m <- regmatches(basename(fs),
                regexec("_(\\d{4})_(\\d{2})_005deg\\.nc$", basename(fs)))
ok <- lengths(m) == 3
inv <- data.frame(
  archivo = fs[ok],
  anio_cal = as.integer(vapply(m[ok], `[`, character(1), 2)),
  mes      = as.integer(vapply(m[ok], `[`, character(1), 3)),
  stringsAsFactors = FALSE)

inv$anio <- if (anio_hidrologico) {
  ifelse(inv$mes >= mes_inicio, inv$anio_cal, inv$anio_cal - 1L)
} else inv$anio_cal

# Solo anos con los 12 meses: un ano truncado subestimaria la media anual
completos <- inv %>% count(anio) %>% filter(n == 12) %>% pull(anio)
if (!is.null(anios)) completos <- intersect(completos, anios)
if (!length(completos)) {
  stop("No hay ningun ano completo (12 meses) en ", dir_pr,
       if (!is.null(anios)) " dentro del rango pedido." else ".", call. = FALSE)
}
inv <- filter(inv, anio %in% completos)

.meses <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
            "agosto", "septiembre", "octubre", "noviembre", "diciembre")
etq_anio <- if (anio_hidrologico) {
  paste0("año hidrológico (", .meses[mes_inicio], "-",
         .meses[(mes_inicio + 10) %% 12 + 1], ")")
} else "año calendario"

periodo <- paste0(min(completos), "-", max(completos))
cat("Periodo:", periodo, "|", length(completos), "años completos |",
    nrow(inv), "archivos NetCDF\n")

############################################################
# 6. Precipitacion media anual celda a celda
############################################################

# Ventana de trabajo: bbox de la cuenca mas el buffer de celdas
r0        <- terra::rast(inv$archivo[1])
res_grid  <- terra::res(r0)[1]
bb        <- sf::st_bbox(shp)
ventana   <- terra::ext(
  bb[["xmin"]] - buffer_celdas * res_grid, bb[["xmax"]] + buffer_celdas * res_grid,
  bb[["ymin"]] - buffer_celdas * res_grid, bb[["ymax"]] + buffer_celdas * res_grid)
ventana   <- terra::intersect(ventana, terra::ext(r0))
rm(r0)

cat("Acumulando", nrow(inv), "archivos (recorte a la ventana de la cuenca)...\n")

acumulado <- NULL
paso <- max(1, floor(nrow(inv) / 20))
for (i in seq_len(nrow(inv))) {
  r <- terra::rast(inv$archivo[i])
  r <- terra::crop(r, ventana)
  # Total mensual de la celda: suma de las capas diarias del archivo
  tot <- terra::app(r, fun = sum, na.rm = TRUE)
  acumulado <- if (is.null(acumulado)) tot else acumulado + tot
  if (i %% paso == 0 || i == nrow(inv)) {
    cat(sprintf("\r  %d/%d (%.0f%%)", i, nrow(inv), 100 * i / nrow(inv)))
    flush.console()
  }
}
cat("\n")

# Media anual = total acumulado / numero de anos completos
pp_media <- acumulado / length(completos)
names(pp_media) <- "pp_mm_anio"

# Celdas -> poligonos, para dibujar igual en lat/lon y en UTM
celdas <- sf::st_as_sf(terra::as.polygons(pp_media, dissolve = FALSE,
                                          values = TRUE, na.rm = FALSE))
names(celdas)[1] <- "pp"
sf::st_crs(celdas) <- 4326
celdas <- celdas[!is.na(celdas$pp), ]
celdas$celda <- seq_len(nrow(celdas))

# Que celdas tocan la cuenca (para el resumen y el atenuado)
celdas$en_cuenca <- lengths(sf::st_intersects(celdas, cuenca)) > 0

# ---- Resumen ----
dentro <- celdas$pp[celdas$en_cuenca]
cat("\n--- Precipitacion media anual |", cuenca_nombre, "|", periodo, "---\n")
cat("Celdas que tocan la cuenca :", sum(celdas$en_cuenca), "\n")
cat("Minimo                     :", round(min(dentro)), "mm/año\n")
cat("Maximo                     :", round(max(dentro)), "mm/año\n")
cat("Mediana                    :", round(median(dentro)), "mm/año\n")
cat("Razon max/min              :", round(max(dentro) / min(dentro), 1), "\n\n")

if (exportar_gpkg) {
  gpkg <- file.path(dir_salida, paste0("pp_media_anual_", cuenca_nombre, ".gpkg"))
  suppressWarnings(sf::st_write(celdas, gpkg, delete_dsn = TRUE, quiet = TRUE))
  cat("Celdas exportadas:", gpkg, "\n")
}

############################################################
# 7. Clases de la leyenda
############################################################

# Cortes redondos que cubren todo el rango dibujado
rango  <- range(celdas$pp)
paso_c <- .num_bonito(diff(rango) / n_clases)
cortes <- seq(floor(rango[1] / paso_c) * paso_c,
              ceiling(rango[2] / paso_c) * paso_c, by = paso_c)

# Rampa tipo isoyetas: seco (ocre) -> humedo (azul oscuro)
rampa <- colorRampPalette(
  c("#F7E9A0", "#D9EF8B", "#A6D96A", "#66C2A5", "#41B6C4",
    "#3690C0", "#2166AC", "#253494", "#141E5E"))(length(cortes) - 1)

############################################################
# 8. Constructor del mapa
############################################################

pie_mapa <- paste0(
  "Fuente: CR2MET v2.5 (celda ", .fmt(res_grid), " grados, ~",
  .fmt(round(res_grid * 111.32, 1)), " km) · ", periodo, " · ",
  length(completos), " años completos · ", etq_anio, "\n",
  "Cada celda es la precipitación media anual de esa celda, sin promediar ",
  "en el espacio: dentro de la cuenca el rango va de ",
  .fmt(round(min(dentro))), " a ", .fmt(round(max(dentro))), " mm/año (razón ",
  .fmt(round(max(dentro) / min(dentro), 1)), " a 1).")

construir_mapa <- function(crs_destino, subtitulo, unidad_por_km,
                           eje_x, eje_y, fmt_eje = NULL) {

  g_celdas <- sf::st_transform(celdas, crs_destino)
  g_shp    <- sf::st_transform(shp,    crs_destino)
  g_cuenca <- sf::st_transform(cuenca, crs_destino)

  bbg  <- sf::st_bbox(g_celdas)
  rx   <- bbg[["xmax"]] - bbg[["xmin"]]
  ry   <- bbg[["ymax"]] - bbg[["ymin"]]
  xlim <- c(bbg[["xmin"]] - 0.02 * rx, bbg[["xmax"]] + 0.02 * rx)
  ylim <- c(bbg[["ymin"]] - 0.02 * ry, bbg[["ymax"]] + 0.10 * ry)

  p <- ggplot()

  if (atenuar_fuera) {
    p <- p +
      geom_sf(data = g_celdas[!g_celdas$en_cuenca, ], aes(fill = pp),
              colour = "grey80", linewidth = 0.1, alpha = 0.45) +
      geom_sf(data = g_celdas[g_celdas$en_cuenca, ], aes(fill = pp),
              colour = "grey55", linewidth = 0.15)
  } else {
    p <- p + geom_sf(data = g_celdas, aes(fill = pp),
                     colour = "grey65", linewidth = 0.12)
  }

  if (etiquetar_celdas) {
    p <- p + geom_sf_text(data = g_celdas[g_celdas$en_cuenca, ],
                          aes(label = round(pp)),
                          size = 1.6, colour = "grey15")
  }

  p <- p +
    geom_sf(data = g_shp, aes(colour = "Subcuencas"),
            fill = NA, linewidth = 0.3, show.legend = "line") +
    geom_sf(data = sf::st_sf(geometry = g_cuenca), aes(colour = "Cuenca"),
            fill = NA, linewidth = 0.9, show.legend = "line")

  if (etiquetar_subcuencas) {
    ctr <- suppressWarnings(sf::st_point_on_surface(g_shp))
    if (requireNamespace("ggrepel", quietly = TRUE)) {
      p <- p + ggrepel::geom_text_repel(
        data = ctr, aes(label = .nombre, geometry = geometry),
        stat = "sf_coordinates", size = 2.2, colour = "grey10",
        bg.color = "white", bg.r = 0.15, min.segment.length = 0.2,
        segment.size = 0.2, max.overlaps = 30)
    } else {
      p <- p + geom_sf_text(data = ctr, aes(label = .nombre),
                            size = 2.2, colour = "grey10", check_overlap = TRUE)
    }
  }

  p <- p +
    capa_escala(xlim, ylim, unidad_por_km, pos = pos_escala) +
    capa_norte(xlim, ylim, pos = pos_norte) +
    scale_fill_stepsn(
      name    = "Precipitación\nmedia anual\n(mm/año)",
      colours = rampa,
      breaks  = cortes,
      limits  = range(cortes),
      guide   = guide_coloursteps(show.limits = TRUE, even.steps = TRUE,
                                  order = 3)) +
    scale_colour_manual(
      name = NULL,
      values = c("Cuenca" = "black", "Subcuencas" = "grey25")) +
    coord_sf(crs = crs_destino, datum = crs_destino,
             xlim = xlim, ylim = ylim, expand = FALSE) +
    labs(title    = paste0("Precipitación media anual por celda CR2MET — ",
                           cuenca_nombre),
         subtitle = subtitulo,
         x = eje_x, y = eje_y, caption = pie_mapa) +
    guides(colour = guide_legend(
      order = 1, override.aes = list(linewidth = c(1, 0.4)))) +
    theme_bw(base_size = 10) +
    theme(
      panel.grid        = element_line(colour = "grey88", linewidth = 0.2),
      panel.border      = element_rect(colour = "grey20", linewidth = 0.5, fill = NA),
      plot.title        = element_text(face = "bold", size = 12),
      plot.subtitle     = element_text(colour = "grey30", size = 9),
      plot.caption      = element_text(colour = "grey35", size = 7, hjust = 0),
      legend.key        = element_rect(fill = "white", colour = NA),
      legend.background = element_blank(),
      legend.title      = element_text(size = 8.5),
      legend.key.height = grid::unit(7, "mm"),
      legend.key.width  = grid::unit(4.5, "mm"),
      axis.text         = element_text(size = 7.5))

  if (!is.null(fmt_eje)) {
    p <- p + scale_x_continuous(labels = fmt_eje$x) +
             scale_y_continuous(labels = fmt_eje$y)
  }

  list(plot = p, xlim = xlim, ylim = ylim)
}

############################################################
# 9. Mapa (a): lat/lon WGS 84
############################################################

lat_c <- mean(sf::st_bbox(celdas)[c("ymin", "ymax")])
lon_c <- mean(sf::st_bbox(celdas)[c("xmin", "xmax")])
km_por_grado <- as.numeric(sf::st_distance(
  sf::st_sfc(sf::st_point(c(lon_c,     lat_c)), crs = 4326),
  sf::st_sfc(sf::st_point(c(lon_c + 1, lat_c)), crs = 4326))) / 1000

fmt_lon <- function(x) paste0(.fmt(round(abs(x), 2)), "°", ifelse(x < 0, "O", "E"))
fmt_lat <- function(y) paste0(.fmt(round(abs(y), 2)), "°", ifelse(y < 0, "S", "N"))

m_geo <- construir_mapa(
  crs_destino   = 4326,
  subtitulo     = "Coordenadas geográficas - WGS 84 (EPSG:4326)",
  unidad_por_km = 1 / km_por_grado,
  eje_x = "Longitud", eje_y = "Latitud",
  fmt_eje = list(x = fmt_lon, y = fmt_lat))

asp_geo  <- diff(m_geo$ylim) / (diff(m_geo$xlim) * cos(lat_c * pi / 180))
alto_geo <- min(30, max(10, ancho_cm * asp_geo * 0.80 + 3))

f_geo <- file.path(dir_salida, paste0("pp_media_anual_", cuenca_nombre, "_latlon.png"))
ggsave(f_geo, m_geo$plot, width = ancho_cm, height = alto_geo,
       units = "cm", dpi = dpi_out, bg = "white")
cat("Mapa lat/lon:", f_geo, "\n")

############################################################
# 10. Mapa (b): UTM
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

f_utm <- file.path(dir_salida, paste0("pp_media_anual_", cuenca_nombre, "_UTM.png"))
ggsave(f_utm, m_utm$plot, width = ancho_cm, height = alto_utm,
       units = "cm", dpi = dpi_out, bg = "white")
cat("Mapa UTM    :", f_utm, "\n")

############################################################
# 11. Cierre
############################################################

sf::sf_use_s2(old_s2)
cat("\nListo. Salidas en:", dir_salida, "\n")
