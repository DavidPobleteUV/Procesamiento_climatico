############################################################
# Series anuales y promedios decadales a partir de CR2MET
#
# Lee los CSV MENSUALES generados por el .Rmd de extraccion y produce:
#   (a) series anuales por variable, con el promedio de cada decada
#       superpuesto y el periodo de megasequia sombreado
#   (b) cambio de cada decada respecto a la primera, para leer la senal
#       de golpe (% en precipitacion, delta grados C en temperaturas)
#   (c) las tablas anuales y decadales en CSV
#
# La agregacion espacial es un promedio PONDERADO POR AREA de las
# subcuencas (area_ha del shapefile _mejorado), no un promedio simple:
# en una cuenca con subcuencas de tamano muy distinto el promedio simple
# sobrerrepresenta a las chicas.
#
# NOTA: CR2MET no entrega caudales. Este script cubre precipitacion,
# temperaturas y evapotranspiracion de referencia.
#
# Autores: Simon Caneo & David Poblete - EIC, Universidad de Valparaiso
# Licencia: GPL v3
#
# Uso:
#   - En RStudio: abrir y ejecutar (Source).
#   - Desde consola:  Rscript scr/series_anuales_decadales.R
############################################################

options(scipen = 999)

############################################################
# 1. Librerias
############################################################

