# `scr/` — Scripts auxiliares para el flujo CR2Met → WEAP

Scripts que automatizan la incorporación de los productos CR2Met
(generados con el Rmd del repositorio) en un modelo WEAP a través de la
[WEAP API](https://www.weap21.org/webhelp/weapapplication.htm).

---

## `preproceso_SIG_mejorado.R`

Preproceso GIS standalone. Genera la versión `_mejorado.shp/.dbf` del
shapefile de subcuencas **sin** descargar ni procesar NetCDF — útil cuando
solo quieres regenerar el shapefile mejorado para alimentar al script Python
de WEAP, o cuando agregaste/editaste una subcuenca y no quieres volver a
correr toda la extracción climática.

Equivale a la **sección 3** del Rmd principal. Hace:

- lee el shapefile original (`Cuenca/<cuenca>/<archivo>.shp`)
- repara geometrías (`st_make_valid`, buffer(0), simplify si falla)
- dissolve robusto por la columna `Subcuenca`
- asigna `ID` correlativo
- calcula `area_ha` (2 decimales) reproyectando a UTM hemisferio sur
- proyecta a WGS84
- calcula `lat_deg` (latitud del centroide en grados, 2 decimales)
- guarda `<archivo>_mejorado.shp` en la misma carpeta

### Uso

1. Editar el bloque **CONFIG** al inicio: `cuenca_nombre`, `archivo_shp`,
   `nombre_subcuenca` (igual que en el Rmd).
2. Correr:
   ```powershell
   Rscript "C:\Users\David\Documents\GitHub_DPL\CR2Met_extraction\scr\preproceso_SIG_mejorado.R"
   ```
   o `Source` en RStudio.

Requisitos: paquetes R `sf` y `dplyr` (`rstudioapi` opcional, solo para
auto-detectar la raíz del proyecto desde RStudio).

---

## `mapa_grilla_CR2Met.R`

Dibuja la grilla CR2MET v2.5 (0,05° ≈ 5 km) sobre la cuenca y genera **dos
mapas** de la misma escena:

| Salida | CRS | Ejes |
|--------|-----|------|
| `..._latlon.png` | WGS 84 geográficas (EPSG:4326) | grados con sufijo O/S |
| `..._UTM.png` | UTM zona inferida del centroide (ej. EPSG:32719) | km |

Ambos incluyen escala gráfica en **km**, flecha de **norte**, **leyenda** y un
pie con los metadatos de la grilla. La escala se calcula en la unidad del CRS
de cada mapa: 1000 m/km en UTM, y en lat/lon los grados de longitud por km
medidos con `st_distance` en la latitud central (no una constante fija), así
que ambas barras representan la misma distancia real.

El **relleno de cada celda es la fracción de su área cubierta por la cuenca**,
que es exactamente el peso que aplica `terra::extract(..., exact = TRUE)` en el
Rmd de extracción. Los centroides marcan qué celdas entrarían con la regla
"centroid-in" (`+` dentro, `×` fuera), lo que hace visible el sesgo discutido
en el README principal: en Aconcagua, 347 celdas intersectan la cuenca pero
solo 290 tienen el centroide dentro.

También exporta la grilla recortada como GeoPackage (`.gpkg`) con el campo
`frac_pct`, para abrirla en QGIS.

### Uso

1. Editar el bloque **PARAMETROS**: `cuenca_nombre`, `archivo_shp`,
   `nombre_subcuenca` (igual que en el Rmd). Si existe el
   `<archivo>_mejorado.shp` lo usa automáticamente.
2. Correr:
   ```powershell
   Rscript "C:\Users\David\Documents\GitHub_DPL\CR2Met_extraction\scr\mapa_grilla_CR2Met.R"
   ```
   o `Source` en RStudio.

Salidas en `Results/<cuenca_nombre>/mapas/`.

Otros parámetros útiles: `buffer_celdas` (celdas de contexto alrededor del
bbox), `epsg_utm` (forzar zona), `mostrar_centroides` /
`centroides_solo_uso`, `etiquetar_subcuencas`, `etiquetar_celdas` (escribe el
% de cobertura dentro de cada celda), `pos_escala` / `pos_norte` (posición en
fracción del panel) y `ancho_cm` / `dpi_out`.

La geometría de la grilla se lee del primer NetCDF que encuentre en
`nc_cache/`; si no hay ninguno, la reconstruye con la geometría nominal de
CR2MET v2.5 (extent −77…−66 / −57…−17, celda 0,05°).

Requisitos: `sf`, `ggplot2`, `dplyr`. Opcionales: `terra` (leer la grilla del
NetCDF), `ggrepel` (etiquetas de subcuenca sin solape), `rstudioapi`.

---

## `weap_create_band_branches.py`

Crea las **bandas de elevación como sub-ramas** de cada catchment existente en
un modelo WEAP, y le conecta a cada banda su clima y su área.

### Qué hace

Para cada banda detectada en los CSV de CR2Met:

1. Crea una sub-rama bajo el catchment padre, nombrada `b<n>` (p.ej. `b1`, `b2`).
2. Asigna la expresión de variables del método **Soil Moisture (Rainfall Runoff)**:

   | Variable        | Expresión                                                       |
   | --------------- | --------------------------------------------------------------- |
   | `Precipitation` | `ReadFromFile("Datos\Clima_CR2Met_v2.5\<area>_pp_diaria_*.csv", "<label>")`  |
   | `Temperature`   | `ReadFromFile("Datos\Clima_CR2Met_v2.5\<area>_tav_diaria_*.csv", "<label>")` |
   | `Area`          | valor numérico en hectáreas, desde el `.dbf` (`area_ha`)        |
   | `Latitude`      | latitud del centroide en grados, desde el `.dbf` (`lat_deg`)    |

3. Guarda el modelo (`SaveArea`).

### Cómo mapea labels → ramas

El label de columna en el CSV (p.ej. `Aconcagua en Blanco_2`) es la llave común
entre las tres fuentes:

- columna de los CSV (`$Columns = fecha, Aconcagua en Blanco_2, ...`)
- campo **`Subcuenca`** del `.dbf` (con `area_ha` asociada)
- ruta de la rama en WEAP: `\Demand Sites and Catchments\Aconcagua en Blanco\b2`

El script separa por el último `_`: lo de antes es el catchment padre (debe
existir ya en el modelo), el sufijo es el número de banda.

### Detalles importantes

- **`ReadFromFile` con rutas RELATIVAS** al *area directory* (`Datos\...`).
  WEAP resuelve estas rutas respecto a la carpeta del area, por lo que el
  modelo es portable: copiar el `.areas` a otra PC sigue funcionando.
- **Timestep weekly desde CSV diario**: WEAP agrega solo, por fecha — precipitación
  se suma, temperatura promedia. No hay que pre-procesar nada.
- **Unidad de área**: la unidad del variable `Area` **NO se puede setear via API**
  (intentar `WEAP.BranchVariable(...).Unit = "Hectare"` falla). El script asume
  que el modelo ya tiene la unidad en Hectare y escribe el valor en hectáreas
  directo. Si tu modelo está en km², setea `AREA_SCALE = 0.01` para convertir.
- **Idempotente**: si la rama `b<n>` ya existe, no la duplica; siempre
  re-escribe las expresiones (útil para re-ejecutar tras editar los CSV).
- **Otras variables del Soil Moisture** (Kc, Soil Water Capacity, etc.)
  *no* se tocan — quedan con sus valores por defecto / heredados.

### Requisitos

| Componente | Cómo conseguirlo                              |
| ---------- | --------------------------------------------- |
| WEAP       | Abierto, con el area objetivo como ActiveArea |
| Python     | 3.x                                           |
| `pywin32`  | `pip install pywin32`                         |

Los CSV de clima y el `.dbf` con `area_ha` deben existir dentro del area
directory del modelo:

```
<WEAP.AreasDirectory>\<ActiveArea>\
├── Datos\Clima_CR2Met_v2.5\
│   ├── <ActiveArea>_pp_diaria_cr2met2.5_1975_2026.csv
│   └── <ActiveArea>_tav_diaria_cr2met2.5_1975_2026.csv
└── SIG\
    └── <ActiveArea>_v2.dbf            (campos: Subcuenca, ID, area_ha)
```

Los CSV se generan con el `.Rmd` raíz del repo; el `.dbf` debe ser la
versión "mejorada" con bandas (una fila por `<catchment>_<n>`).

### Uso

1. Abrir WEAP en el area objetivo.
2. Verificar las **3 opciones de configuración** al inicio del script:
   - `CATCHMENTS_ROOT` (por defecto `\Demand Sites and Catchments`)
   - `AREA_SCALE`     (1.0 si la unidad WEAP es hectárea; 0.01 si es km²)
   - `DRY_RUN`        (**dejar en `True` la primera vez**)
3. Correr:
   ```powershell
   python "C:\Users\David\Documents\GitHub_DPL\CR2Met_extraction\scr\weap_create_band_branches.py"
   ```
4. Revisar el log impreso:
   - `[create]` / `[exists]` para cada banda
   - expresiones que se escribirían en cada variable
   - lista de catchments `[MISSING]` (si el nombre del catchment en el modelo
     no coincide con el prefijo del label hay que arreglarlo antes)
5. Si todo se ve bien, cambiar `DRY_RUN = False` y volver a correr.
   El modelo queda guardado al final.

### Salida típica (DRY_RUN)

```
Connected to WEAP. Active area: Aconcagua_EmbCatemu
Area directory:  C:\...\WEAP Areas\Aconcagua_EmbCatemu

[create]  \Demand Sites and Catchments\Aconcagua en Blanco\b2
           Precipitation = ReadFromFile("Datos\Clima_CR2Met_v2.5\...pp_diaria...csv", "Aconcagua en Blanco_2")
           Temperature   = ReadFromFile("Datos\Clima_CR2Met_v2.5\...tav_diaria...csv", "Aconcagua en Blanco_2")
           Area          = 2424.79
...
----- summary -----
branches to create : 28
branches existing  : 0
catchments missing : 0
DRY_RUN = True  (no changes made)
```

### Adaptar a otro modelo / cuenca

El script ya es independiente del nombre del area: usa
`WEAP.ActiveArea.Name` para armar todas las rutas. Para procesar otra cuenca
basta con:

1. Abrirla en WEAP como ActiveArea.
2. Tener los CSV y el `.dbf` con la convención de nombres y carpetas de arriba,
   dentro del area directory.
3. Correr el script.

Si tu modelo usa otra raíz de árbol (no `\Demand Sites and Catchments`),
ajusta `CATCHMENTS_ROOT`.

---

## Troubleshooting

| Síntoma                                       | Causa probable                                                            |
| --------------------------------------------- | ------------------------------------------------------------------------- |
| `[MISSING] catchment not in model: X`         | El nombre del catchment en WEAP no coincide con el prefijo del label CSV. |
| Áreas se ven mil veces más grandes/chicas     | Unidad del Area variable distinta a Hectare → ajusta `AREA_SCALE`.        |
| `pywin32` no encuentra `WEAP.WEAPApplication` | WEAP no está abierto, o no está instalado/registrado COM.                 |
| `ReadFromFile` falla al recalcular            | La ruta relativa no resuelve → verifica que el CSV esté en `Datos\Clima_CR2Met_v2.5\` dentro del area directory. |
| Falta `area_ha` para algún label              | El `.dbf` no tiene una fila por banda. El script lo reporta como `WARNING` y deja Area vacía. |
