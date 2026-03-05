# Extracción de Series Climáticas CR2MET v2.5 por Subcuenca

**Script:** `pr_tn_tx_tm_bestday_extraccion_cr2met2_5_web_DPL.Rmd`  
**Versión:** 5  
**Fuente de datos:** [CR2MET v2.5 — Centro de Ciencia del Clima y la Resiliencia (CR)²](https://www.cr2.cl/datos-productos-grillados/)  
**Salida compatible con:** WEAP (Water Evaluation And Planning System)

---

## ¿Qué hace este script?

Descarga archivos NetCDF mensuales del repositorio público CR2MET v2.5 (resolución 0.05°, ~5 km) y extrae series de tiempo diarias de variables climáticas para cada subcuenca definida en un shapefile. Las series extraídas se exportan en formato compatible con WEAP.

El flujo completo es:

```
FTP CR2MET (NetCDF mensual)
        ↓
  Descarga en memoria temporal
        ↓
  Extracción por polígono (media areal)
        ↓
  Tabla larga → agregación diaria/mensual
        ↓
  CSV formato WEAP  +  CSV estándar
```

---

## Variables procesadas

| Variable | Nombre CR2MET | Directorio remoto | Agregación diaria | Agregación mensual |
|----------|--------------|-------------------|-------------------|--------------------|
| Precipitación | `pr` | `pr/v2.5_best_day/` | Suma | Suma |
| Temperatura mínima | `tmin` | `txn/v2.5_best_day/` | Media | Media |
| Temperatura máxima | `tmax` | `txn/v2.5_best_day/` | Media | Media |
| Temperatura media | *(tmin+tmax)/2* | — | Media | Media |
| Evapotranspiración de referencia | `et0` | `et0/v2.5_best_day/` | Suma | Suma |

> **Nota:** `tmin` y `tmax` vienen en el mismo archivo NetCDF dentro del directorio `txn/`.

---

## Requisitos

### Paquetes R

```r
# Generales
tidyverse, lubridate, janitor

# Espaciales
sf, terra

# Web
rvest, stringr, xml2
```

Instalar con:

```r
install.packages(c("tidyverse", "lubridate", "janitor",
                   "sf", "terra", "rvest", "stringr", "xml2"))
```

> `lwgeom` es opcional. Si está instalado, el script lo ignora (las funciones que lo usaban fueron reemplazadas por equivalentes nativos de `sf`).

### Archivos necesarios

```
/
├── Cuenca/
│   └── <cuenca_nombre>/
│       └── <archivo_shp>          ← Shapefile de subcuencas
├── Results/                       ← Se crea automáticamente
└── pr_tn_tx_tm_bestday_...Rmd     ← Este script
```

### Conexión a internet

El script descarga los NetCDF directamente desde `ftp.cr2.cl`. Se requiere acceso sin proxy a ese dominio.

---

## Configuración

Todos los parámetros ajustables están en el **Chunk 1** del script:

```r
cuenca_nombre    <- "Quilimari"        # Nombre de la cuenca (para carpetas y archivos)
archivo_shp      <- "Quilimari_WEAP.shp"
cuenca_shp       <- file.path(getwd(), "Cuenca", cuenca_nombre, archivo_shp)
nombre_subcuenca <- "Name"             # Columna del shapefile con nombres de subcuenca

years_to_keep    <- 1970:2025          # Rango de años a extraer
months_to_keep   <- NULL               # NULL = todos; ej. c(12,1,2) solo para DJF
```

Para cambiar de cuenca, basta con modificar esos cinco parámetros.

---

## Estructura del shapefile

El shapefile de subcuencas debe tener:

- Una columna con el nombre de cada subcuenca (definida en `nombre_subcuenca`). En el ejemplo: columna `Name`.
- CRS definido. Si viene sin CRS, el script intenta inferirlo (lon/lat vs. UTM 19S). Si la inferencia no es correcta para tu shapefile, ajustar `EPSG:32719` en el Chunk 3.
- Geometrías válidas. El script aplica reparación automática robusta en varios intentos antes de fallar.

---

## Archivos de salida

Los resultados se guardan en `Results/<cuenca_nombre>/` con la nomenclatura:

```
<cuenca>_pp_diaria_cr2met2.5_<año_ini>_<año_fin>.csv      ← formato WEAP
<cuenca>_pp_mensual_cr2met2.5_<año_ini>_<año_fin>.csv     ← CSV estándar
<cuenca>_tn_diaria_...csv
<cuenca>_tn_mensual_...csv
<cuenca>_tx_diaria_...csv
<cuenca>_tx_mensual_...csv
<cuenca>_tav_diaria_...csv
<cuenca>_tav_mensual_...csv
<cuenca>_et0_diaria_...csv
<cuenca>_et0_mensual_...csv
```

### Formato WEAP (archivos diarios)

Los archivos diarios usan el formato requerido por WEAP para series de tiempo:

```
#,1,2,...,N
$Columns = Date,SubC_1,SubC_2,...,SubC_N
01/01/1970,3.2,1.8,...
01/02/1970,0.0,0.0,...
```

Los archivos mensuales se exportan como CSV estándar (para revisión o uso en otros entornos).

---

## Descripción de los chunks

| Chunk | Contenido |
|-------|-----------|
| 1 | Librerías, directorio de trabajo y parámetros de la cuenca |
| 2 | URLs del FTP CR2MET y funciones para listar/filtrar archivos remotos |
| 3 | Lectura y reparación robusta del shapefile; dissolve por subcuenca; transformación a WGS84 |
| 4 | Función `fn_extract_from_nc()`: extrae la media areal de una variable para un polígono |
| 5 | Loops de descarga y extracción para PR, temperatura y ET0 |
| 6 | Agregaciones diarias y mensuales (largo → ancho) |
| 7–8 | Función de exportación custom y escritura de archivos de salida |

---

## Notas técnicas

- **S2 desactivado durante el dissolve** (`sf_use_s2(FALSE)`): evita errores topológicos en GEOS al procesar polígonos complejos.
- **Descarga secuencial con limpieza**: cada NetCDF se descarga a un archivo temporal, se procesa para todos los polígonos y se elimina antes de pasar al siguiente. El uso de disco en todo momento es de 1 archivo NetCDF (~50–150 MB).
- **Tolerancia a fallos**: cada descarga y cada extracción están envueltas en `tryCatch`. Si un archivo mensual falla (timeout, 404), el loop continúa y el fallo se reporta en consola sin abortar el proceso completo.
- **Reparación geométrica en cascada**: el dissolve intenta hasta 3 estrategias antes de lanzar error (make_valid → buffer(0) → simplify mínimo).

---

## Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---------|---------------|----------|
| `Variable 'pr' not found in NetCDF` | El nombre de variable cambió en CR2MET | Revisar con `terra::rast(nc) |> names()` y ajustar `var =` en el loop |
| `No se pudo parsear año/mes del archivo` | El patrón del nombre cambió en CR2MET | Ajustar el regex `_(\d{4})_(\d{2})_005deg\.nc$` en `filter_by_year_month` y `fn_extract_from_nc` |
| Polígono con todos `NA` | Subcuenca fuera del dominio del raster CR2MET (lat > -17.5° o lat < -56°) | Verificar extensión del shapefile |
| `CRS ausente: se asignó EPSG:32719` | El .prj del shapefile está vacío o corrupto | Asignar CRS manualmente antes de correr el script |

---

## Contacto y mantención

Script desarrollado para la extracción de forzantes climáticos en modelos WEAP de cuencas de Chile central.  
Ante cambios en la estructura del FTP de CR2MET, los parámetros más probables a actualizar son las URLs en el **Chunk 2** y el patrón de nombre de archivo en `filter_by_year_month`.