.paquetes <- c("ggplot2", "dplyr", "tidyr")
.faltan   <- .paquetes[!vapply(.paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(.faltan)) {
  stop("Faltan paquetes: install.packages(c(\"",
       paste(.faltan, collapse = "\", \""), "\"))")
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

############################################################
# 2. PARAMETROS  <-- LO UNICO QUE HAY QUE EDITAR
############################################################

cuenca_nombre <- "Aconcagua_catchments2026"   # carpeta dentro de Results/

# Variables a graficar. Disponibles: "pp", "tav", "tn", "tx", "et0"
variables <- c("pp", "tav", "tn", "tx")

# Subcuencas a incluir. NULL = todas (promedio areal de la cuenca completa).
# Ej.: c("CE1", "CE4") para un subconjunto.
subcuencas <- NULL

# Promedio ponderado por area_ha del shapefile _mejorado.
# Si no se encuentra el shapefile, cae a promedio simple avisando.
ponderar_por_area <- TRUE

# Ano hidrologico (Chile: abril a marzo) en vez de ano calendario.
# El ano se etiqueta por el ano de inicio: 2010 = abr 2010 a mar 2011.
anio_hidrologico <- TRUE
mes_inicio       <- 4

# Descartar anos sin los 12 meses. Imprescindible: la serie termina a
# mitad de ano y un ano truncado se veria como una sequia inexistente.
solo_anios_completos <- TRUE

# Decadas con menos anos que esto no se dibujan (evita "decadas" de 1-2 anos)
decada_min_anios <- 5

# Inicio de la megasequia para el sombreado (Garreaud et al., 2017)
inicio_megasequia <- 2010

# Salida
ancho_cm <- 24
dpi_out  <- 300

############################################################
# 3. Directorio del proyecto
############################################################

.buscar_raiz <- function(inicio) {
  d <- normalizePath(inicio, winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    if (dir.exists(file.path(d, "Results"))) return(d)
    padre <- dirname(d)
    if (identical(padre, d)) break
    d <- padre
  }
  NA_character_
}

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

dir_proyecto <- .buscar_raiz(getwd())
if (is.na(dir_proyecto)) dir_proyecto <- .buscar_raiz(.dir_script())
if (is.na(dir_proyecto)) {
  dir_proyecto <- normalizePath(file.path(.dir_script(), ".."),
                                winslash = "/", mustWork = FALSE)
}

dir_datos <- file.path(dir_proyecto, "Results", cuenca_nombre)
if (!dir.exists(dir_datos)) {
  stop(
    "No se encontro la carpeta de resultados:\n  ", dir_datos, "\n\n",
    "Este script consume los CSV mensuales que produce el .Rmd de extraccion.\n",
    "Corre primero CR2Met_bestday_extraccion_...Rmd para la cuenca '",
    cuenca_nombre, "'.\n",
    "Ver el orden de ejecucion en README.md.",
    call. = FALSE)
}

dir_salida <- file.path(dir_datos, "series")
dir.create(dir_salida, recursive = TRUE, showWarnings = FALSE)
cat("Directorio del proyecto:", dir_proyecto, "\n")

############################################################
# 4. Metadatos de las variables
############################################################

# 'corto' se usa en la figura de cambio decadal: el texto del eje va rotado
# dentro de un panel bajo, y los nombres largos se cortan.
meta <- list(
  pp  = list(etiqueta = "Precipitación",       corto = "Precipitación",
             unidad = "mm/año", agg = "sum",  dec = 0, color = "#1F6FB4"),
  tav = list(etiqueta = "Temperatura media",   corto = "T. media",
             unidad = "°C",     agg = "mean", dec = 1, color = "#C0392B"),
  tn  = list(etiqueta = "Temperatura mínima",  corto = "T. mínima",
             unidad = "°C",     agg = "mean", dec = 1, color = "#7D3C98"),
  tx  = list(etiqueta = "Temperatura máxima",  corto = "T. máxima",
             unidad = "°C",     agg = "mean", dec = 1, color = "#E67E22"),
  et0 = list(etiqueta = "Evapotranspiración de referencia", corto = "ET0 ref.",
             unidad = "mm/año", agg = "sum",  dec = 0, color = "#16A085")
)

desconocidas <- setdiff(variables, names(meta))
if (length(desconocidas)) {
  stop("Variable(s) no reconocida(s): ", paste(desconocidas, collapse = ", "),
       ". Disponibles: ", paste(names(meta), collapse = ", "), call. = FALSE)
}

.fmt <- function(v) sub("\\.", ",", format(v, trim = TRUE, scientific = FALSE))

############################################################
# 5. Pesos por area (opcional)
############################################################

pesos <- NULL
if (ponderar_por_area && requireNamespace("sf", quietly = TRUE)) {
  cand <- list.files(file.path(dir_proyecto, "Cuenca", cuenca_nombre),
                     pattern = "_mejorado\\.shp$", full.names = TRUE)
  if (length(cand)) {
    shp <- try(suppressWarnings(sf::st_read(cand[1], quiet = TRUE)), silent = TRUE)
    if (!inherits(shp, "try-error") &&
        all(c("Subcuenca", "area_ha") %in% names(shp))) {
      pesos <- data.frame(
        subcuenca = as.character(shp$Subcuenca),
        peso      = suppressWarnings(as.numeric(as.character(shp$area_ha))),
        stringsAsFactors = FALSE)
      pesos <- pesos[!is.na(pesos$peso) & pesos$peso > 0, ]
      cat("Pesos por area tomados de:", basename(cand[1]),
          "(", nrow(pesos), "subcuencas )\n")
    }
  }
}
if (ponderar_por_area && is.null(pesos)) {
  cat("Sin shapefile _mejorado con area_ha: se usara promedio simple.\n")
}

############################################################
# 6. Lectura y agregacion
############################################################

# Elige, entre los CSV mensuales de una variable, el de rango de anos mas amplio
.archivo_var <- function(var) {
  patron <- paste0("^", cuenca_nombre, "_", var, "_mensual_.*\\.csv$")
  fs <- list.files(dir_datos, pattern = patron, full.names = TRUE)
  if (!length(fs)) return(NA_character_)
  m  <- regmatches(basename(fs), regexpr("(\\d{4})_(\\d{4})\\.csv$", basename(fs)))
  sp <- vapply(seq_along(fs), function(i) {
    if (is.na(m[i]) || !nzchar(m[i])) return(0)
    y <- as.integer(strsplit(sub("\\.csv$", "", m[i]), "_")[[1]])
    y[2] - y[1]
  }, numeric(1))
  fs[which.max(sp)]
}

leer_variable <- function(var) {

  f <- .archivo_var(var)
  if (is.na(f)) {
    cat("  [omitida] no se encontro CSV mensual de '", var, "'\n", sep = "")
    return(NULL)
  }

  d <- read.csv(f, check.names = FALSE, fileEncoding = "UTF-8",
                stringsAsFactors = FALSE)
  names(d)[1] <- "fecha"
  d$fecha <- as.Date(d$fecha)

  largo <- d %>%
    pivot_longer(-fecha, names_to = "subcuenca", values_to = "valor") %>%
    filter(!is.na(valor))

  if (!is.null(subcuencas)) {
    faltan <- setdiff(subcuencas, unique(largo$subcuenca))
    if (length(faltan)) {
      stop("Subcuenca(s) no presente(s) en ", basename(f), ": ",
           paste(faltan, collapse = ", "), call. = FALSE)
    }
    largo <- filter(largo, subcuenca %in% subcuencas)
  }

  # ---- Agregacion espacial: promedio ponderado por area ----
  w <- pesos
  if (!is.null(w)) {
    if (!all(unique(largo$subcuenca) %in% w$subcuenca)) {
      cat("  [aviso] nombres de subcuenca no calzan con el shapefile:",
          "promedio simple en '", var, "'\n", sep = "")
      w <- NULL
    }
  }

  mensual <- if (is.null(w)) {
    largo %>% group_by(fecha) %>%
      summarise(valor = mean(valor), .groups = "drop")
  } else {
    largo %>% left_join(w, by = "subcuenca") %>%
      group_by(fecha) %>%
      summarise(valor = sum(valor * peso) / sum(peso), .groups = "drop")
  }

  # ---- Ano calendario u hidrologico ----
  mm <- as.integer(format(mensual$fecha, "%m"))
  yy <- as.integer(format(mensual$fecha, "%Y"))
  mensual$anio <- if (anio_hidrologico) ifelse(mm >= mes_inicio, yy, yy - 1L) else yy

  # ---- Agregacion temporal ----
  fun <- if (meta[[var]]$agg == "sum") sum else mean
  anual <- mensual %>%
    group_by(anio) %>%
    summarise(valor = fun(valor), n_meses = n(), .groups = "drop")

  if (solo_anios_completos) {
    incompletos <- anual$anio[anual$n_meses < 12]
    if (length(incompletos)) {
      cat("  [", var, "] anos descartados por incompletos: ",
          paste(incompletos, collapse = ", "), "\n", sep = "")
    }
    anual <- filter(anual, n_meses == 12)
  }

  if (!nrow(anual)) {
    cat("  [omitida] '", var, "' no dejo ningun ano completo\n", sep = "")
    return(NULL)
  }

  anual$variable <- var
  anual
}

cat("\n--- Lectura ---\n")
anual <- bind_rows(lapply(variables, leer_variable))
if (!nrow(anual)) {
  stop("Ninguna variable pudo leerse. Revisa 'cuenca_nombre' y que el .Rmd ",
       "de extraccion ya haya corrido.", call. = FALSE)
}

vars_ok <- intersect(variables, unique(anual$variable))
etiqueta_var <- vapply(vars_ok, function(v)
  paste0(meta[[v]]$etiqueta, " (", meta[[v]]$unidad, ")"), character(1))

anual$panel <- factor(etiqueta_var[anual$variable], levels = etiqueta_var)
colores     <- setNames(vapply(vars_ok, function(v) meta[[v]]$color, character(1)),
                        etiqueta_var)

############################################################
# 7. Promedios decadales
############################################################

anual$decada <- (anual$anio %/% 10L) * 10L

decadal <- anual %>%
  group_by(variable, panel, decada) %>%
  summarise(media    = mean(valor),
            n_anios  = n(),
            anio_ini = min(anio),
            anio_fin = max(anio),
            .groups  = "drop") %>%
  filter(n_anios >= decada_min_anios) %>%
  mutate(completa = n_anios >= 10)

decadal$etiqueta <- vapply(seq_len(nrow(decadal)), function(i) {
  v <- decadal$variable[i]
  .fmt(round(decadal$media[i], meta[[v]]$dec))
}, character(1))

# Cambio respecto a la primera decada disponible de cada variable
cambio <- decadal %>%
  group_by(variable, panel) %>%
  arrange(decada, .by_group = TRUE) %>%
  mutate(base = first(media)) %>%
  ungroup() %>%
  mutate(
    tipo   = ifelse(vapply(variable, function(v) meta[[v]]$agg, character(1)) == "sum",
                    "rel", "abs"),
    cambio = ifelse(tipo == "rel", 100 * (media - base) / base, media - base))

.panel_cambio <- function(v)
  paste0(meta[[v]]$corto, if (meta[[v]]$agg == "sum") " (%)" else " (Δ°C)")

cambio$panel_cambio <- factor(
  vapply(cambio$variable, .panel_cambio, character(1)),
  levels = vapply(vars_ok, .panel_cambio, character(1)))

colores_cambio <- setNames(
  vapply(vars_ok, function(v) meta[[v]]$color, character(1)),
  vapply(vars_ok, .panel_cambio, character(1)))

############################################################
# 8. Resumen en consola
############################################################

periodo <- paste0(min(anual$anio), "-", max(anual$anio))

.meses <- c("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
            "agosto", "septiembre", "octubre", "noviembre", "diciembre")
etq_anio <- if (anio_hidrologico) {
  paste0("año hidrológico (", .meses[mes_inicio], "-",
         .meses[(mes_inicio + 10) %% 12 + 1], ")")
} else {
  "año calendario"
}

cat("\n--- Promedios decadales |", cuenca_nombre, "|", periodo, "---\n")
for (v in vars_ok) {
  d <- filter(decadal, variable == v)
  cat("\n", meta[[v]]$etiqueta, " (", meta[[v]]$unidad, ")\n", sep = "")
  for (i in seq_len(nrow(d))) {
    delta <- filter(cambio, variable == v, decada == d$decada[i])$cambio
    cat(sprintf("  %ds  %8s   (%d años)%s%s\n",
                d$decada[i],
                .fmt(round(d$media[i], meta[[v]]$dec)),
                d$n_anios[i],
                if (!d$completa[i]) "  [decada incompleta]" else "",
                if (i == 1) "  <- base" else
                  sprintf("   %+s%s vs base",
                          .fmt(round(delta, 1)),
                          if (meta[[v]]$agg == "sum") "%" else " °C")))
  }
}
cat("\n")

############################################################
# 9. Figura 1: series anuales + promedios decadales
############################################################

anio_max <- max(anual$anio)
hay_megasequia <- inicio_megasequia <= anio_max

pie1 <- paste0(
  "Fuente: CR2MET v2.5 procesado con este repositorio | ", etq_anio,
  " | promedio areal", if (is.null(pesos)) " simple" else " ponderado por área",
  " de ", if (is.null(subcuencas)) "todas las subcuencas" else
    paste(subcuencas, collapse = ", "), "\n",
  "Línea delgada: valor anual. Segmento grueso: promedio de la década. ",
  "Línea de puntos: promedio del período completo.",
  if (hay_megasequia) paste0(" Franja gris: megasequía (", inicio_megasequia, "-).") else "")

media_periodo <- anual %>% group_by(panel) %>%
  summarise(media = mean(valor), .groups = "drop")

p1 <- ggplot()

if (hay_megasequia) {
  p1 <- p1 + annotate("rect",
                      xmin = inicio_megasequia - 0.5, xmax = anio_max + 0.5,
                      ymin = -Inf, ymax = Inf,
                      fill = "grey55", alpha = 0.13)
}

p1 <- p1 +
  geom_hline(data = media_periodo, aes(yintercept = media),
             linetype = "dotted", colour = "grey35", linewidth = 0.4) +
  geom_line(data = anual, aes(anio, valor, colour = panel),
            linewidth = 0.35, alpha = 0.55) +
  geom_point(data = anual, aes(anio, valor, colour = panel),
             size = 0.7, alpha = 0.55) +
  geom_segment(data = decadal,
               aes(x = anio_ini - 0.5, xend = anio_fin + 0.5,
                   y = media, yend = media, colour = panel,
                   linetype = completa),
               linewidth = 1.5) +
  geom_text(data = decadal,
            aes(x = (anio_ini + anio_fin) / 2, y = media, label = etiqueta),
            vjust = -0.9, size = 2.6, fontface = "bold", colour = "grey15") +
  facet_wrap(~ panel, ncol = 1, scales = "free_y", strip.position = "left") +
  scale_colour_manual(values = colores, guide = "none") +
  scale_linetype_manual(values = c(`TRUE` = "solid", `FALSE` = "22"),
                        labels = c(`TRUE` = "década completa",
                                   `FALSE` = "década incompleta (menos de 10 años)"),
                        breaks = c("TRUE", "FALSE"),
                        name = NULL, drop = FALSE) +
  scale_x_continuous(breaks = seq(1900, 2100, 10), minor_breaks = seq(1900, 2100, 5),
                     expand = expansion(mult = 0.01)) +
  labs(title    = paste0("Series anuales y promedios decadales — ", cuenca_nombre),
       subtitle = paste0("CR2MET v2.5 · ", periodo, " · ", etq_anio),
       x = NULL, y = NULL, caption = pie1) +
  theme_bw(base_size = 10) +
  theme(
    strip.placement   = "outside",
    strip.background  = element_blank(),
    strip.text.y.left = element_text(angle = 90, face = "bold", size = 8.5),
    panel.grid.minor.y = element_blank(),
    plot.title        = element_text(face = "bold", size = 12),
    plot.subtitle     = element_text(colour = "grey30", size = 9),
    plot.caption      = element_text(colour = "grey35", size = 7, hjust = 0),
    legend.position   = "top",
    legend.justification = "left",
    legend.margin     = margin(b = -4))

f1 <- file.path(dir_salida, paste0("series_anuales_decadales_", cuenca_nombre, ".png"))
ggsave(f1, p1, width = ancho_cm, height = 5.2 + 3.6 * length(vars_ok),
       units = "cm", dpi = dpi_out, bg = "white", limitsize = FALSE)
cat("Figura series :", f1, "\n")

############################################################
# 10. Figura 2: cambio de cada decada respecto a la primera
############################################################

decada_base <- min(cambio$decada)
cambio$etq <- vapply(seq_len(nrow(cambio)), function(i) {
  if (cambio$decada[i] == decada_base) return("base")
  paste0(if (cambio$cambio[i] > 0) "+" else "",
         .fmt(round(cambio$cambio[i], 1)))
}, character(1))

# Cambios cercanos a cero dan barras invisibles: la etiqueta va siempre
# arriba de la linea del cero para que no quede colgando bajo el eje.
cambio$vj <- ifelse(cambio$cambio >= -0.05, -0.45, 1.35)

p2 <- ggplot(cambio, aes(factor(decada), cambio, fill = panel_cambio)) +
  geom_hline(yintercept = 0, colour = "grey30", linewidth = 0.4) +
  geom_col(width = 0.68, alpha = 0.9) +
  geom_text(aes(label = etq, vjust = vj), size = 2.7, colour = "grey15") +
  facet_wrap(~ panel_cambio, ncol = 1, scales = "free_y",
             strip.position = "left") +
  scale_fill_manual(values = colores_cambio, guide = "none") +
  scale_y_continuous(expand = expansion(mult = 0.16)) +
  labs(title    = paste0("Cambio por década respecto a la primera — ", cuenca_nombre),
       subtitle = paste0("Base: década de ", min(cambio$decada),
                         " · precipitación en %, temperaturas en Δ°C · ", etq_anio),
       x = "Década", y = NULL,
       caption = paste0("Calculado sobre los promedios decadales de la figura ",
                        "anterior. Las décadas incompletas (menos de 10 años) ",
                        "se incluyen igual: ver el conteo en promedios_decadales_",
                        cuenca_nombre, ".csv")) +
  theme_bw(base_size = 10) +
  theme(
    strip.placement   = "outside",
    strip.background  = element_blank(),
    strip.text.y.left = element_text(angle = 90, face = "bold", size = 8.5),
    panel.grid.major.x = element_blank(),
    plot.title        = element_text(face = "bold", size = 12),
    plot.subtitle     = element_text(colour = "grey30", size = 9),
    plot.caption      = element_text(colour = "grey35", size = 7, hjust = 0))

f2 <- file.path(dir_salida, paste0("cambio_decadal_", cuenca_nombre, ".png"))
ggsave(f2, p2, width = ancho_cm, height = 4.5 + 3.2 * length(vars_ok),
       units = "cm", dpi = dpi_out, bg = "white", limitsize = FALSE)
cat("Figura cambio :", f2, "\n")

############################################################
# 11. Tablas
############################################################

tabla_anual <- anual %>%
  select(anio, variable, valor) %>%
  pivot_wider(names_from = variable, values_from = valor) %>%
  arrange(anio)

tabla_decadal <- decadal %>%
  left_join(select(cambio, variable, decada, cambio), by = c("variable", "decada")) %>%
  select(variable, decada, anio_ini, anio_fin, n_anios, completa, media, cambio) %>%
  arrange(variable, decada)

t1 <- file.path(dir_salida, paste0("series_anuales_", cuenca_nombre, ".csv"))
t2 <- file.path(dir_salida, paste0("promedios_decadales_", cuenca_nombre, ".csv"))
write.csv(tabla_anual,   t1, row.names = FALSE, fileEncoding = "UTF-8")
write.csv(tabla_decadal, t2, row.names = FALSE, fileEncoding = "UTF-8")
cat("Tabla anual   :", t1, "\n")
cat("Tabla decadal :", t2, "\n")

cat("\nListo. Salidas en:", dir_salida, "\n")
