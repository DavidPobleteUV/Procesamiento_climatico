############################################################
# utils_mapa.R - Helpers compartidos por los scripts de mapas
#
# Lo cargan con source():
#   - scr/mapa_grilla_CR2Met.R
#   - scr/mapa_pp_media_anual.R
#
# Contiene la localizacion de la raiz del proyecto y las capas
# cartograficas (barra de escala en km y flecha de norte) escritas
# como capas annotate() propias, sin depender de ggspatial.
#
# Autores: Simon Caneo & David Poblete - EIC, Universidad de Valparaiso
# Licencia: GPL v3
############################################################

############################################################
# Localizacion del proyecto
############################################################

.buscar_raiz <- function(inicio) {
  d <- normalizePath(inicio, winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (dir.exists(file.path(d, "Cuenca"))) return(d)
    padre <- dirname(d)
    if (identical(padre, d)) break
    d <- padre
  }
  NA_character_
}

# Carpeta donde vive este script (RStudio o Rscript)
.dir_script <- function() {
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable() &&
      nzchar(rstudioapi::getActiveDocumentContext()$path)) {
    return(dirname(rstudioapi::getActiveDocumentContext()$path))
  }
  args <- commandArgs(trailingOnly = FALSE)
  f    <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
  if (length(f)) dirname(normalizePath(f)) else getwd()
}

# Raiz del proyecto: busca hacia arriba una carpeta con Cuenca/, luego
# desde la carpeta del script, y si aun no aparece (clon recien bajado,
# sin Cuenca/) asume el padre de scr/.
raiz_proyecto <- function() {
  d <- .buscar_raiz(getwd())
  if (is.na(d)) d <- .buscar_raiz(.dir_script())
  if (is.na(d)) d <- normalizePath(file.path(.dir_script(), ".."),
                                   winslash = "/", mustWork = FALSE)
  d
}

############################################################
# Capas cartograficas
############################################################

# Redondea a un numero "bonito": 1, 2, 5 x 10^k
.num_bonito <- function(x) {
  p <- 10^floor(log10(x))
  f <- x / p
  m <- if (f < 1.5) 1 else if (f < 3.5) 2 else if (f < 7.5) 5 else 10
  m * p
}

# Formato con coma decimal
.fmt <- function(v) sub("\\.", ",", format(v, trim = TRUE, scientific = FALSE))

# Barra de escala en km.
#   unidad_por_km: cuantas unidades del CRS equivalen a 1 km
#                  (1000 en UTM; grados de longitud por km en lat/lon)
capa_escala <- function(xlim, ylim, unidad_por_km,
                        pos = c(0.03, 0.04), frac_ancho = 0.26,
                        alto_frac = 0.014, n_div = 4, tam_texto = 2.9) {

  rx <- diff(xlim); ry <- diff(ylim)
  largo_km <- .num_bonito(frac_ancho * rx / unidad_por_km)
  largo_u  <- largo_km * unidad_por_km

  x0 <- xlim[1] + pos[1] * rx
  y0 <- ylim[1] + pos[2] * ry
  h  <- alto_frac * ry

  brk <- seq(0, largo_u, length.out = n_div + 1)
  idx <- c(1, n_div / 2 + 1, n_div + 1)
  etq <- c(.fmt(0), .fmt(largo_km / 2), paste0(.fmt(largo_km), " km"))

  list(
    # recuadro blanco de fondo, para que la escala se lea sobre la grilla
    annotate("rect",
             xmin = x0 - 0.030 * rx, xmax = x0 + largo_u + 0.055 * rx,
             ymin = y0 - 0.020 * ry, ymax = y0 + h + 0.055 * ry,
             fill = "white", colour = "grey60", linewidth = 0.2, alpha = 0.85),
    annotate("rect",
             xmin = x0 + brk[-(n_div + 1)], xmax = x0 + brk[-1],
             ymin = y0, ymax = y0 + h,
             fill = rep(c("grey15", "white"), length.out = n_div),
             colour = "grey15", linewidth = 0.25),
    annotate("text",
             x = x0 + brk[idx], y = y0 + h + 0.010 * ry,
             label = etq, vjust = 0, size = tam_texto, colour = "grey15")
  )
}

# Flecha de norte clasica (dos mitades, blanca y negra)
capa_norte <- function(xlim, ylim, pos = c(0.94, 0.82),
                       ancho_frac = 0.035, alto_frac = 0.075, tam_texto = 3.2) {

  rx <- diff(xlim); ry <- diff(ylim)
  cx <- xlim[1] + pos[1] * rx
  cy <- ylim[1] + pos[2] * ry
  w  <- ancho_frac * rx
  h  <- alto_frac  * ry

  list(
    # recuadro blanco de fondo
    annotate("rect",
             xmin = cx - 0.75 * w, xmax = cx + 0.75 * w,
             ymin = cy - 0.10 * h, ymax = cy + 1.55 * h,
             fill = "white", colour = "grey60", linewidth = 0.2, alpha = 0.85),
    annotate("polygon",
             x = c(cx, cx - w / 2, cx), y = c(cy + h, cy, cy + 0.30 * h),
             fill = "white", colour = "grey15", linewidth = 0.3),
    annotate("polygon",
             x = c(cx, cx + w / 2, cx), y = c(cy + h, cy, cy + 0.30 * h),
             fill = "grey15", colour = "grey15", linewidth = 0.3),
    annotate("text", x = cx, y = cy + h + 0.015 * ry,
             label = "N", vjust = 0, fontface = 2,
             size = tam_texto, colour = "grey15")
  )
}
